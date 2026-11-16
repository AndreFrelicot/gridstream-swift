//
//  StreamingIntegrationTests.swift
//  gridstream-macosTests
//
//  Byte serving of the real stream route: whole file, ranges and content
//  types. Session auth on media routes and range clamping/416 are covered by
//  ServerSecurityTests.
//

import XCTest
import Vapor
@testable import gridstream_macos

final class StreamingIntegrationTests: XCTestCase {

    private static let fileSize = 10_000

    private var directory: URL!
    private var app: Application!
    private var fileData: Data!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StreamingIntegrationTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Byte i is i % 256, so any slice can be checked
        fileData = Data((0..<Self.fileSize).map { UInt8($0 % 256) })
        try fileData.write(to: directory.appendingPathComponent("test_video.mp4"))
        try Data("mov".utf8).write(to: directory.appendingPathComponent("clip.mov"))
        try Data("m4v".utf8).write(to: directory.appendingPathComponent("clip.m4v"))

        let source = SourceDirectory(id: UUID(), path: directory.path, isEnabled: true)
        app = try await StreamRouteTesting.makeApp(
            videos: [
                StreamRouteTesting.video("mp4", relativePath: "test_video.mp4", in: source),
                StreamRouteTesting.video("mov", relativePath: "clip.mov", in: source),
                StreamRouteTesting.video("m4v", relativePath: "clip.m4v", in: source),
                StreamRouteTesting.video("deleted", relativePath: "deleted.mp4", in: source),
            ],
            sourceDirectories: [source]
        )
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        try? FileManager.default.removeItem(at: directory)
        app = nil
        directory = nil
        fileData = nil
    }

    // MARK: - Whole file

    func testRequestWithoutRangeReturnsTheWholeFile() async throws {
        let response = try await StreamRouteTesting.stream("mp4", in: app)

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(response.headers.contentType, HTTPMediaType(type: "video", subType: "mp4"))
        let body = try await StreamRouteTesting.body(of: response, in: app)
        XCTAssertEqual(body, fileData)
    }

    // MARK: - Ranges

    func testClosedRangeReturnsThoseBytes() async throws {
        try await assertRange("bytes=0-99", contentRange: "bytes 0-99/10000", slice: 0..<100)
        try await assertRange("bytes=5000-5999", contentRange: "bytes 5000-5999/10000", slice: 5000..<6000)
    }

    func testOpenEndedRangeRunsToTheEndOfTheFile() async throws {
        try await assertRange("bytes=9000-", contentRange: "bytes 9000-9999/10000", slice: 9000..<10_000)
    }

    func testSuffixRangeReturnsTheLastBytes() async throws {
        try await assertRange("bytes=-100", contentRange: "bytes 9900-9999/10000", slice: 9900..<10_000)
    }

    private func assertRange(
        _ range: String,
        contentRange: String,
        slice: Range<Int>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let response = try await StreamRouteTesting.stream("mp4", range: range, in: app)

        XCTAssertEqual(response.status, .partialContent, range, file: file, line: line)
        XCTAssertEqual(response.headers.first(name: .contentRange), contentRange, file: file, line: line)
        let body = try await StreamRouteTesting.body(of: response, in: app)
        XCTAssertEqual(body, fileData.subdata(in: slice), range, file: file, line: line)
    }

    // MARK: - Metering

    func testMeteredBodiesServeTheSameBytesAndCountThem() async throws {
        let monitor = ConnectionMonitor()
        app.connectionMonitor = monitor

        let whole = try await StreamRouteTesting.stream("mp4", in: app)
        let wholeBody = try await StreamRouteTesting.body(of: whole, in: app)
        XCTAssertEqual(wholeBody, fileData)
        XCTAssertEqual(whole.headers.first(name: .contentLength), "\(Self.fileSize)")

        try await assertRange("bytes=5000-5999", contentRange: "bytes 5000-5999/10000", slice: 5000..<6000)
        try await assertRange("bytes=-100", contentRange: "bytes 9900-9999/10000", slice: 9900..<10_000)

        let sample = monitor.sample()
        XCTAssertEqual(sample.bytesSent, Int64(Self.fileSize + 1_000 + 100))
        XCTAssertEqual(sample.videosServed, 1, "Back-to-back requests for one video are one stream")
        XCTAssertEqual(sample.clients.first?.streams.map(\.filename), ["test_video.mp4"])
    }

    // MARK: - Content types

    func testContentTypeFollowsTheFileExtension() async throws {
        let mov = try await StreamRouteTesting.stream("mov", in: app)
        let m4v = try await StreamRouteTesting.stream("m4v", in: app)

        XCTAssertEqual(mov.headers.contentType, HTTPMediaType(type: "video", subType: "quicktime"))
        XCTAssertEqual(m4v.headers.contentType, HTTPMediaType(type: "video", subType: "mp4"))
    }

    func testContentTypeForWebM() {
        XCTAssertEqual(
            VideoStreamRoutes.contentTypeForExtension("video.webm"),
            HTTPMediaType(type: "video", subType: "webm")
        )
    }

    // MARK: - Missing

    func testUnknownVideoIs404() async throws {
        let response = try await StreamRouteTesting.stream("0123456789abcdef", in: app)
        XCTAssertEqual(response.status, .notFound)
    }

    func testCatalogEntryWhoseFileIsGoneIs404() async throws {
        let response = try await StreamRouteTesting.stream("deleted", in: app)
        XCTAssertEqual(response.status, .notFound)
    }
}

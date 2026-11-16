import Foundation
import XCTest
@testable import gridstream_macos

final class VideoFileEnumeratorTests: XCTestCase {
    private var rootURL: URL!

    override func setUp() async throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoFileEnumeratorTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        rootURL = rootURL.resolvingSymlinksInPath()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: rootURL)
        rootURL = nil
    }

    private func source(_ url: URL) -> SourceDirectory {
        SourceDirectory(id: UUID(), path: url.path, isEnabled: true)
    }

    @discardableResult
    private func write(_ path: String, size: Int = Int(FileHasher.minimumFileSize)) throws -> URL {
        let url = rootURL.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: size).write(to: url)
        return url
    }

    func testListsSupportedExtensionsAtMinimumSizeAndExcludesOtherFiles() throws {
        let directory = source(rootURL)
        try write("minimum.mp4")
        try write("uppercase.MOV")
        try write("nested/clip.m4v")
        try write("too-small.mp4", size: Int(FileHasher.minimumFileSize) - 1)
        try write("unsupported.avi")
        try write("scrub-generated.mp4")
        try write("nested/scrub-generated.mov")
        try write(".hidden.mp4")
        try write(".hidden-folder/clip.mp4")
        try FileManager.default.createDirectory(at: rootURL.appendingPathComponent("folder.mp4"), withIntermediateDirectories: true)

        let listing = VideoFileEnumerator.findVideoFiles(in: rootURL, sourceDirectory: directory)

        XCTAssertFalse(listing.hadErrors)
        XCTAssertEqual(Set(listing.files.map { $0.url.lastPathComponent }), ["minimum.mp4", "uppercase.MOV", "clip.m4v"])
        XCTAssertTrue(listing.files.allSatisfy { $0.sourceDirectory.id == directory.id })
    }

    func testNestedSourcesChooseDeepestOwnerRegardlessOfEnumerationOrder() throws {
        let topURL = try write("top.mp4")
        let nestedURL = try write("nested/deeper/clip.mp4")
        let top = source(rootURL)
        let nested = source(rootURL.appendingPathComponent("nested"))
        let deepest = source(rootURL.appendingPathComponent("nested/deeper"))
        let topListing = VideoFileEnumerator.findVideoFiles(in: rootURL, sourceDirectory: top)
        let nestedListing = VideoFileEnumerator.findVideoFiles(in: URL(fileURLWithPath: nested.path), sourceDirectory: nested)
        let deepestListing = VideoFileEnumerator.findVideoFiles(in: URL(fileURLWithPath: deepest.path), sourceDirectory: deepest)
        let entries = topListing.files + nestedListing.files + deepestListing.files

        for order in [entries, Array(entries.reversed())] {
            let assigned = VideoFileEnumerator.assigningFilesToDeepestDirectory(order)
            XCTAssertEqual(assigned.count, 2)
            XCTAssertEqual(assigned.first { $0.url.standardizedFileURL.path == topURL.standardizedFileURL.path }?.sourceDirectory.id, top.id)
            XCTAssertEqual(assigned.first { $0.url.standardizedFileURL.path == nestedURL.standardizedFileURL.path }?.sourceDirectory.id, deepest.id)
        }
    }

    func testStandardizedPathsAreDeduplicated() {
        let directory = source(rootURL)
        let canonical = rootURL.appendingPathComponent("clip.mp4")
        let alternate = rootURL.appendingPathComponent("nested/../clip.mp4")

        let assigned = VideoFileEnumerator.assigningFilesToDeepestDirectory([
            (url: canonical, sourceDirectory: directory),
            (url: alternate, sourceDirectory: directory)
        ])

        XCTAssertEqual(assigned.count, 1)
        XCTAssertEqual(assigned.first?.url, canonical)
    }

    func testReadableDirectoryRejectsMissingPathsAndRegularFiles() throws {
        let file = try write("clip.mp4")

        XCTAssertTrue(VideoFileEnumerator.isReadableDirectory(atPath: rootURL.path))
        XCTAssertFalse(VideoFileEnumerator.isReadableDirectory(atPath: rootURL.appendingPathComponent("missing").path))
        XCTAssertFalse(VideoFileEnumerator.isReadableDirectory(atPath: file.path))
    }

    func testEmptyReadableDirectoryHasNoEnumerationError() {
        let listing = VideoFileEnumerator.findVideoFiles(in: rootURL, sourceDirectory: source(rootURL))

        XCTAssertTrue(listing.files.isEmpty)
        XCTAssertFalse(listing.hadErrors)
    }

    func testMissingDirectoryReportsEnumerationError() {
        let missing = rootURL.appendingPathComponent("missing")

        let listing = VideoFileEnumerator.findVideoFiles(in: missing, sourceDirectory: source(missing))

        XCTAssertTrue(listing.files.isEmpty)
        XCTAssertTrue(listing.hadErrors)
    }

    func testUnreadableSubdirectoryReportsErrorAndKeepsReadableSiblings() throws {
        try write("readable.mp4")
        try write("locked/clip.mp4")
        let locked = rootURL.appendingPathComponent("locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        }
        guard !VideoFileEnumerator.isReadableDirectory(atPath: locked.path) else {
            throw XCTSkip("This process can read directories with no permission bits")
        }

        let listing = VideoFileEnumerator.findVideoFiles(in: rootURL, sourceDirectory: source(rootURL))

        XCTAssertTrue(listing.hadErrors)
        XCTAssertEqual(listing.files.map { $0.url.lastPathComponent }, ["readable.mp4"])
    }
}

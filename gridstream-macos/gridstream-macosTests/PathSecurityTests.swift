//
//  PathSecurityTests.swift
//  gridstream-macosTests
//
//  Path containment of the real stream route: a catalog entry can only
//  serve a file inside its source folder.
//

import XCTest
import Vapor
@testable import gridstream_macos

final class PathSecurityTests: XCTestCase {

    private var root: URL!
    private var app: Application!

    /// fileId → relative path inside the `Clips` source folder.
    private static let clipsEntries: [(fileId: String, relativePath: String)] = [
        ("valid", "clip.mp4"),
        ("nested", "nested/dir/clip.mp4"),
        ("hidden", ".hidden/clip.mp4"),
        ("dotted", "clip.2024.01.mp4"),
        ("currentDir", "./clip.mp4"),
        ("innerLink", "inner-link.mp4"),
        ("missing", "missing.mp4"),
        ("parent", "../outside.mp4"),
        ("nestedParent", "nested/../../outside.mp4"),
        ("absolute", "/etc/hosts"),
        ("empty", ""),
        ("escapingLink", "escape.mp4"),
        ("siblingLink", "sibling.mp4"),
    ]

    override func setUp() async throws {
        // root/
        //   outside.mp4            not in any source folder
        //   Clips-evil/a.mp4       sibling folder sharing the "Clips" prefix
        //   Clips/                 source folder
        //   ClipsLink -> Clips     source folder registered through a symlink
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory.appendingPathComponent("PathSecurityTests_\(UUID().uuidString)")
        let clips = root.appendingPathComponent("Clips")
        for directory in ["Clips/nested/dir", "Clips/.hidden", "Clips-evil"] {
            try fileManager.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true)
        }
        for file in ["outside.mp4", "Clips-evil/a.mp4", "Clips/clip.mp4", "Clips/nested/dir/clip.mp4",
                     "Clips/.hidden/clip.mp4", "Clips/clip.2024.01.mp4"] {
            try Data("video".utf8).write(to: root.appendingPathComponent(file))
        }
        try fileManager.createSymbolicLink(
            at: clips.appendingPathComponent("escape.mp4"),
            withDestinationURL: root.appendingPathComponent("outside.mp4")
        )
        try fileManager.createSymbolicLink(
            at: clips.appendingPathComponent("sibling.mp4"),
            withDestinationURL: root.appendingPathComponent("Clips-evil/a.mp4")
        )
        try fileManager.createSymbolicLink(
            at: clips.appendingPathComponent("inner-link.mp4"),
            withDestinationURL: clips.appendingPathComponent("clip.mp4")
        )
        try fileManager.createSymbolicLink(at: root.appendingPathComponent("ClipsLink"), withDestinationURL: clips)

        let clipsSource = SourceDirectory(id: UUID(), path: clips.path, isEnabled: true)
        let linkedSource = SourceDirectory(id: UUID(), path: root.appendingPathComponent("ClipsLink").path, isEnabled: true)
        let unknownSource = SourceDirectory(id: UUID(), path: clips.path, isEnabled: true)

        var videos = Self.clipsEntries.map { StreamRouteTesting.video($0.fileId, relativePath: $0.relativePath, in: clipsSource) }
        videos.append(StreamRouteTesting.video("viaLinkedSource", relativePath: "clip.mp4", in: linkedSource))
        videos.append(StreamRouteTesting.video("unknownSource", relativePath: "clip.mp4", in: unknownSource))

        app = try await StreamRouteTesting.makeApp(videos: videos, sourceDirectories: [clipsSource, linkedSource])
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        try? FileManager.default.removeItem(at: root)
        app = nil
        root = nil
    }

    private func status(of fileId: String) async throws -> HTTPStatus {
        try await StreamRouteTesting.stream(fileId, in: app).status
    }

    // MARK: - Rejected

    func testParentDirectoryComponentsAreForbidden() async throws {
        let parent = try await status(of: "parent")
        let nestedParent = try await status(of: "nestedParent")
        XCTAssertEqual(parent, .forbidden)
        XCTAssertEqual(nestedParent, .forbidden)
    }

    func testAbsoluteAndEmptyPathsAreForbidden() async throws {
        let absolute = try await status(of: "absolute")
        let empty = try await status(of: "empty")
        XCTAssertEqual(absolute, .forbidden)
        XCTAssertEqual(empty, .forbidden)
    }

    func testSymlinkLeavingTheSourceFolderIsForbidden() async throws {
        let escaping = try await status(of: "escapingLink")
        XCTAssertEqual(escaping, .forbidden)
    }

    func testSymlinkIntoASiblingFolderWithTheSamePrefixIsForbidden() async throws {
        let sibling = try await status(of: "siblingLink")
        XCTAssertEqual(sibling, .forbidden)
    }

    // MARK: - Accepted

    func testFilesInsideTheSourceFolderAreServed() async throws {
        for fileId in ["valid", "nested", "hidden", "dotted", "currentDir", "innerLink"] {
            let response = try await StreamRouteTesting.stream(fileId, in: app)
            XCTAssertEqual(response.status, .ok, "\(fileId) should be served")
            let body = try await StreamRouteTesting.body(of: response, in: app)
            XCTAssertEqual(body, Data("video".utf8), "\(fileId) should serve its file")
        }
    }

    func testSourceFolderRegisteredThroughASymlinkIsServed() async throws {
        let linked = try await status(of: "viaLinkedSource")
        XCTAssertEqual(linked, .ok)
    }

    // MARK: - Missing

    func testUnknownVideoAndMissingFileAre404() async throws {
        let unknown = try await status(of: "not-in-catalog")
        let missing = try await status(of: "missing")
        XCTAssertEqual(unknown, .notFound)
        XCTAssertEqual(missing, .notFound)
    }

    func testVideoOfAnUnknownSourceFolderIs500() async throws {
        let orphan = try await status(of: "unknownSource")
        XCTAssertEqual(orphan, .internalServerError)
    }
}

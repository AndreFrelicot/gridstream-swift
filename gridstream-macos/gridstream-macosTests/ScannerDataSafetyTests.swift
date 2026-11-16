//
//  ScannerDataSafetyTests.swift
//  gridstream-macosTests
//
//  A scan must never destroy user data because a folder or a file could not
//  be read. Missing files are soft-deleted (missing_since) and restored when
//  they come back; hard deletion only happens through purgeMissing.
//

import GridStreamAPI
import XCTest
import GRDB
@testable import gridstream_macos

final class ScannerDataSafetyTests: XCTestCase {

    private var rootURL: URL!
    private var databaseManager: DatabaseManager!
    private var videosURL: URL!

    override func setUp() async throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScannerDataSafetyTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        // Enumerated paths are resolved (/var → /private/var): use the same form
        rootURL = URL(fileURLWithPath: realpath(rootURL.path, nil).map { String(cString: $0) } ?? rootURL.path)
        databaseManager = DatabaseManager(databasePath: rootURL.appendingPathComponent("test.sqlite"))
        try await databaseManager.initialize()
        videosURL = rootURL.appendingPathComponent("videos")
        try FileManager.default.createDirectory(at: videosURL, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: videosURL.path)
        try await databaseManager.close()
        try? FileManager.default.removeItem(at: rootURL)
        databaseManager = nil
        rootURL = nil
        videosURL = nil
    }

    // MARK: - Helpers

    private func makeDirectory(path: String) -> SourceDirectory {
        SourceDirectory(id: UUID(), path: path, isEnabled: true)
    }

    @discardableResult
    private func insertRecord(
        fileId: String,
        path: String,
        sourceDirectoryId: UUID,
        lastModified: Double = 1_000,
        missingSince: Double? = nil
    ) async throws -> VideoFileRecord {
        let record = VideoFileRecord(
            fileId: fileId,
            path: path,
            sourceDirectoryId: sourceDirectoryId,
            filename: (path as NSString).lastPathComponent,
            fileSize: 4_242,
            duration: 60,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: lastModified,
            rating: 7,
            missingSince: missingSince
        )
        try await databaseManager.write { db in
            let mutable = record
            try mutable.insert(db)
            let tag = TagRecord(name: "tag-\(fileId)", color: TagColorPalette.allColors[0])
            let mutableTag = tag
            try mutableTag.insert(db)
            let videoTag = VideoTagRecord(videoFileId: fileId, tagId: tag.id)
            try videoTag.insert(db)
        }
        return record
    }

    /// A file big enough to be listed (≥ 192 KB) that AVFoundation cannot analyse.
    @discardableResult
    private func writeUnreadableVideo(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(repeating: 0x42, count: 300_000).write(to: url)
        return url
    }

    private func fetchRecord(fileId: String) async throws -> VideoFileRecord? {
        try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(fileId, in: db)
        }
    }

    private func tagCount(fileId: String) async throws -> Int {
        try await databaseManager.read { db in
            VideoTagRecord.findByVideoFileId(fileId, in: db).count
        }
    }

    // MARK: - Unavailable folders keep their records

    func testMissingFolderKeepsAllRecords() async throws {
        let missingFolder = rootURL.appendingPathComponent("unplugged-disk").path
        let directory = makeDirectory(path: missingFolder)
        try await insertRecord(fileId: "keep_a", path: missingFolder + "/a.mp4", sourceDirectoryId: directory.id)
        try await insertRecord(fileId: "keep_b", path: missingFolder + "/b.mp4", sourceDirectoryId: directory.id)

        let scanner = VideoScanner(databaseManager: databaseManager)
        let items = try await scanner.scan(directories: [directory])

        let unavailable = await scanner.unavailableDirectoryIds
        XCTAssertEqual(unavailable, [directory.id])
        XCTAssertEqual(Set(items.map(\.fileId)), ["keep_a", "keep_b"], "Records of an unavailable folder stay in the catalog")
        for fileId in ["keep_a", "keep_b"] {
            let record = try await fetchRecord(fileId: fileId)
            XCTAssertNotNil(record)
            XCTAssertNil(record?.missingSince, "An unavailable folder must not soft-delete its records")
            XCTAssertEqual(record?.rating, 7)
            let tags = try await tagCount(fileId: fileId)
            XCTAssertEqual(tags, 1)
        }
    }

    func testEmptyFolderWithKnownRecordsIsTreatedAsUnavailable() async throws {
        let directory = makeDirectory(path: videosURL.path)
        try await insertRecord(fileId: "keep_empty", path: videosURL.path + "/gone.mp4", sourceDirectoryId: directory.id)

        let scanner = VideoScanner(databaseManager: databaseManager)
        _ = try await scanner.scan(directories: [directory])

        let unavailable = await scanner.unavailableDirectoryIds
        XCTAssertEqual(unavailable, [directory.id])
        let record = try await fetchRecord(fileId: "keep_empty")
        XCTAssertNil(record?.missingSince)
    }

    func testUnreadableFolderKeepsAllRecords() async throws {
        let directory = makeDirectory(path: videosURL.path)
        try writeUnreadableVideo(named: "present.mp4", in: videosURL)
        try await insertRecord(fileId: "keep_locked", path: videosURL.path + "/other.mp4", sourceDirectoryId: directory.id)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: videosURL.path)

        let scanner = VideoScanner(databaseManager: databaseManager)
        _ = try await scanner.scan(directories: [directory])

        let record = try await fetchRecord(fileId: "keep_locked")
        XCTAssertNotNil(record)
        XCTAssertNil(record?.missingSince)
    }

    // MARK: - Soft delete

    func testFileAbsentFromReadableFolderIsSoftDeleted() async throws {
        let directory = makeDirectory(path: videosURL.path)
        try writeUnreadableVideo(named: "still-here.mp4", in: videosURL)
        try await insertRecord(fileId: "gone", path: videosURL.path + "/deleted.mp4", sourceDirectoryId: directory.id)

        let scanner = VideoScanner(databaseManager: databaseManager)
        let items = try await scanner.scan(directories: [directory])

        XCTAssertFalse(items.contains { $0.fileId == "gone" })
        let record = try await fetchRecord(fileId: "gone")
        XCTAssertNotNil(record, "Missing files are soft-deleted, never purged by a scan")
        XCTAssertNotNil(record?.missingSince)
        let tags = try await tagCount(fileId: "gone")
        XCTAssertEqual(tags, 1, "Tags of a missing video survive")

        let liveIds = try await databaseManager.read { db in try VideoFileRecord.liveFileIds(in: db) }
        XCTAssertFalse(liveIds.contains("gone"))
    }

    func testFileWhoseAnalysisFailsKeepsItsRecordUnchanged() async throws {
        let directory = makeDirectory(path: videosURL.path)
        let url = try writeUnreadableVideo(named: "corrupt.mp4", in: videosURL)
        // Stored lastModified differs from the file's, forcing a re-analysis that fails.
        let original = try await insertRecord(fileId: "corrupt", path: url.path, sourceDirectoryId: directory.id, lastModified: 1_000)

        let scanner = VideoScanner(databaseManager: databaseManager)
        let items = try await scanner.scan(directories: [directory])

        XCTAssertTrue(items.contains { $0.fileId == "corrupt" })
        let record = try await fetchRecord(fileId: "corrupt")
        XCTAssertNil(record?.missingSince)
        XCTAssertEqual(record?.fileSize, original.fileSize)
        XCTAssertEqual(record?.duration, original.duration)
        XCTAssertEqual(record?.lastModified, original.lastModified)
        XCTAssertEqual(record?.rating, 7)
    }

    func testFileReappearingAtSamePathIsRestored() async throws {
        let directory = makeDirectory(path: videosURL.path)
        let url = try writeUnreadableVideo(named: "back.mp4", in: videosURL)
        try await insertRecord(fileId: "back", path: url.path, sourceDirectoryId: directory.id, missingSince: 123)

        let scanner = VideoScanner(databaseManager: databaseManager)
        let items = try await scanner.scan(directories: [directory])

        XCTAssertTrue(items.contains { $0.fileId == "back" })
        let record = try await fetchRecord(fileId: "back")
        XCTAssertNil(record?.missingSince, "A file found again at its path is restored")
        XCTAssertEqual(record?.rating, 7)
    }

    func testMovedFileWithSameFileIdIsRestored() async throws {
        guard let sample = SampleVideoLocator.find() else {
            throw XCTSkip("No sample video available on this system")
        }
        let directory = makeDirectory(path: videosURL.path)
        try writeUnreadableVideo(named: "anchor.mp4", in: videosURL)
        let original = videosURL.appendingPathComponent("clip.mov")
        try FileManager.default.copyItem(at: sample, to: original)

        let scanner = VideoScanner(databaseManager: databaseManager)
        let firstItems = try await scanner.scan(directories: [directory])
        let fileId = try XCTUnwrap(firstItems.first { $0.filename == "clip.mov" }?.fileId)

        // The file disappears: soft-deleted.
        let parked = rootURL.appendingPathComponent("clip.mov")
        try FileManager.default.moveItem(at: original, to: parked)
        _ = try await scanner.scan(directories: [directory])
        let missingRecord = try await fetchRecord(fileId: fileId)
        XCTAssertNotNil(missingRecord?.missingSince)

        // It comes back under another name: same content, same fileId.
        let renamed = videosURL.appendingPathComponent("renamed.mov")
        try FileManager.default.moveItem(at: parked, to: renamed)
        _ = try await scanner.scan(directories: [directory])
        let restored = try await fetchRecord(fileId: fileId)
        XCTAssertNil(restored?.missingSince)
        XCTAssertEqual(restored?.path, renamed.path)
        XCTAssertEqual(restored?.id, missingRecord?.id)
    }

    func testPurgeMissingDeletesOnlyMissingRecordsWithAssociations() async throws {
        let directoryId = UUID()
        try await insertRecord(fileId: "present", path: "/x/present.mp4", sourceDirectoryId: directoryId)
        try await insertRecord(fileId: "missing", path: "/x/missing.mp4", sourceDirectoryId: directoryId, missingSince: 1)

        let purged = try await databaseManager.write { db in try VideoFileRecord.purgeMissing(in: db) }

        XCTAssertEqual(purged, 1)
        let missing = try await fetchRecord(fileId: "missing")
        XCTAssertNil(missing)
        let missingTags = try await tagCount(fileId: "missing")
        XCTAssertEqual(missingTags, 0)
        let present = try await fetchRecord(fileId: "present")
        XCTAssertNotNil(present)
        let presentTags = try await tagCount(fileId: "present")
        XCTAssertEqual(presentTags, 1)
    }

    func testCachedVideosExcludeMissingRecords() async throws {
        let directory = makeDirectory(path: videosURL.path)
        try await insertRecord(fileId: "cached_present", path: videosURL.path + "/a.mp4", sourceDirectoryId: directory.id)
        try await insertRecord(fileId: "cached_missing", path: videosURL.path + "/b.mp4", sourceDirectoryId: directory.id, missingSince: 5)

        let items = try await VideoScanner(databaseManager: databaseManager).loadCachedVideos(sourceDirectories: [directory])

        XCTAssertEqual(items.map(\.fileId), ["cached_present"])
    }
}

/// Locates a system video large enough to be scanned.
enum SampleVideoLocator {
    static func find() -> URL? {
        let roots = [
            "/System/Library/Desktop Pictures/.wallpapers",
            "/System/Library/CoreServices",
            "/Library/Desktop Pictures"
        ]
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where ["mp4", "m4v", "mov"].contains(url.pathExtension.lowercased()) {
                if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64,
                   size >= FileHasher.minimumFileSize {
                    return url
                }
            }
        }
        return nil
    }
}

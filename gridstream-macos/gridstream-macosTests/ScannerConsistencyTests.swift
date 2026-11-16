//
//  ScannerConsistencyTests.swift
//  gridstream-macosTests
//
//  Scanner edge cases: concurrent scans, nested folders, duplicate content,
//  files re-encoded in place, and writes that must not clobber user data.
//

import GridStreamAPI
import XCTest
import GRDB
@testable import gridstream_macos

final class ScannerConsistencyTests: XCTestCase {

    private var rootURL: URL!
    private var databaseManager: DatabaseManager!
    private var videosURL: URL!

    override func setUp() async throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScannerConsistencyTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        // Enumerated paths are resolved (/var → /private/var): use the same form
        rootURL = URL(fileURLWithPath: realpath(rootURL.path, nil).map { String(cString: $0) } ?? rootURL.path)
        videosURL = rootURL.appendingPathComponent("videos")
        try FileManager.default.createDirectory(at: videosURL, withIntermediateDirectories: true)
        databaseManager = DatabaseManager(databasePath: rootURL.appendingPathComponent("test.sqlite"))
        try await databaseManager.initialize()
    }

    override func tearDown() async throws {
        try await databaseManager.close()
        try? FileManager.default.removeItem(at: rootURL)
        databaseManager = nil
        rootURL = nil
        videosURL = nil
    }

    private func sampleVideo() throws -> URL {
        guard let sample = SampleVideoLocator.find() else {
            throw XCTSkip("No sample video available on this system")
        }
        return sample
    }

    private func allRecords() async throws -> [VideoFileRecord] {
        try await databaseManager.read { db in try VideoFileRecord.fetchAll(db) }
    }

    // MARK: - Concurrent scans

    func testConcurrentScansDoNotInterleave() async throws {
        let sample = try sampleVideo()
        for index in 0..<3 {
            try FileManager.default.copyItem(at: sample, to: videosURL.appendingPathComponent("clip\(index).mov"))
            // Distinct content per copy so each file gets its own fileId
            let handle = try FileHandle(forWritingTo: videosURL.appendingPathComponent("clip\(index).mov"))
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(repeating: UInt8(index), count: 64))
            try handle.close()
        }
        let directory = SourceDirectory(path: videosURL.path)
        let scanner = VideoScanner(databaseManager: databaseManager)

        async let first = scanner.scan(directories: [directory])
        async let second = scanner.scan(directories: [directory])
        async let third = scanner.fullRescan(directories: [directory])
        let results = try await [first, second, third]

        let records = try await allRecords()
        XCTAssertEqual(Set(records.map(\.fileId)).count, records.count, "No duplicate fileIds")
        XCTAssertTrue(records.allSatisfy { $0.missingSince == nil })
        for result in results {
            XCTAssertEqual(Set(result.map(\.fileId)), Set(records.map(\.fileId)))
        }
    }

    // MARK: - Nested folders

    func testNestedFoldersAssignFilesToTheDeepestFolder() async throws {
        let sample = try sampleVideo()
        let nestedURL = videosURL.appendingPathComponent("Season")
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sample, to: nestedURL.appendingPathComponent("clip.mov"))

        let outer = SourceDirectory(path: videosURL.path)
        let inner = SourceDirectory(path: nestedURL.path)
        let scanner = VideoScanner(databaseManager: databaseManager)

        for _ in 0..<2 {
            let items = try await scanner.scan(directories: [outer, inner])
            XCTAssertEqual(items.count, 1, "A file is listed once even with nested folders")
            XCTAssertEqual(items.first?.sourceDirectoryId, inner.id)
            XCTAssertEqual(items.first?.relativePath, "clip.mov")
        }

        let records = try await allRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.sourceDirectoryId, inner.id)
    }

    func testAddingNestedOrContainingFolderIsRejected() throws {
        let existing = ["/Volumes/Media/Movies"]
        func validate(_ path: String) throws {
            try ConfigurationService.validateNewDirectory(path: path, existingPaths: existing)
        }

        XCTAssertThrowsError(try validate("/Volumes/Media/Movies/2024")) { error in
            XCTAssertEqual(error as? SourceDirectoryValidationError, .nestedInExisting("/Volumes/Media/Movies"))
        }
        XCTAssertThrowsError(try validate("/Volumes/Media")) { error in
            XCTAssertEqual(error as? SourceDirectoryValidationError, .containsExisting("/Volumes/Media/Movies"))
        }
        XCTAssertThrowsError(try validate("/Volumes/Media/Movies/"))
        XCTAssertNoThrow(try validate("/Volumes/Media/Movies 2"))
    }

    func testRelativePathUsesPrefixStripping() {
        let directory = SourceDirectory(path: "/V/S")
        let record = VideoFileRecord(
            fileId: "f", path: "/V/S/sub/x.mp4", sourceDirectoryId: directory.id, filename: "x.mp4",
            fileSize: 1, duration: 1, width: 1, height: 1, codec: "h264", lastModified: 0
        )
        XCTAssertEqual(VideoItem.relativePath(of: record, in: directory), "sub/x.mp4")
        XCTAssertEqual(VideoItem.relativePath(of: record, in: nil), "x.mp4", "Unknown folder must not strip every slash")
        XCTAssertEqual(VideoItem.relativePath(of: record, in: SourceDirectory(path: "/Other")), "x.mp4")
        let trap = VideoFileRecord(
            fileId: "g", path: "/V/S/V/S/y.mp4", sourceDirectoryId: directory.id, filename: "y.mp4",
            fileSize: 1, duration: 1, width: 1, height: 1, codec: "h264", lastModified: 0
        )
        XCTAssertEqual(VideoItem.relativePath(of: trap, in: directory), "V/S/y.mp4")
    }

    // MARK: - Duplicate content

    func testDuplicateContentAtTwoLivePathsDoesNotOscillate() async throws {
        let sample = try sampleVideo()
        try FileManager.default.copyItem(at: sample, to: videosURL.appendingPathComponent("a.mov"))
        try FileManager.default.copyItem(at: sample, to: videosURL.appendingPathComponent("b.mov"))
        let directory = SourceDirectory(path: videosURL.path)
        let scanner = VideoScanner(databaseManager: databaseManager)

        _ = try await scanner.scan(directories: [directory])
        let firstPath = try await allRecords().first?.path
        let versionAfterFirstScan = try await databaseManager.fetchCatalogVersion()

        for _ in 0..<2 {
            _ = try await scanner.scan(directories: [directory])
            let records = try await allRecords()
            XCTAssertEqual(records.count, 1)
            XCTAssertEqual(records.first?.path, firstPath, "The record must keep its path")
            XCTAssertNil(records.first?.missingSince)
        }

        let versionAfterRescans = try await databaseManager.fetchCatalogVersion()
        XCTAssertEqual(versionAfterRescans, versionAfterFirstScan, "Rescans of an unchanged library must not bump the catalog")
    }

    // MARK: - Modified in place

    func testFileModifiedInPlacePurgesScrubFramesButKeepsFileId() async throws {
        let sample = try sampleVideo()
        let url = videosURL.appendingPathComponent("clip.mov")
        try FileManager.default.copyItem(at: sample, to: url)
        let directory = SourceDirectory(path: videosURL.path)
        let scanner = VideoScanner(databaseManager: databaseManager)
        _ = try await scanner.scan(directories: [directory])
        let originalRecords = try await allRecords()
        let original = try XCTUnwrap(originalRecords.first)

        // Stored frames and a stale stored size: the next scan sees new content.
        try await ScrubFrameCache.shared.storeFrames(
            videoId: original.fileId,
            frames: [(time: 0, data: Data([1])), (time: 2, data: Data([2]))],
            using: databaseManager
        )
        try await databaseManager.write { db in
            try db.execute(sql: "UPDATE video_files SET file_size = 1, rating = 9 WHERE id = ?", arguments: [original.id])
        }
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(500)], ofItemAtPath: url.path)

        _ = try await scanner.scan(directories: [directory])

        let updatedRecords = try await allRecords()
        let updated = try XCTUnwrap(updatedRecords.first)
        XCTAssertEqual(updated.fileId, original.fileId)
        XCTAssertEqual(updated.scrubFrameCount, 0)
        XCTAssertEqual(updated.rating, 9, "Scanner must not overwrite user data")
        let remainingFrames = try await databaseManager.read { db in
            try ScrubFrameRecord.count(forFileId: original.fileId, in: db)
        }
        XCTAssertEqual(remainingFrames, 0)
    }

    // MARK: - Overflow-safe playback stats

    func testPlaybackStatsClampViewTimeAndSaturateCounters() async throws {
        try await databaseManager.write { db in
            let record = VideoFileRecord(
                fileId: "stats", path: "/x/stats.mp4", sourceDirectoryId: UUID(), filename: "stats.mp4",
                fileSize: 1, duration: 1, width: 1, height: 1, codec: "h264", lastModified: 0
            )
            try record.insert(db)
        }

        let first = try await databaseManager.write { db in
            try VideoFileRecord.applyPlaybackReport(fileId: "stats", incrementPlayCount: false, addViewTime: Int.max, in: db)
        }
        XCTAssertEqual(first?.totalViewTime, 86_400)
        let second = try await databaseManager.write { db in
            try VideoFileRecord.applyPlaybackReport(fileId: "stats", incrementPlayCount: false, addViewTime: Int.max, in: db)
        }
        XCTAssertEqual(second?.totalViewTime, 172_800)
        let negative = try await databaseManager.write { db in
            try VideoFileRecord.applyPlaybackReport(fileId: "stats", incrementPlayCount: false, addViewTime: -500, in: db)
        }
        XCTAssertEqual(negative?.totalViewTime, 172_800, "Negative view time is clamped to zero")

        try await databaseManager.write { db in
            try db.execute(sql: "UPDATE video_files SET play_count = ?, total_view_time = ? WHERE file_id = 'stats'",
                           arguments: [Int.max, Int.max - 10])
        }
        let saturated = try await databaseManager.write { db in
            try VideoFileRecord.applyPlaybackReport(fileId: "stats", incrementPlayCount: true, addViewTime: 100, in: db)
        }
        XCTAssertEqual(saturated?.playCount, Int.max)
        XCTAssertEqual(saturated?.totalViewTime, Int.max)
    }
}

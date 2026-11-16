//
//  PlayCountIntegrationTests.swift
//  gridstream-macosTests
//
//  Integration tests for play count tracking feature.
//

import GridStreamAPI
import XCTest
import GRDB
@testable import gridstream_macos

final class PlayCountIntegrationTests: XCTestCase {

    var testDatabaseURL: URL!
    var databaseManager: DatabaseManager!

    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GridStreamPlayCountIntegrationTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        testDatabaseURL = testDir.appendingPathComponent("test_gridstream.sqlite")
        databaseManager = DatabaseManager(databasePath: testDatabaseURL)
        try await databaseManager.initialize()
    }

    override func tearDown() async throws {
        try await databaseManager.close()
        let testDir = testDatabaseURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: testDir)
        databaseManager = nil
        testDatabaseURL = nil
    }

    // MARK: - Integration Test 1: Full playback session workflow

    func testFullPlaybackSessionWorkflow() async throws {
        // Given: A video exists in the database
        let sourceDirectoryId = UUID()
        let video = VideoFileRecord(
            fileId: "integration_test_video",
            path: "/test/path/video.mp4",
            sourceDirectoryId: sourceDirectoryId,
            filename: "video.mp4",
            fileSize: 1000,
            duration: 300.0, // 5 minutes
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: Date().timeIntervalSince1970,
            playCount: 0,
            totalViewTime: 0
        )

        try await databaseManager.write { db in
            try video.insert(db)
        }

        // Simulate a playback session of 4 minutes (240 seconds)
        // This should result in 2 play count increments (2x 2-minute chunks)

        // First 2-minute chunk
        try await databaseManager.write { db in
            guard var record = try VideoFileRecord.findByFileId(video.fileId, in: db) else {
                XCTFail("Video not found")
                return
            }
            record.playCount += 1
            record.totalViewTime += 120 // 2 minutes
            record.touch()
            try record.update(db)
        }

        // Second 2-minute chunk
        try await databaseManager.write { db in
            guard var record = try VideoFileRecord.findByFileId(video.fileId, in: db) else {
                XCTFail("Video not found")
                return
            }
            record.playCount += 1
            record.totalViewTime += 120 // 2 more minutes
            record.touch()
            try record.update(db)
        }

        // Verify final state
        let finalVideo = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(video.fileId, in: db)
        }

        XCTAssertNotNil(finalVideo)
        XCTAssertEqual(finalVideo?.playCount, 2, "Should have 2 play counts for 4 minutes watched")
        XCTAssertEqual(finalVideo?.totalViewTime, 240, "Should have 240 seconds of total view time")
    }

    // MARK: - Integration Test 2: Play count persists across database close/reopen

    func testPlayCountPersistsAcrossDatabaseReopen() async throws {
        // Given: A video with accumulated play count
        let sourceDirectoryId = UUID()
        let video = VideoFileRecord(
            fileId: "persistence_test_video",
            path: "/test/path/video.mp4",
            sourceDirectoryId: sourceDirectoryId,
            filename: "video.mp4",
            fileSize: 1000,
            duration: 120.0,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: Date().timeIntervalSince1970,
            playCount: 5,
            totalViewTime: 600
        )

        try await databaseManager.write { db in
            try video.insert(db)
        }

        // Close the database
        try await databaseManager.close()

        // Reopen the database
        databaseManager = DatabaseManager(databasePath: testDatabaseURL)
        try await databaseManager.initialize()

        // Verify the data persisted
        let persistedVideo = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(video.fileId, in: db)
        }

        XCTAssertNotNil(persistedVideo)
        XCTAssertEqual(persistedVideo?.playCount, 5, "Play count should persist after database reopen")
        XCTAssertEqual(persistedVideo?.totalViewTime, 600, "Total view time should persist after database reopen")
    }

    // MARK: - Integration Test 3: Filter queries work with play count data

    func testPlayCountFilterQueriesWorkCorrectly() async throws {
        let sourceDirectoryId = UUID()

        // Create videos with varying play counts
        let testData: [(String, Int)] = [
            ("video_never_played", 0),
            ("video_played_once", 1),
            ("video_played_5_times", 5),
            ("video_played_10_times", 10),
            ("video_played_3_times", 3)
        ]

        for (fileId, playCount) in testData {
            let video = VideoFileRecord(
                fileId: fileId,
                path: "/test/path/\(fileId).mp4",
                sourceDirectoryId: sourceDirectoryId,
                filename: "\(fileId).mp4",
                fileSize: 1000,
                duration: 120.0,
                width: 1920,
                height: 1080,
                codec: "h264",
                lastModified: Date().timeIntervalSince1970,
                playCount: playCount,
                totalViewTime: playCount * 120
            )
            try await databaseManager.write { db in
                try video.insert(db)
            }
        }

        // Test unplayed filter
        let unplayedVideos = try await databaseManager.read { db in
            try VideoFileRecord.findUnplayed(in: db)
        }
        XCTAssertEqual(unplayedVideos.count, 1)
        XCTAssertEqual(unplayedVideos.first?.fileId, "video_never_played")

        // Test min play count filter
        let playedAtLeast5 = try await databaseManager.read { db in
            try VideoFileRecord.findByMinPlayCount(5, in: db)
        }
        XCTAssertEqual(playedAtLeast5.count, 2) // 5 and 10

        // Test most played
        let mostPlayed = try await databaseManager.read { db in
            try VideoFileRecord.findMostPlayed(limit: 3, in: db)
        }
        XCTAssertEqual(mostPlayed.count, 3)
        XCTAssertEqual(mostPlayed[0].playCount, 10)
        XCTAssertEqual(mostPlayed[1].playCount, 5)
        XCTAssertEqual(mostPlayed[2].playCount, 3)
    }

    // MARK: - Integration Test 4: Migration applies correctly to existing videos

    func testMigrationAppliesDefaultsToExistingVideos() async throws {
        // The migration should have already run on setUp
        // Any video without explicit play count values should have defaults of 0

        let sourceDirectoryId = UUID()
        let video = VideoFileRecord(
            fileId: "migration_test_video",
            path: "/test/path/video.mp4",
            sourceDirectoryId: sourceDirectoryId,
            filename: "video.mp4",
            fileSize: 1000,
            duration: 120.0,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: Date().timeIntervalSince1970
            // Note: not explicitly setting playCount or totalViewTime
        )

        try await databaseManager.write { db in
            try video.insert(db)
        }

        let savedVideo = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(video.fileId, in: db)
        }

        XCTAssertNotNil(savedVideo)
        XCTAssertEqual(savedVideo?.playCount, 0, "Default play count should be 0")
        XCTAssertEqual(savedVideo?.totalViewTime, 0, "Default total view time should be 0")
    }

    // MARK: - Integration Test 5: VideoItem includes play count in API response

    func testVideoItemIncludesPlayCountFields() {
        // Test that VideoItem model correctly includes the new fields
        let videoItem = VideoItem(
            fileId: "test_video",
            filename: "test.mp4",
            relativePath: "videos/test.mp4",
            sourceDirectoryId: UUID(),
            duration: 120.0,
            width: 1920,
            height: 1080,
            codec: "h264",
            fileSize: 1000,
            lastModified: Date(),
            rating: 5,
            playCount: 7,
            totalViewTime: 840
        )

        XCTAssertEqual(videoItem.playCount, 7)
        XCTAssertEqual(videoItem.totalViewTime, 840)
    }

    // MARK: - Integration Test 6: Concurrent updates don't cause issues

    func testConcurrentPlayCountUpdatesHandledCorrectly() async throws {
        let sourceDirectoryId = UUID()
        let video = VideoFileRecord(
            fileId: "concurrent_test_video",
            path: "/test/path/video.mp4",
            sourceDirectoryId: sourceDirectoryId,
            filename: "video.mp4",
            fileSize: 1000,
            duration: 120.0,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: Date().timeIntervalSince1970,
            playCount: 0,
            totalViewTime: 0
        )

        try await databaseManager.write { db in
            try video.insert(db)
        }

        // Simulate concurrent updates by running multiple updates in parallel
        let updateCount = 5
        let databaseManager: DatabaseManager = self.databaseManager
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<updateCount {
                group.addTask {
                    try? await databaseManager.write { db in
                        guard var record = try VideoFileRecord.findByFileId(video.fileId, in: db) else {
                            return
                        }
                        record.playCount += 1
                        record.totalViewTime += 120
                        record.touch()
                        try record.update(db)
                    }
                }
            }
        }

        // Verify the final count equals the number of updates
        let finalVideo = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(video.fileId, in: db)
        }

        XCTAssertNotNil(finalVideo)
        XCTAssertEqual(finalVideo?.playCount, updateCount, "All concurrent updates should be applied")
        XCTAssertEqual(finalVideo?.totalViewTime, updateCount * 120)
    }

    // MARK: - Integration Test 7: Index improves query performance

    func testPlayCountIndexExists() async throws {
        // Verify that the play_count index was created by the migration
        let indexExists = try await databaseManager.read { db -> Bool in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_video_files_play_count'"
            )
            return !rows.isEmpty
        }

        XCTAssertTrue(indexExists, "Index idx_video_files_play_count should exist")
    }
}

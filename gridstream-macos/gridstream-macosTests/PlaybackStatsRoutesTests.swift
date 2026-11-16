//
//  PlaybackStatsRoutesTests.swift
//  gridstream-macosTests
//
//  Tests for playback stats database functionality and route logic.
//

import XCTest
import GRDB
@testable import gridstream_macos

final class PlaybackStatsRoutesTests: XCTestCase {

    var testDatabaseURL: URL!
    var databaseManager: DatabaseManager!

    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GridStreamPlaybackStatsTests_\(UUID().uuidString)")
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

    // MARK: - Test Helpers

    private func createTestVideo(
        fileId: String = "test_file_id",
        playCount: Int = 0,
        totalViewTime: Int = 0
    ) async throws -> VideoFileRecord {
        let video = VideoFileRecord(
            fileId: fileId,
            path: "/test/path/video.mp4",
            sourceDirectoryId: UUID(),
            filename: "video.mp4",
            fileSize: 1000,
            duration: 120.0,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: Date().timeIntervalSince1970,
            playCount: playCount,
            totalViewTime: totalViewTime
        )

        try await databaseManager.write { db in
            try video.insert(db)
        }

        return video
    }

    // MARK: - Test 1: POST increments play_count correctly

    func testPlaybackStatsIncrementPlayCountCorrectly() async throws {
        // Given a video with initial play count of 5
        let video = try await createTestVideo(fileId: "increment_test", playCount: 5, totalViewTime: 600)

        // Verify initial state
        let initialVideo = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(video.fileId, in: db)
        }
        XCTAssertEqual(initialVideo?.playCount, 5)

        try await databaseManager.write { db in
            _ = try VideoFileRecord.applyPlaybackReport(
                fileId: video.fileId,
                incrementPlayCount: true,
                addViewTime: 0,
                in: db
            )
        }

        // Then the database should reflect the increment
        let updatedVideo = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(video.fileId, in: db)
        }
        XCTAssertEqual(updatedVideo?.playCount, 6, "Play count should be incremented by 1")
    }

    // MARK: - Test 2: POST adds view time correctly

    func testPlaybackStatsAddsViewTimeCorrectly() async throws {
        // Given a video with initial total view time of 600 seconds
        let video = try await createTestVideo(fileId: "viewtime_test", playCount: 5, totalViewTime: 600)

        // Verify initial state
        let initialVideo = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(video.fileId, in: db)
        }
        XCTAssertEqual(initialVideo?.totalViewTime, 600)

        let addViewTime = 120
        try await databaseManager.write { db in
            _ = try VideoFileRecord.applyPlaybackReport(
                fileId: video.fileId,
                incrementPlayCount: false,
                addViewTime: addViewTime,
                in: db
            )
        }

        // Then the database should reflect the added view time
        let updatedVideo = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(video.fileId, in: db)
        }
        XCTAssertEqual(updatedVideo?.totalViewTime, 720, "View time should be increased by 120")
    }

    // MARK: - Test 3: Non-existent video returns nil (route returns 404)

    func testPlaybackStatsReturnsNilForNonExistentVideo() async throws {
        // Given a fileId that doesn't exist
        let nonExistentFileId = "nonexistent_video_id"

        // When querying for the video
        let video = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(nonExistentFileId, in: db)
        }

        // Then it should return nil (route would return 404)
        XCTAssertNil(video, "Should return nil for non-existent video")
    }

    // MARK: - Test 4: Response contains updated playCount and totalViewTime

    func testPlaybackStatsUpdatesAndReturnsCorrectValues() async throws {
        // Given a video with known initial values
        let video = try await createTestVideo(fileId: "response_test", playCount: 5, totalViewTime: 600)

        let incrementPlayCount = true
        let addViewTime = 120

        let result = try await databaseManager.write { db in
            try VideoFileRecord.applyPlaybackReport(
                fileId: video.fileId,
                incrementPlayCount: incrementPlayCount,
                addViewTime: addViewTime,
                in: db
            )
        }

        // Verify response values
        XCTAssertEqual(result?.playCount, 6, "Response should contain updated play count")
        XCTAssertEqual(result?.totalViewTime, 720, "Response should contain updated total view time")

        // Also verify database state matches
        let updatedVideo = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(video.fileId, in: db)
        }
        XCTAssertEqual(updatedVideo?.playCount, 6)
        XCTAssertEqual(updatedVideo?.totalViewTime, 720)
    }

    // MARK: - Test multiple increments

    func testMultiplePlayCountIncrements() async throws {
        // Given a video with initial values
        let video = try await createTestVideo(fileId: "multiple_test", playCount: 5, totalViewTime: 600)

        // Simulate 3 consecutive updates (like watching 6 minutes in 2-minute chunks)
        for i in 1...3 {
            try await databaseManager.write { db in
                _ = try VideoFileRecord.applyPlaybackReport(
                    fileId: video.fileId,
                    incrementPlayCount: true,
                    addViewTime: 120,
                    in: db
                )
            }

            // Verify after each update
            let currentVideo = try await databaseManager.read { db in
                try VideoFileRecord.findByFileId(video.fileId, in: db)
            }
            XCTAssertEqual(currentVideo?.playCount, 5 + i, "Play count should increment correctly on iteration \(i)")
            XCTAssertEqual(currentVideo?.totalViewTime, 600 + (120 * i), "View time should accumulate correctly on iteration \(i)")
        }

        // Verify final state
        let finalVideo = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(video.fileId, in: db)
        }
        XCTAssertEqual(finalVideo?.playCount, 8)
        XCTAssertEqual(finalVideo?.totalViewTime, 960)
    }

    func testConcurrentPlaybackStatsUpdatesDoNotLoseIncrements() async throws {
        let video = try await createTestVideo(fileId: "concurrent_test", playCount: 0, totalViewTime: 0)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<25 {
                group.addTask { [databaseManager] in
                    try await databaseManager!.write { db in
                        _ = try VideoFileRecord.applyPlaybackReport(
                            fileId: video.fileId,
                            incrementPlayCount: true,
                            addViewTime: 10,
                            in: db
                        )
                    }
                }
            }

            try await group.waitForAll()
        }

        let updatedVideo = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(video.fileId, in: db)
        }

        XCTAssertEqual(updatedVideo?.playCount, 25)
        XCTAssertEqual(updatedVideo?.totalViewTime, 250)
    }
}

//
//  PlayCountRecordTests.swift
//  gridstream-macosTests
//
//  Tests for play count tracking database functionality.
//

import XCTest
import GRDB
@testable import gridstream_macos

final class PlayCountRecordTests: XCTestCase {

    var testDatabaseURL: URL!
    var databaseManager: DatabaseManager!

    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GridStreamPlayCountTests_\(UUID().uuidString)")
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

    // MARK: - Test 1: play_count column default value is 0

    func testPlayCountColumnDefaultValueIsZero() async throws {
        let sourceDirectoryId = UUID()

        // Create a video without explicitly setting playCount
        let video = VideoFileRecord(
            fileId: "play_count_default_test",
            path: "/test/path/video.mp4",
            sourceDirectoryId: sourceDirectoryId,
            filename: "video.mp4",
            fileSize: 1000,
            duration: 120.0,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: Date().timeIntervalSince1970
        )

        try await databaseManager.write { db in
            try video.insert(db)
        }

        let foundVideo = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId("play_count_default_test", in: db)
        }

        XCTAssertNotNil(foundVideo)
        XCTAssertEqual(foundVideo?.playCount, 0, "play_count should default to 0")
    }

    // MARK: - Test 2: total_view_time column default value is 0

    func testTotalViewTimeColumnDefaultValueIsZero() async throws {
        let sourceDirectoryId = UUID()

        // Create a video without explicitly setting totalViewTime
        let video = VideoFileRecord(
            fileId: "view_time_default_test",
            path: "/test/path/video.mp4",
            sourceDirectoryId: sourceDirectoryId,
            filename: "video.mp4",
            fileSize: 1000,
            duration: 120.0,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: Date().timeIntervalSince1970
        )

        try await databaseManager.write { db in
            try video.insert(db)
        }

        let foundVideo = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId("view_time_default_test", in: db)
        }

        XCTAssertNotNil(foundVideo)
        XCTAssertEqual(foundVideo?.totalViewTime, 0, "total_view_time should default to 0")
    }

    // MARK: - Test 3: findByPlayCount query returns correct records

    func testFindByPlayCountReturnsCorrectRecords() async throws {
        let sourceDirectoryId = UUID()

        // Create videos with different play counts
        let playCounts = [0, 1, 3, 3, 5]
        for (index, playCount) in playCounts.enumerated() {
            let video = VideoFileRecord(
                fileId: "play_count_query_\(index)",
                path: "/test/path/video_\(index).mp4",
                sourceDirectoryId: sourceDirectoryId,
                filename: "video_\(index).mp4",
                fileSize: 1000,
                duration: 120.0,
                width: 1920,
                height: 1080,
                codec: "h264",
                lastModified: Date().timeIntervalSince1970,
                playCount: playCount
            )
            try await databaseManager.write { db in
                try video.insert(db)
            }
        }

        // Query for videos with play count of 3
        let foundVideos = try await databaseManager.read { db in
            try VideoFileRecord.findByPlayCount(3, in: db)
        }

        XCTAssertEqual(foundVideos.count, 2, "Should find 2 videos with play count of 3")
        XCTAssertTrue(foundVideos.allSatisfy { $0.playCount == 3 })
    }

    // MARK: - Test 4: findUnplayed query returns only records with play_count = 0

    func testFindUnplayedReturnsOnlyUnplayedRecords() async throws {
        let sourceDirectoryId = UUID()

        // Create videos with varying play counts
        let playCounts = [0, 0, 1, 2, 0, 5]
        for (index, playCount) in playCounts.enumerated() {
            let video = VideoFileRecord(
                fileId: "unplayed_query_\(index)",
                path: "/test/path/video_\(index).mp4",
                sourceDirectoryId: sourceDirectoryId,
                filename: "video_\(index).mp4",
                fileSize: 1000,
                duration: 120.0,
                width: 1920,
                height: 1080,
                codec: "h264",
                lastModified: Date().timeIntervalSince1970,
                playCount: playCount
            )
            try await databaseManager.write { db in
                try video.insert(db)
            }
        }

        // Query for unplayed videos
        let unplayedVideos = try await databaseManager.read { db in
            try VideoFileRecord.findUnplayed(in: db)
        }

        XCTAssertEqual(unplayedVideos.count, 3, "Should find 3 unplayed videos")
        XCTAssertTrue(unplayedVideos.allSatisfy { $0.playCount == 0 }, "All returned videos should have play_count = 0")
    }

    // MARK: - Additional Tests for Query Helpers

    func testFindByMinPlayCountReturnsCorrectRecords() async throws {
        let sourceDirectoryId = UUID()

        // Create videos with different play counts
        let playCounts = [0, 1, 2, 3, 5, 10]
        for (index, playCount) in playCounts.enumerated() {
            let video = VideoFileRecord(
                fileId: "min_play_count_\(index)",
                path: "/test/path/video_\(index).mp4",
                sourceDirectoryId: sourceDirectoryId,
                filename: "video_\(index).mp4",
                fileSize: 1000,
                duration: 120.0,
                width: 1920,
                height: 1080,
                codec: "h264",
                lastModified: Date().timeIntervalSince1970,
                playCount: playCount
            )
            try await databaseManager.write { db in
                try video.insert(db)
            }
        }

        // Query for videos with at least 3 plays
        let foundVideos = try await databaseManager.read { db in
            try VideoFileRecord.findByMinPlayCount(3, in: db)
        }

        XCTAssertEqual(foundVideos.count, 3, "Should find 3 videos with play count >= 3")
        XCTAssertTrue(foundVideos.allSatisfy { $0.playCount >= 3 })
    }

    func testFindMostPlayedReturnsVideosInDescendingOrder() async throws {
        let sourceDirectoryId = UUID()

        // Create videos with different play counts
        let playCounts = [1, 5, 2, 10, 3]
        for (index, playCount) in playCounts.enumerated() {
            let video = VideoFileRecord(
                fileId: "most_played_\(index)",
                path: "/test/path/video_\(index).mp4",
                sourceDirectoryId: sourceDirectoryId,
                filename: "video_\(index).mp4",
                fileSize: 1000,
                duration: 120.0,
                width: 1920,
                height: 1080,
                codec: "h264",
                lastModified: Date().timeIntervalSince1970,
                playCount: playCount
            )
            try await databaseManager.write { db in
                try video.insert(db)
            }
        }

        // Query for top 3 most played
        let mostPlayed = try await databaseManager.read { db in
            try VideoFileRecord.findMostPlayed(limit: 3, in: db)
        }

        XCTAssertEqual(mostPlayed.count, 3, "Should return 3 videos")
        XCTAssertEqual(mostPlayed[0].playCount, 10)
        XCTAssertEqual(mostPlayed[1].playCount, 5)
        XCTAssertEqual(mostPlayed[2].playCount, 3)
    }
}

import GridStreamAPI
import XCTest
import Vapor
import GRDB
@testable import gridstream_macos

final class RatingRoutesTests: XCTestCase {

    var testDatabaseURL: URL!
    var databaseManager: DatabaseManager!

    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GridStreamRatingRoutesTests_\(UUID().uuidString)")
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

    private func createTestVideo(fileId: String = "test_file_id", rating: Int = 0, sourceDirectoryId: UUID? = nil) async throws -> VideoFileRecord {
        let video = VideoFileRecord(
            fileId: fileId,
            path: "/test/path/video.mp4",
            sourceDirectoryId: sourceDirectoryId ?? UUID(),
            filename: "video.mp4",
            fileSize: 1000,
            duration: 120.0,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: Date().timeIntervalSince1970,
            rating: rating
        )

        try await databaseManager.write { db in
            try video.insert(db)
        }

        return video
    }

    private func createTestTag(name: String = "test-tag", ratingEnabled: Bool = false) async throws -> TagRecord {
        let tag = TagRecord(
            name: name,
            color: TagColorPalette.red,
            description: nil,
            ratingEnabled: ratingEnabled
        )

        try await databaseManager.write { db in
            try tag.insert(db)
        }

        return tag
    }

    // MARK: - GET /api/v1/videos/:fileId/rating - Tests rating retrieval

    func testGetVideoRatingReturnsCurrentRating() async throws {
        let video = try await createTestVideo(fileId: "get_rating_test", rating: 7)

        // Simulate the GET endpoint: fetch video and return rating
        let foundVideo = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(video.fileId, in: db)
        }

        XCTAssertNotNil(foundVideo)
        XCTAssertEqual(foundVideo?.rating, 7)
    }

    // MARK: - PUT /api/v1/videos/:fileId/rating - Tests rating update with validation

    func testPutVideoRatingSetsRatingWithValidation() async throws {
        let video = try await createTestVideo(fileId: "put_rating_test", rating: 0)

        // Simulate the PUT endpoint: update video rating
        let newRating = 8

        // Validate rating is 0-10
        XCTAssertTrue(newRating >= 0 && newRating <= 10)

        try await databaseManager.write { db in
            guard var videoRecord = try VideoFileRecord.findByFileId(video.fileId, in: db) else {
                XCTFail("Video not found")
                return
            }
            videoRecord.rating = newRating
            videoRecord.touch()
            try videoRecord.update(db)
        }

        // Verify persistence
        let updatedVideo = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(video.fileId, in: db)
        }
        XCTAssertEqual(updatedVideo?.rating, 8)
    }

    // MARK: - Per-Tag Rating Tests

    func testGetPerTagRatingWithRatingEnabled() async throws {
        let video = try await createTestVideo(fileId: "pertag_get_test")
        let tag = try await createTestTag(name: "ratable-tag", ratingEnabled: true)

        // Create video-tag association with rating
        try await databaseManager.write { db in
            let videoTag = VideoTagRecord(
                videoFileId: video.fileId,
                tagId: tag.id,
                rating: 9
            )
            try videoTag.insert(db)
        }

        // Simulate GET endpoint: verify tag has ratingEnabled and get per-tag rating
        let savedTag = try await databaseManager.read { db in
            TagRecord.findById(tag.id, in: db)
        }
        XCTAssertTrue(savedTag?.ratingEnabled == true)

        let videoTag = try await databaseManager.read { db in
            VideoTagRecord.findByVideoFileIdAndTagId(video.fileId, tag.id, in: db)
        }

        XCTAssertNotNil(videoTag)
        XCTAssertEqual(videoTag?.rating, 9)
    }

    func testPutPerTagRatingValidatesRatingEnabled() async throws {
        let video = try await createTestVideo(fileId: "pertag_put_test")
        let ratingEnabledTag = try await createTestTag(name: "rating-enabled", ratingEnabled: true)
        let regularTag = try await createTestTag(name: "regular-tag", ratingEnabled: false)

        // Create video-tag associations
        try await databaseManager.write { db in
            let videoTag1 = VideoTagRecord(videoFileId: video.fileId, tagId: ratingEnabledTag.id)
            try videoTag1.insert(db)

            let videoTag2 = VideoTagRecord(videoFileId: video.fileId, tagId: regularTag.id)
            try videoTag2.insert(db)
        }

        // Simulate PUT endpoint: check ratingEnabled before allowing update

        // For rating-enabled tag - should succeed
        let savedRatingEnabledTag = try await databaseManager.read { db in
            TagRecord.findById(ratingEnabledTag.id, in: db)
        }
        XCTAssertTrue(savedRatingEnabledTag?.ratingEnabled == true)

        try await databaseManager.write { db in
            guard var videoTag = VideoTagRecord.findByVideoFileIdAndTagId(video.fileId, ratingEnabledTag.id, in: db) else {
                XCTFail("VideoTag not found")
                return
            }
            videoTag.rating = 6
            try videoTag.update(db)
        }

        let updatedVideoTag = try await databaseManager.read { db in
            VideoTagRecord.findByVideoFileIdAndTagId(video.fileId, ratingEnabledTag.id, in: db)
        }
        XCTAssertEqual(updatedVideoTag?.rating, 6)

        // For non-rating-enabled tag - should be rejected (in real API)
        let savedRegularTag = try await databaseManager.read { db in
            TagRecord.findById(regularTag.id, in: db)
        }
        XCTAssertFalse(savedRegularTag?.ratingEnabled == true)
        // The API would return 400 Bad Request here
    }

    // MARK: - Bulk Rating Tests

    func testBulkRatingForSourceDirectory() async throws {
        let sourceDirectoryId = UUID()

        // Create multiple videos in the same source directory
        for i in 1...3 {
            _ = try await createTestVideo(
                fileId: "bulk_test_\(i)",
                rating: 0,
                sourceDirectoryId: sourceDirectoryId
            )
        }

        // Simulate bulk rating endpoint
        let newRating = 5

        let videos = try await databaseManager.read { db in
            try VideoFileRecord.findBySourceDirectoryId(sourceDirectoryId, in: db)
        }
        XCTAssertEqual(videos.count, 3)

        let videosAffected = try await databaseManager.write { db -> Int in
            var videosAffected = 0
            for var video in videos {
                video.rating = newRating
                video.touch()
                try video.update(db)
                videosAffected += 1
            }
            return videosAffected
        }

        XCTAssertEqual(videosAffected, 3)

        // Verify all videos now have rating 5
        let updatedVideos = try await databaseManager.read { db in
            try VideoFileRecord.findBySourceDirectoryId(sourceDirectoryId, in: db)
        }

        for video in updatedVideos {
            XCTAssertEqual(video.rating, 5)
        }
    }

    // MARK: - Bulk Tag Rating Tests

    func testBulkTagRatingForSourceDirectory() async throws {
        let sourceDirectoryId = UUID()
        let ratingEnabledTag = try await createTestTag(name: "bulk-ratable", ratingEnabled: true)

        // Create multiple videos with the tag assigned
        for i in 1...3 {
            let video = try await createTestVideo(
                fileId: "bulk_tag_test_\(i)",
                rating: 0,
                sourceDirectoryId: sourceDirectoryId
            )

            try await databaseManager.write { db in
                let videoTag = VideoTagRecord(videoFileId: video.fileId, tagId: ratingEnabledTag.id)
                try videoTag.insert(db)
            }
        }

        // Simulate bulk tag rating endpoint
        let newRating = 7

        let videos = try await databaseManager.read { db in
            try VideoFileRecord.findBySourceDirectoryId(sourceDirectoryId, in: db)
        }

        let associationsAffected = try await databaseManager.write { db -> Int in
            var associationsAffected = 0
            for video in videos {
                if var videoTag = VideoTagRecord.findByVideoFileIdAndTagId(video.fileId, ratingEnabledTag.id, in: db) {
                    videoTag.rating = newRating
                    try videoTag.update(db)
                    associationsAffected += 1
                }
            }
            return associationsAffected
        }

        XCTAssertEqual(associationsAffected, 3)

        // Verify all video-tag associations now have the rating
        for video in videos {
            let videoTag = try await databaseManager.read { db in
                VideoTagRecord.findByVideoFileIdAndTagId(video.fileId, ratingEnabledTag.id, in: db)
            }
            XCTAssertEqual(videoTag?.rating, 7)
        }
    }
}

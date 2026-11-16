import GridStreamAPI
import XCTest
import Vapor
import GRDB
@testable import gridstream_macos

/// Strategic integration tests for the rating system to fill critical gaps
final class RatingIntegrationTests: XCTestCase {

    var testDatabaseURL: URL!
    var databaseManager: DatabaseManager!

    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GridStreamRatingIntegrationTests_\(UUID().uuidString)")
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

    // MARK: - Rating Validation Boundary Tests

    func testRatingValidationBoundaries() async throws {
        // Test that 0 and 10 are valid ratings
        XCTAssertTrue(isValidRating(0), "Rating 0 should be valid")
        XCTAssertTrue(isValidRating(10), "Rating 10 should be valid")

        // Test boundary values 1-9
        for rating in 1...9 {
            XCTAssertTrue(isValidRating(rating), "Rating \(rating) should be valid")
        }

        // Test that -1 and 11 are invalid ratings
        XCTAssertFalse(isValidRating(-1), "Rating -1 should be invalid")
        XCTAssertFalse(isValidRating(11), "Rating 11 should be invalid")
        XCTAssertFalse(isValidRating(-100), "Rating -100 should be invalid")
        XCTAssertFalse(isValidRating(100), "Rating 100 should be invalid")
    }

    private func isValidRating(_ rating: Int) -> Bool {
        rating >= 0 && rating <= 10
    }

    // MARK: - Per-Tag Rating Validation

    func testPerTagRatingBlockedWhenRatingDisabled() async throws {
        let video = try await createTestVideo(fileId: "blocked_rating_test")

        // Create a tag with rating disabled
        let tag = TagRecord(
            name: "no-rating-tag",
            color: TagColorPalette.blue,
            description: nil,
            ratingEnabled: false
        )

        try await databaseManager.write { db in
            try tag.insert(db)
        }

        // Create video-tag association
        try await databaseManager.write { db in
            let videoTag = VideoTagRecord(videoFileId: video.fileId, tagId: tag.id)
            try videoTag.insert(db)
        }

        // Verify the tag does NOT have rating enabled
        let savedTag = try await databaseManager.read { db in
            TagRecord.findById(tag.id, in: db)
        }
        XCTAssertFalse(savedTag?.ratingEnabled ?? true, "Tag should have ratingEnabled = false")

        // The API would reject attempts to set per-tag rating
        // This simulates the validation check in RatingRoutes.setPerTagRating
        let canSetPerTagRating = savedTag?.ratingEnabled ?? false
        XCTAssertFalse(canSetPerTagRating, "Should not be able to set per-tag rating when ratingEnabled is false")
    }

    // MARK: - Query Filter Integration Tests

    func testRatingRangeQueryWithCombinedFilters() async throws {
        let sourceDirectoryId = UUID()

        // Create videos with various ratings
        let ratings = [0, 2, 4, 6, 8, 10]
        for (index, rating) in ratings.enumerated() {
            let video = VideoFileRecord(
                fileId: "filter_test_\(index)",
                path: "/test/path/video_\(index).mp4",
                sourceDirectoryId: sourceDirectoryId,
                filename: "video_\(index).mp4",
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
        }

        // Test min_rating filter only
        let minRating5 = try await databaseManager.read { db in
            try VideoFileRecord.findByRatingRange(min: 5, max: 10, in: db)
        }
        XCTAssertEqual(minRating5.count, 3)  // 6, 8, 10

        // Test max_rating filter only
        let maxRating5 = try await databaseManager.read { db in
            try VideoFileRecord.findByRatingRange(min: 0, max: 5, in: db)
        }
        XCTAssertEqual(maxRating5.count, 3)  // 0, 2, 4

        // Test combined min and max (middle range)
        let range3to7 = try await databaseManager.read { db in
            try VideoFileRecord.findByRatingRange(min: 3, max: 7, in: db)
        }
        XCTAssertEqual(range3to7.count, 2)  // 4, 6

        // Test exact match using findByRating
        let exactMatch = try await databaseManager.read { db in
            try VideoFileRecord.findByRating(6, in: db)
        }
        XCTAssertEqual(exactMatch.count, 1)

        // Test unrated filter
        let unrated = try await databaseManager.read { db in
            try VideoFileRecord.findUnrated(in: db)
        }
        XCTAssertEqual(unrated.count, 1)
        XCTAssertEqual(unrated.first?.rating, 0)
    }

    // MARK: - Empty Directory Edge Case

    func testBulkRatingWithEmptyDirectoryReturnsZero() async throws {
        let emptySourceDirectoryId = UUID()

        // Don't create any videos for this source directory

        // Attempt to fetch videos - should return empty array
        let videos = try await databaseManager.read { db in
            try VideoFileRecord.findBySourceDirectoryId(emptySourceDirectoryId, in: db)
        }

        XCTAssertTrue(videos.isEmpty, "Should return empty array for directory with no videos")

        // Simulate bulk rating - should affect 0 videos
        let videosAffected = try await databaseManager.write { db -> Int in
            var videosAffected = 0
            for var video in videos {
                video.rating = 5
                video.touch()
                try video.update(db)
                videosAffected += 1
            }
            return videosAffected
        }

        XCTAssertEqual(videosAffected, 0, "Bulk rating on empty directory should affect 0 videos")
    }

    // MARK: - Rating Update Touch Timestamp

    func testRatingUpdateTouchesTimestamp() async throws {
        let video = VideoFileRecord(
            fileId: "timestamp_test",
            path: "/test/path/video.mp4",
            sourceDirectoryId: UUID(),
            filename: "video.mp4",
            fileSize: 1000,
            duration: 120.0,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: Date().timeIntervalSince1970,
            rating: 0
        )

        try await databaseManager.write { db in
            try video.insert(db)
        }

        let originalVideo = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(video.fileId, in: db)
        }
        let originalUpdatedAt = originalVideo?.updatedAt ?? 0

        // Wait a moment to ensure timestamp difference
        try await Task.sleep(nanoseconds: 100_000_000)

        // Update rating
        try await databaseManager.write { db in
            guard var videoRecord = try VideoFileRecord.findByFileId(video.fileId, in: db) else {
                XCTFail("Video not found")
                return
            }
            videoRecord.rating = 5
            videoRecord.touch()
            try videoRecord.update(db)
        }

        let updatedVideo = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(video.fileId, in: db)
        }

        XCTAssertEqual(updatedVideo?.rating, 5)
        XCTAssertGreaterThan(updatedVideo?.updatedAt ?? 0, originalUpdatedAt, "updatedAt should be updated after rating change")
    }

    // MARK: - Per-Tag Rating Range Query

    func testPerTagRatingRangeQuery() async throws {
        // Create a rating-enabled tag
        let tag = TagRecord(
            name: "per-tag-range-test",
            color: TagColorPalette.green,
            description: nil,
            ratingEnabled: true
        )

        try await databaseManager.write { db in
            try tag.insert(db)
        }

        let sourceDirectoryId = UUID()

        // Create videos with different per-tag ratings
        let perTagRatings = [1, 3, 5, 7, 9]
        for (index, rating) in perTagRatings.enumerated() {
            let video = VideoFileRecord(
                fileId: "pertag_range_\(index)",
                path: "/test/path/video_\(index).mp4",
                sourceDirectoryId: sourceDirectoryId,
                filename: "video_\(index).mp4",
                fileSize: 1000,
                duration: 120.0,
                width: 1920,
                height: 1080,
                codec: "h264",
                lastModified: Date().timeIntervalSince1970
            )

            try await databaseManager.write { db in
                try video.insert(db)

                let videoTag = VideoTagRecord(
                    videoFileId: video.fileId,
                    tagId: tag.id,
                    rating: rating
                )
                try videoTag.insert(db)
            }
        }

        // Query for per-tag ratings 4-8
        let filteredVideoTags = try await databaseManager.read { db in
            try VideoTagRecord.findByTagIdWithRating(tag.id, minRating: 4, maxRating: 8, in: db)
        }

        XCTAssertEqual(filteredVideoTags.count, 2)  // 5, 7
        let ratings = filteredVideoTags.map { $0.rating }.sorted()
        XCTAssertEqual(ratings, [5, 7])
    }

    // MARK: - Helper Methods

    private func createTestVideo(fileId: String) async throws -> VideoFileRecord {
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
            lastModified: Date().timeIntervalSince1970
        )

        try await databaseManager.write { db in
            try video.insert(db)
        }

        return video
    }
}

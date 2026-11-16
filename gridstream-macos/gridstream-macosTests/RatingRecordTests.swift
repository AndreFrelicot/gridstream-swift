import GridStreamAPI
import XCTest
import GRDB
@testable import gridstream_macos

final class RatingRecordTests: XCTestCase {

    var testDatabaseURL: URL!
    var databaseManager: DatabaseManager!

    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GridStreamRatingTests_\(UUID().uuidString)")
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

    // MARK: - VideoFileRecord Rating CRUD Tests

    func testVideoFileRecordRatingFieldSetAndQuery() async throws {
        let sourceDirectoryId = UUID()
        let video = VideoFileRecord(
            fileId: "rating_test_file_1",
            path: "/test/path/video.mp4",
            sourceDirectoryId: sourceDirectoryId,
            filename: "video.mp4",
            fileSize: 1000,
            duration: 120.0,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: Date().timeIntervalSince1970,
            rating: 7
        )

        try await databaseManager.write { db in
            try video.insert(db)
        }

        let foundVideos = try await databaseManager.read { db in
            try VideoFileRecord.findByRating(7, in: db)
        }

        XCTAssertEqual(foundVideos.count, 1)
        XCTAssertEqual(foundVideos.first?.rating, 7)
        XCTAssertEqual(foundVideos.first?.fileId, "rating_test_file_1")
    }

    func testVideoFileRecordRatingRangeQuery() async throws {
        let sourceDirectoryId = UUID()

        // Create videos with various ratings
        let ratings = [0, 3, 5, 7, 10]
        for (index, rating) in ratings.enumerated() {
            let video = VideoFileRecord(
                fileId: "range_test_file_\(index)",
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

        // Query for ratings 5-8
        let foundVideos = try await databaseManager.read { db in
            try VideoFileRecord.findByRatingRange(min: 5, max: 8, in: db)
        }

        XCTAssertEqual(foundVideos.count, 2)
        let foundRatings = foundVideos.map { $0.rating }.sorted()
        XCTAssertEqual(foundRatings, [5, 7])
    }

    func testVideoFileRecordFindUnrated() async throws {
        let sourceDirectoryId = UUID()

        // Create rated and unrated videos
        for i in 0..<3 {
            let video = VideoFileRecord(
                fileId: "unrated_test_file_\(i)",
                path: "/test/path/video_\(i).mp4",
                sourceDirectoryId: sourceDirectoryId,
                filename: "video_\(i).mp4",
                fileSize: 1000,
                duration: 120.0,
                width: 1920,
                height: 1080,
                codec: "h264",
                lastModified: Date().timeIntervalSince1970,
                rating: i == 0 ? 0 : i * 3  // First one unrated (0), others rated
            )
            try await databaseManager.write { db in
                try video.insert(db)
            }
        }

        let unratedVideos = try await databaseManager.read { db in
            try VideoFileRecord.findUnrated(in: db)
        }

        XCTAssertEqual(unratedVideos.count, 1)
        XCTAssertEqual(unratedVideos.first?.rating, 0)
    }

    // MARK: - TagRecord ratingEnabled Tests

    func testTagRecordRatingEnabledFieldPersistence() async throws {
        let tag = TagRecord(
            name: "favorites",
            color: TagColorPalette.red,
            description: "My favorites",
            ratingEnabled: true
        )

        try await databaseManager.write { db in
            try tag.insert(db)
        }

        let foundTag = try await databaseManager.read { db in
            TagRecord.findByName("favorites", in: db)
        }

        XCTAssertNotNil(foundTag)
        XCTAssertTrue(foundTag!.ratingEnabled)

        // Create another tag without rating enabled
        let tag2 = TagRecord(
            name: "regular",
            color: TagColorPalette.blue,
            description: nil,
            ratingEnabled: false
        )

        try await databaseManager.write { db in
            try tag2.insert(db)
        }

        let foundTag2 = try await databaseManager.read { db in
            TagRecord.findByName("regular", in: db)
        }

        XCTAssertNotNil(foundTag2)
        XCTAssertFalse(foundTag2!.ratingEnabled)
    }

    // MARK: - VideoTagRecord Per-Tag Rating Tests

    func testVideoTagRecordPerTagRatingStorage() async throws {
        let sourceDirectoryId = UUID()

        // Create a video
        let video = VideoFileRecord(
            fileId: "pertag_rating_test",
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

        // Create a rating-enabled tag
        let tag = TagRecord(
            name: "ratable-tag",
            color: TagColorPalette.green,
            description: nil,
            ratingEnabled: true
        )

        try await databaseManager.write { db in
            try video.insert(db)
            try tag.insert(db)
        }

        let savedTag = try await databaseManager.read { db in
            TagRecord.findByName("ratable-tag", in: db)
        }

        // Create video-tag association with rating
        let videoTag = VideoTagRecord(
            videoFileId: video.fileId,
            tagId: savedTag!.id,
            rating: 8
        )

        try await databaseManager.write { db in
            try videoTag.insert(db)
        }

        // Query and verify
        let videoTags = try await databaseManager.read { db in
            VideoTagRecord.findByVideoFileIdWithRatings(video.fileId, in: db)
        }

        XCTAssertEqual(videoTags.count, 1)
        XCTAssertEqual(videoTags.first?.rating, 8)
    }

    func testVideoTagRecordFindByTagIdWithRatingFilter() async throws {
        let sourceDirectoryId = UUID()

        // Create a rating-enabled tag
        let tag = TagRecord(
            name: "filter-test-tag",
            color: TagColorPalette.pink,
            description: nil,
            ratingEnabled: true
        )

        try await databaseManager.write { db in
            try tag.insert(db)
        }

        let savedTag = try await databaseManager.read { db in
            TagRecord.findByName("filter-test-tag", in: db)
        }

        // Create videos with different per-tag ratings
        let ratings = [2, 5, 7, 9]
        for (index, rating) in ratings.enumerated() {
            let video = VideoFileRecord(
                fileId: "tag_rating_filter_\(index)",
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

            let videoTag = VideoTagRecord(
                videoFileId: video.fileId,
                tagId: savedTag!.id,
                rating: rating
            )

            try await databaseManager.write { db in
                try video.insert(db)
                try videoTag.insert(db)
            }
        }

        // Query for ratings 5-8
        let filteredVideoTags = try await databaseManager.read { db in
            try VideoTagRecord.findByTagIdWithRating(savedTag!.id, minRating: 5, maxRating: 8, in: db)
        }

        XCTAssertEqual(filteredVideoTags.count, 2)
        let foundRatings = filteredVideoTags.map { $0.rating }.sorted()
        XCTAssertEqual(foundRatings, [5, 7])
    }
}

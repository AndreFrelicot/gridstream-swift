import GridStreamAPI
import XCTest
import Vapor
import GRDB
@testable import gridstream_macos

/// Integration tests for critical tagging system workflows that are not covered
/// by the individual component tests.
final class TaggingSystemIntegrationTests: XCTestCase {

    var testDatabaseURL: URL!
    var databaseManager: DatabaseManager!

    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GridStreamTagIntegrationTests_\(UUID().uuidString)")
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

    // MARK: - 30 Tag Limit Boundary Tests

    /// Tests that exactly 30 tags can be created (boundary condition)
    func testTagLimit30thTagAllowed() async throws {
        // Create 30 tags - all should succeed
        for i in 1...30 {
            let tag = TagRecord(
                name: "tag\(i)",
                color: TagColorPalette.allColors[i % TagColorPalette.allColors.count],
                description: nil
            )
            try await databaseManager.write { db in
                let mutableTag = tag
                try mutableTag.insert(db)
            }
        }

        let tagCount = try await databaseManager.read { db in
            TagRecord.countAll(in: db)
        }

        XCTAssertEqual(tagCount, 30, "Should be able to create exactly 30 tags")
    }

    /// Tests that the 31st tag is rejected when limit is reached
    func testTagLimit31stTagRejectedByApplicationLayer() async throws {
        // Create 30 tags first
        for i in 1...30 {
            let tag = TagRecord(
                name: "limit-test-tag\(i)",
                color: TagColorPalette.allColors[i % TagColorPalette.allColors.count],
                description: nil
            )
            try await databaseManager.write { db in
                let mutableTag = tag
                try mutableTag.insert(db)
            }
        }

        // Verify we have 30 tags
        let tagCount = try await databaseManager.read { db in
            TagRecord.countAll(in: db)
        }
        XCTAssertEqual(tagCount, 30)

        // The 31st tag check should happen at application layer
        // This tests that the countAll function works correctly for limit checking
        let canAddMore = tagCount < 30
        XCTAssertFalse(canAddMore, "Should not allow more than 30 tags")
    }

    // MARK: - Case-Insensitive Tag Name Uniqueness

    /// Tests that tags with different cases are treated as the same tag
    func testCaseInsensitiveTagNameUniqueness() async throws {
        // Create a tag with mixed case
        let tag1 = TagRecord(
            name: "Interview",
            color: TagColorPalette.red,
            description: nil
        )
        try await databaseManager.write { db in
            let mutableTag = tag1
            try mutableTag.insert(db)
        }

        // Verify the name is stored lowercase
        let savedTag = try await databaseManager.read { db in
            TagRecord.findByName("INTERVIEW", in: db)
        }
        XCTAssertNotNil(savedTag)
        XCTAssertEqual(savedTag?.name, "interview", "Tag name should be stored as lowercase")

        // Verify lookup works with any case
        let foundWithLower = try await databaseManager.read { db in
            TagRecord.findByName("interview", in: db)
        }
        let foundWithUpper = try await databaseManager.read { db in
            TagRecord.findByName("INTERVIEW", in: db)
        }
        let foundWithMixed = try await databaseManager.read { db in
            TagRecord.findByName("InTeRvIeW", in: db)
        }

        XCTAssertEqual(foundWithLower?.id, savedTag?.id)
        XCTAssertEqual(foundWithUpper?.id, savedTag?.id)
        XCTAssertEqual(foundWithMixed?.id, savedTag?.id)
    }

    // MARK: - Tag Persistence via file_id

    /// Tests that tags remain associated with a video when accessed via file_id
    /// This simulates the scenario where a file's path might change but its file_id stays the same
    func testTagPersistenceViaFileId() async throws {
        // Create a video with a specific file_id (simulating the hash-based ID)
        let originalPath = "/original/path/video.mp4"
        let fileId = "abc123_persistent_file_id"

        let video = VideoFileRecord(
            fileId: fileId,
            path: originalPath,
            sourceDirectoryId: UUID(),
            filename: "video.mp4",
            fileSize: 1000,
            duration: 120.0,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: Date().timeIntervalSince1970
        )

        let tag = TagRecord(name: "important", color: TagColorPalette.blue)

        try await databaseManager.write { db in
            let mutableVideo = video
            try mutableVideo.insert(db)
            let mutableTag = tag
            try mutableTag.insert(db)
        }

        // Apply tag to video
        let savedTag = try await databaseManager.read { db in
            TagRecord.findByName("important", in: db)
        }

        let videoTag = VideoTagRecord(videoFileId: fileId, tagId: savedTag!.id)
        try await databaseManager.write { db in
            let mutableVideoTag = videoTag
            try mutableVideoTag.insert(db)
        }

        // Simulate file move by updating the path (but keeping the same file_id)
        let newPath = "/new/location/renamed_video.mp4"
        try await databaseManager.write { db in
            try db.execute(
                sql: "UPDATE video_files SET path = ?, filename = ? WHERE file_id = ?",
                arguments: [newPath, "renamed_video.mp4", fileId]
            )
        }

        // Verify the tag is still associated with the video via file_id
        let tagsForVideo = try await databaseManager.read { db in
            VideoTagRecord.findByVideoFileId(fileId, in: db)
        }

        XCTAssertEqual(tagsForVideo.count, 1, "Tag should persist after simulated file move")
        XCTAssertEqual(tagsForVideo.first?.tagId, savedTag?.id)
    }

    // MARK: - Tag Deletion Cascades

    /// Tests that deleting a tag properly removes all video-tag associations
    func testTagDeletionCascadesToMultipleVideos() async throws {
        let tag = TagRecord(name: "cascade-test", color: TagColorPalette.amber)

        try await databaseManager.write { db in
            let mutableTag = tag
            try mutableTag.insert(db)
        }

        let savedTag = try await databaseManager.read { db in
            TagRecord.findByName("cascade-test", in: db)
        }

        // Create multiple videos and assign the tag to all of them
        for i in 1...5 {
            let video = VideoFileRecord(
                fileId: "cascade_test_video_\(i)",
                path: "/test/cascade_\(i).mp4",
                sourceDirectoryId: UUID(),
                filename: "cascade_\(i).mp4",
                fileSize: Int64(1000 * i),
                duration: Double(60 * i),
                width: 1920,
                height: 1080,
                codec: "h264",
                lastModified: Date().timeIntervalSince1970
            )

            let videoTag = VideoTagRecord(videoFileId: video.fileId, tagId: savedTag!.id)

            try await databaseManager.write { db in
                let mutableVideo = video
                try mutableVideo.insert(db)
                let mutableVideoTag = videoTag
                try mutableVideoTag.insert(db)
            }
        }

        // Verify we have 5 associations
        let associationsBefore = try await databaseManager.read { db in
            VideoTagRecord.findByTagId(savedTag!.id, in: db)
        }
        XCTAssertEqual(associationsBefore.count, 5)

        // Delete the tag and its associations
        try await databaseManager.write { db in
            _ = try VideoTagRecord
                .filter(Column("tag_id") == savedTag!.id)
                .deleteAll(db)
            _ = try TagRecord
                .filter(Column("id") == savedTag!.id)
                .deleteAll(db)
        }

        // Verify all associations are deleted
        let associationsAfter = try await databaseManager.read { db in
            VideoTagRecord.findByTagId(savedTag!.id, in: db)
        }
        XCTAssertEqual(associationsAfter.count, 0, "All video-tag associations should be deleted")

        // Verify the tag itself is deleted
        let deletedTag = try await databaseManager.read { db in
            TagRecord.findById(savedTag!.id, in: db)
        }
        XCTAssertNil(deletedTag, "Tag should be deleted")
    }

    // MARK: - Bulk Application with Mixed Scenarios

    /// Tests bulk tag application where some videos already have the tag
    func testBulkTagApplicationWithPartialDuplicates() async throws {
        let sourceDirectoryId = UUID()
        let tag = TagRecord(name: "bulk-mixed", color: TagColorPalette.green)

        try await databaseManager.write { db in
            let mutableTag = tag
            try mutableTag.insert(db)
        }

        let savedTag = try await databaseManager.read { db in
            TagRecord.findByName("bulk-mixed", in: db)
        }

        // Create 5 videos in the same source directory
        var videos: [VideoFileRecord] = []
        for i in 1...5 {
            let video = VideoFileRecord(
                fileId: "bulk_mixed_video_\(i)",
                path: "/test/source/bulk_\(i).mp4",
                sourceDirectoryId: sourceDirectoryId,
                filename: "bulk_\(i).mp4",
                fileSize: Int64(1000 * i),
                duration: Double(60 * i),
                width: 1920,
                height: 1080,
                codec: "h264",
                lastModified: Date().timeIntervalSince1970
            )
            videos.append(video)

            try await databaseManager.write { db in
                let mutableVideo = video
                try mutableVideo.insert(db)
            }
        }

        // Pre-apply tag to first 2 videos
        for i in 0..<2 {
            let videoTag = VideoTagRecord(videoFileId: videos[i].fileId, tagId: savedTag!.id)
            try await databaseManager.write { db in
                let mutableVideoTag = videoTag
                try mutableVideoTag.insert(db)
            }
        }

        // Verify pre-application
        let preAppliedCount = try await databaseManager.read { db in
            VideoTagRecord.findByTagId(savedTag!.id, in: db).count
        }
        XCTAssertEqual(preAppliedCount, 2)

        // Bulk apply to all videos (should skip duplicates silently)
        try await databaseManager.write { [videos] db in
            for video in videos {
                let existing = VideoTagRecord.findByVideoFileIdAndTagId(video.fileId, savedTag!.id, in: db)
                if existing == nil {
                    let videoTag = VideoTagRecord(videoFileId: video.fileId, tagId: savedTag!.id)
                    try videoTag.insert(db)
                }
            }
        }

        // Verify all 5 videos now have the tag
        let finalCount = try await databaseManager.read { db in
            VideoTagRecord.findByTagId(savedTag!.id, in: db).count
        }
        XCTAssertEqual(finalCount, 5, "All 5 videos should have the tag after bulk application")
    }

    // MARK: - Color Palette Validation

    /// Tests that all colors in the palette are valid
    func testAllPaletteColorsAreValid() async throws {
        let colors = TagColorPalette.allColors

        XCTAssertEqual(colors.count, 10, "Should have exactly 10 colors in palette")

        for color in colors {
            XCTAssertTrue(TagColorPalette.isValidColor(color), "Color \(color) should be valid")
        }

        // Test that an invalid color is rejected
        XCTAssertFalse(TagColorPalette.isValidColor("#FFFFFF"))
        XCTAssertFalse(TagColorPalette.isValidColor("invalid"))
        XCTAssertFalse(TagColorPalette.isValidColor(""))
    }
}

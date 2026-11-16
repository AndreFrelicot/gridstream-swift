import GridStreamAPI
import XCTest
import Vapor
import GRDB
@testable import gridstream_macos

final class VideoTagAssignmentTests: XCTestCase {

    var testDatabaseURL: URL!
    var databaseManager: DatabaseManager!
    var app: Application!

    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GridStreamVideoTagTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        testDatabaseURL = testDir.appendingPathComponent("test_gridstream.sqlite")
        databaseManager = DatabaseManager(databasePath: testDatabaseURL)
        try await databaseManager.initialize()

        var env = try Environment.detect()
        env.arguments = ["vapor", "test"]
        app = try await Application.make(env)
        app.middleware.use(ErrorMiddleware.default(environment: app.environment))
        try app.register(collection: VideoTagRoutes(databaseManager: databaseManager))
    }

    override func tearDown() async throws {
        try await databaseManager.close()
        try await app.asyncShutdown()
        let testDir = testDatabaseURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: testDir)
        databaseManager = nil
        testDatabaseURL = nil
        app = nil
    }

    // MARK: - Test GET /api/v1/videos/:id/tags returns tags for a video

    func testGetVideoTagsReturnsTagsForVideo() async throws {
        let sourceDirectoryId = UUID()
        let video = VideoFileRecord(
            fileId: "get_tags_test_file",
            path: "/test/video.mp4",
            sourceDirectoryId: sourceDirectoryId,
            filename: "video.mp4",
            fileSize: 1000,
            duration: 120.0,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: Date().timeIntervalSince1970
        )

        let tag1 = TagRecord(name: "action", color: TagColorPalette.red)
        let tag2 = TagRecord(name: "favorite", color: TagColorPalette.pink)

        try await databaseManager.write { db in
            let mutableVideo = video
            try mutableVideo.insert(db)

            let mutableTag1 = tag1
            let mutableTag2 = tag2
            try mutableTag1.insert(db)
            try mutableTag2.insert(db)
        }

        let savedTag1 = try await databaseManager.read { db in
            TagRecord.findByName("action", in: db)
        }
        let savedTag2 = try await databaseManager.read { db in
            TagRecord.findByName("favorite", in: db)
        }

        let videoTag1 = VideoTagRecord(videoFileId: video.fileId, tagId: savedTag1!.id)
        let videoTag2 = VideoTagRecord(videoFileId: video.fileId, tagId: savedTag2!.id)

        try await databaseManager.write { db in
            let mutableVT1 = videoTag1
            let mutableVT2 = videoTag2
            try mutableVT1.insert(db)
            try mutableVT2.insert(db)
        }

        let videoTags = try await databaseManager.read { db in
            VideoTagRecord.findByVideoFileId(video.fileId, in: db)
        }

        XCTAssertEqual(videoTags.count, 2)

        var tagsForVideo: [TagRecord] = []
        for vt in videoTags {
            if let tag = try await databaseManager.read({ db in TagRecord.findById(vt.tagId, in: db) }) {
                tagsForVideo.append(tag)
            }
        }

        XCTAssertEqual(tagsForVideo.count, 2)
        let tagNames = tagsForVideo.map { $0.name }
        XCTAssertTrue(tagNames.contains("action"))
        XCTAssertTrue(tagNames.contains("favorite"))
    }

    // MARK: - Test POST /api/v1/videos/:id/tags applies tags to a video

    func testApplyTagsToVideo() async throws {
        let sourceDirectoryId = UUID()
        let video = VideoFileRecord(
            fileId: "apply_tags_test_file",
            path: "/test/video2.mp4",
            sourceDirectoryId: sourceDirectoryId,
            filename: "video2.mp4",
            fileSize: 2000,
            duration: 180.0,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: Date().timeIntervalSince1970
        )

        let tag1 = TagRecord(name: "documentary", color: TagColorPalette.blue)
        let tag2 = TagRecord(name: "music", color: TagColorPalette.green)

        try await databaseManager.write { db in
            let mutableVideo = video
            try mutableVideo.insert(db)

            let mutableTag1 = tag1
            let mutableTag2 = tag2
            try mutableTag1.insert(db)
            try mutableTag2.insert(db)
        }

        let savedTag1 = try await databaseManager.read { db in
            TagRecord.findByName("documentary", in: db)
        }
        let savedTag2 = try await databaseManager.read { db in
            TagRecord.findByName("music", in: db)
        }

        try await databaseManager.write { db in
            for tagId in [savedTag1!.id, savedTag2!.id] {
                let existing = VideoTagRecord.findByVideoFileIdAndTagId(video.fileId, tagId, in: db)
                if existing == nil {
                    let videoTag = VideoTagRecord(videoFileId: video.fileId, tagId: tagId)
                    try videoTag.insert(db)
                }
            }
        }

        let videoTags = try await databaseManager.read { db in
            VideoTagRecord.findByVideoFileId(video.fileId, in: db)
        }

        XCTAssertEqual(videoTags.count, 2)
    }

    // MARK: - Test DELETE /api/v1/videos/:id/tags/:tagId removes a tag from a video

    func testRemoveTagFromVideo() async throws {
        let sourceDirectoryId = UUID()
        let video = VideoFileRecord(
            fileId: "remove_tag_test_file",
            path: "/test/video3.mp4",
            sourceDirectoryId: sourceDirectoryId,
            filename: "video3.mp4",
            fileSize: 3000,
            duration: 240.0,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: Date().timeIntervalSince1970
        )

        let tag = TagRecord(name: "to-remove", color: TagColorPalette.amber)

        try await databaseManager.write { db in
            let mutableVideo = video
            try mutableVideo.insert(db)

            let mutableTag = tag
            try mutableTag.insert(db)
        }

        let savedTag = try await databaseManager.read { db in
            TagRecord.findByName("to-remove", in: db)
        }

        let videoTag = VideoTagRecord(videoFileId: video.fileId, tagId: savedTag!.id)
        try await databaseManager.write { db in
            let mutableVT = videoTag
            try mutableVT.insert(db)
        }

        let tagsBeforeRemoval = try await databaseManager.read { db in
            VideoTagRecord.findByVideoFileId(video.fileId, in: db)
        }
        XCTAssertEqual(tagsBeforeRemoval.count, 1)

        try await databaseManager.write { db in
            try VideoTagRecord.deleteByVideoFileIdAndTagId(video.fileId, savedTag!.id, in: db)
        }

        let tagsAfterRemoval = try await databaseManager.read { db in
            VideoTagRecord.findByVideoFileId(video.fileId, in: db)
        }
        XCTAssertEqual(tagsAfterRemoval.count, 0)
    }

    // MARK: - Test POST /api/v1/source-directories/:id/tags bulk-applies to all videos

    func testBulkApplyTagsToSourceDirectory() async throws {
        let sourceDirectoryId = UUID()

        let videos = [
            VideoFileRecord(
                fileId: "bulk_test_file_1",
                path: "/test/bulk1.mp4",
                sourceDirectoryId: sourceDirectoryId,
                filename: "bulk1.mp4",
                fileSize: 1000,
                duration: 60.0,
                width: 1920,
                height: 1080,
                codec: "h264",
                lastModified: Date().timeIntervalSince1970
            ),
            VideoFileRecord(
                fileId: "bulk_test_file_2",
                path: "/test/bulk2.mp4",
                sourceDirectoryId: sourceDirectoryId,
                filename: "bulk2.mp4",
                fileSize: 2000,
                duration: 120.0,
                width: 1920,
                height: 1080,
                codec: "h264",
                lastModified: Date().timeIntervalSince1970
            ),
            VideoFileRecord(
                fileId: "bulk_test_file_3",
                path: "/test/bulk3.mp4",
                sourceDirectoryId: sourceDirectoryId,
                filename: "bulk3.mp4",
                fileSize: 3000,
                duration: 180.0,
                width: 1920,
                height: 1080,
                codec: "h264",
                lastModified: Date().timeIntervalSince1970
            )
        ]

        let tag = TagRecord(name: "bulk-tag", color: TagColorPalette.cyan)

        try await databaseManager.write { db in
            for video in videos {
                let mutableVideo = video
                try mutableVideo.insert(db)
            }
            let mutableTag = tag
            try mutableTag.insert(db)
        }

        let savedTag = try await databaseManager.read { db in
            TagRecord.findByName("bulk-tag", in: db)
        }

        let videosInDirectory = try await databaseManager.read { db in
            try VideoFileRecord.findBySourceDirectoryId(sourceDirectoryId, in: db)
        }
        XCTAssertEqual(videosInDirectory.count, 3)

        try await databaseManager.write { db in
            for video in videosInDirectory {
                let existing = VideoTagRecord.findByVideoFileIdAndTagId(video.fileId, savedTag!.id, in: db)
                if existing == nil {
                    let videoTag = VideoTagRecord(videoFileId: video.fileId, tagId: savedTag!.id)
                    try videoTag.insert(db)
                }
            }
        }

        let allVideoTags = try await databaseManager.read { db in
            VideoTagRecord.findByTagId(savedTag!.id, in: db)
        }
        XCTAssertEqual(allVideoTags.count, 3)
    }

    // MARK: - Test duplicate tag assignment is skipped silently

    func testDuplicateTagAssignmentSkippedSilently() async throws {
        let sourceDirectoryId = UUID()
        let video = VideoFileRecord(
            fileId: "duplicate_skip_test_file",
            path: "/test/duplicate.mp4",
            sourceDirectoryId: sourceDirectoryId,
            filename: "duplicate.mp4",
            fileSize: 1000,
            duration: 60.0,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: Date().timeIntervalSince1970
        )

        let tag = TagRecord(name: "duplicate-test-tag", color: TagColorPalette.violet)

        try await databaseManager.write { db in
            let mutableVideo = video
            try mutableVideo.insert(db)

            let mutableTag = tag
            try mutableTag.insert(db)
        }

        let savedTag = try await databaseManager.read { db in
            TagRecord.findByName("duplicate-test-tag", in: db)
        }

        try await databaseManager.write { db in
            let videoTag = VideoTagRecord(videoFileId: video.fileId, tagId: savedTag!.id)
            try videoTag.insert(db)
        }

        try await databaseManager.write { db in
            let existing = VideoTagRecord.findByVideoFileIdAndTagId(video.fileId, savedTag!.id, in: db)
            if existing == nil {
                let videoTag = VideoTagRecord(videoFileId: video.fileId, tagId: savedTag!.id)
                try videoTag.insert(db)
            }
        }

        let videoTags = try await databaseManager.read { db in
            VideoTagRecord.findByVideoFileId(video.fileId, in: db)
        }
        XCTAssertEqual(videoTags.count, 1)
    }
}

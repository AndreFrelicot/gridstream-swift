import GridStreamAPI
import XCTest
import GRDB
@testable import gridstream_macos

final class TagRecordTests: XCTestCase {

    var testDatabaseURL: URL!
    var databaseManager: DatabaseManager!

    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GridStreamTagTests_\(UUID().uuidString)")
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

    // MARK: - TagRecord CRUD Tests

    func testTagRecordCreateAndFindByName() async throws {
        let tag = TagRecord(
            name: "interview",
            color: TagColorPalette.red,
            description: "Interview clips"
        )

        try await databaseManager.write { db in
            let mutableTag = tag
            try mutableTag.insert(db)
        }

        let foundTag = try await databaseManager.read { db in
            TagRecord.findByName("INTERVIEW", in: db)
        }

        XCTAssertNotNil(foundTag)
        XCTAssertEqual(foundTag?.name, "interview")
        XCTAssertEqual(foundTag?.color, TagColorPalette.red)
        XCTAssertEqual(foundTag?.description, "Interview clips")
    }

    func testTagRecordFindAll() async throws {
        let tags = [
            TagRecord(name: "action", color: TagColorPalette.red, description: nil),
            TagRecord(name: "documentary", color: TagColorPalette.blue, description: nil),
            TagRecord(name: "music", color: TagColorPalette.green, description: nil)
        ]

        try await databaseManager.write { db in
            for tag in tags {
                let mutableTag = tag
                try mutableTag.insert(db)
            }
        }

        let allTags = try await databaseManager.read { db in
            TagRecord.findAll(in: db)
        }

        XCTAssertEqual(allTags.count, 3)
    }

    // MARK: - VideoTagRecord Association Tests

    func testVideoTagRecordAssociationCreateAndLookup() async throws {
        let videoFileRecord = VideoFileRecord(
            fileId: "test_file_id_123",
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

        let tag = TagRecord(
            name: "favorite",
            color: TagColorPalette.pink,
            description: nil
        )

        try await databaseManager.write { db in
            let mutableVideo = videoFileRecord
            try mutableVideo.insert(db)

            let mutableTag = tag
            try mutableTag.insert(db)
        }

        let savedTag = try await databaseManager.read { db in
            TagRecord.findByName("favorite", in: db)
        }

        let videoTag = VideoTagRecord(
            videoFileId: videoFileRecord.fileId,
            tagId: savedTag!.id
        )

        try await databaseManager.write { db in
            let mutableVideoTag = videoTag
            try mutableVideoTag.insert(db)
        }

        let tagsForVideo = try await databaseManager.read { db in
            VideoTagRecord.findByVideoFileId(videoFileRecord.fileId, in: db)
        }

        XCTAssertEqual(tagsForVideo.count, 1)
        XCTAssertEqual(tagsForVideo.first?.tagId, savedTag?.id)
    }

    // MARK: - Unique Constraint Tests

    func testDuplicateTagNameThrowsError() async throws {
        let tag1 = TagRecord(
            name: "unique",
            color: TagColorPalette.red,
            description: nil
        )

        try await databaseManager.write { db in
            let mutableTag = tag1
            try mutableTag.insert(db)
        }

        let tag2 = TagRecord(
            name: "unique",
            color: TagColorPalette.blue,
            description: nil
        )

        do {
            try await databaseManager.write { db in
                let mutableTag = tag2
                try mutableTag.insert(db)
            }
            XCTFail("Expected unique constraint violation")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("UNIQUE") || error is GRDB.DatabaseError)
        }
    }

    func testDuplicateVideoTagAssignmentThrowsError() async throws {
        let videoFileRecord = VideoFileRecord(
            fileId: "test_file_id_456",
            path: "/test/path/video2.mp4",
            sourceDirectoryId: UUID(),
            filename: "video2.mp4",
            fileSize: 2000,
            duration: 180.0,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: Date().timeIntervalSince1970
        )

        let tag = TagRecord(
            name: "duplicate-test",
            color: TagColorPalette.amber,
            description: nil
        )

        try await databaseManager.write { db in
            let mutableVideo = videoFileRecord
            try mutableVideo.insert(db)

            let mutableTag = tag
            try mutableTag.insert(db)
        }

        let savedTag = try await databaseManager.read { db in
            TagRecord.findByName("duplicate-test", in: db)
        }

        let videoTag1 = VideoTagRecord(
            videoFileId: videoFileRecord.fileId,
            tagId: savedTag!.id
        )

        try await databaseManager.write { db in
            let mutableVideoTag = videoTag1
            try mutableVideoTag.insert(db)
        }

        let videoTag2 = VideoTagRecord(
            videoFileId: videoFileRecord.fileId,
            tagId: savedTag!.id
        )

        do {
            try await databaseManager.write { db in
                let mutableVideoTag = videoTag2
                try mutableVideoTag.insert(db)
            }
            XCTFail("Expected unique constraint violation for duplicate video-tag assignment")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("UNIQUE") || error is GRDB.DatabaseError)
        }
    }

    // MARK: - Tag Count Query Tests

    func testCountVideosForTag() async throws {
        let tag = TagRecord(
            name: "count-test",
            color: TagColorPalette.cyan,
            description: nil
        )

        try await databaseManager.write { db in
            let mutableTag = tag
            try mutableTag.insert(db)
        }

        let savedTag = try await databaseManager.read { db in
            TagRecord.findByName("count-test", in: db)
        }

        for i in 0..<5 {
            let video = VideoFileRecord(
                fileId: "count_test_file_\(i)",
                path: "/test/path/video_\(i).mp4",
                sourceDirectoryId: UUID(),
                filename: "video_\(i).mp4",
                fileSize: Int64(1000 * (i + 1)),
                duration: Double(120 * (i + 1)),
                width: 1920,
                height: 1080,
                codec: "h264",
                lastModified: Date().timeIntervalSince1970
            )

            let videoTag = VideoTagRecord(
                videoFileId: video.fileId,
                tagId: savedTag!.id
            )

            try await databaseManager.write { db in
                let mutableVideo = video
                try mutableVideo.insert(db)

                let mutableVideoTag = videoTag
                try mutableVideoTag.insert(db)
            }
        }

        let videoCount = try await databaseManager.read { db in
            TagRecord.countVideos(for: savedTag!.id, in: db)
        }

        XCTAssertEqual(videoCount, 5)
    }
}

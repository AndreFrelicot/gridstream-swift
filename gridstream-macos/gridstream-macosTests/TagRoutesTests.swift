import GridStreamAPI
import XCTest
import Vapor
import GRDB
@testable import gridstream_macos

final class TagRoutesTests: XCTestCase {

    var testDatabaseURL: URL!
    var databaseManager: DatabaseManager!
    var app: Application!

    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GridStreamTagRoutesTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        testDatabaseURL = testDir.appendingPathComponent("test_gridstream.sqlite")
        databaseManager = DatabaseManager(databasePath: testDatabaseURL)
        try await databaseManager.initialize()

        var env = try Environment.detect()
        env.arguments = ["vapor", "test"]
        app = try await Application.make(env)
        app.middleware.use(ErrorMiddleware.default(environment: app.environment))
        try app.register(collection: TagRoutes(databaseManager: databaseManager))
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

    // MARK: - Test GET /api/v1/tags returns list with video counts

    func testGetTagsReturnsListWithVideoCounts() async throws {
        let tag1 = TagRecord(name: "action", color: TagColorPalette.red)
        let tag2 = TagRecord(name: "documentary", color: TagColorPalette.blue)

        try await databaseManager.write { db in
            let mutableTag1 = tag1
            let mutableTag2 = tag2
            try mutableTag1.insert(db)
            try mutableTag2.insert(db)
        }

        let video = VideoFileRecord(
            fileId: "test_file_123",
            path: "/test/video.mp4",
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
            let mutableVideo = video
            try mutableVideo.insert(db)
        }

        let savedTag1 = try await databaseManager.read { db in
            TagRecord.findByName("action", in: db)
        }

        let videoTag = VideoTagRecord(videoFileId: video.fileId, tagId: savedTag1!.id)
        try await databaseManager.write { db in
            let mutableVideoTag = videoTag
            try mutableVideoTag.insert(db)
        }

        let allTags = try await databaseManager.read { db in
            TagRecord.findAll(in: db)
        }
        XCTAssertEqual(allTags.count, 2)

        let actionTagVideoCount = try await databaseManager.read { db in
            TagRecord.countVideos(for: savedTag1!.id, in: db)
        }
        XCTAssertEqual(actionTagVideoCount, 1)

        let savedTag2 = try await databaseManager.read { db in
            TagRecord.findByName("documentary", in: db)
        }
        let docTagVideoCount = try await databaseManager.read { db in
            TagRecord.countVideos(for: savedTag2!.id, in: db)
        }
        XCTAssertEqual(docTagVideoCount, 0)
    }

    // MARK: - Test POST /api/v1/tags creates tag with valid data

    func testCreateTagWithValidData() async throws {
        let newTag = TagRecord(
            name: "favorite",
            color: TagColorPalette.pink,
            description: "My favorite videos"
        )

        try await databaseManager.write { db in
            let mutableTag = newTag
            try mutableTag.insert(db)
        }

        let savedTag = try await databaseManager.read { db in
            TagRecord.findByName("favorite", in: db)
        }

        XCTAssertNotNil(savedTag)
        XCTAssertEqual(savedTag?.name, "favorite")
        XCTAssertEqual(savedTag?.color, TagColorPalette.pink)
        XCTAssertEqual(savedTag?.description, "My favorite videos")
    }

    // MARK: - Test POST /api/v1/tags returns 400 for invalid color or duplicate name

    func testCreateTagWithInvalidColorFails() async throws {
        let invalidColor = "#INVALID"
        XCTAssertFalse(TagColorPalette.isValidColor(invalidColor))
    }

    func testCreateTagWithDuplicateNameFails() async throws {
        let tag1 = TagRecord(name: "unique", color: TagColorPalette.red)
        try await databaseManager.write { db in
            let mutableTag = tag1
            try mutableTag.insert(db)
        }

        let tag2 = TagRecord(name: "UNIQUE", color: TagColorPalette.blue)

        do {
            try await databaseManager.write { db in
                let mutableTag = tag2
                try mutableTag.insert(db)
            }
            XCTFail("Expected duplicate name to fail")
        } catch {
            XCTAssertTrue(error is GRDB.DatabaseError)
        }
    }

    // MARK: - Test PUT /api/v1/tags/:id updates tag properties

    func testUpdateTagProperties() async throws {
        var tag = TagRecord(
            name: "original",
            color: TagColorPalette.red,
            description: "Original description"
        )

        try await databaseManager.write { [tag] db in
            try tag.insert(db)
        }

        let originalUpdatedAt = tag.updatedAt

        try await Task.sleep(nanoseconds: 100_000_000)

        tag.name = "updated"
        tag.color = TagColorPalette.blue
        tag.description = "Updated description"
        tag.touch()

        try await databaseManager.write { [tag] db in
            try tag.update(db)
        }

        let updatedTag = try await databaseManager.read { [tag] db in
            TagRecord.findById(tag.id, in: db)
        }

        XCTAssertNotNil(updatedTag)
        XCTAssertEqual(updatedTag?.name, "updated")
        XCTAssertEqual(updatedTag?.color, TagColorPalette.blue)
        XCTAssertEqual(updatedTag?.description, "Updated description")
        XCTAssertGreaterThan(updatedTag?.updatedAt ?? 0, originalUpdatedAt)
    }

    // MARK: - Test DELETE /api/v1/tags/:id removes tag

    func testDeleteTagRemovesTagAndAssociations() async throws {
        let tag = TagRecord(name: "to-delete", color: TagColorPalette.amber)

        try await databaseManager.write { db in
            let mutableTag = tag
            try mutableTag.insert(db)
        }

        let savedTag = try await databaseManager.read { db in
            TagRecord.findByName("to-delete", in: db)
        }
        XCTAssertNotNil(savedTag)

        let video = VideoFileRecord(
            fileId: "delete_test_file",
            path: "/test/delete_video.mp4",
            sourceDirectoryId: UUID(),
            filename: "delete_video.mp4",
            fileSize: 1000,
            duration: 120.0,
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

        let affectedCount = try await databaseManager.read { db in
            TagRecord.countVideos(for: savedTag!.id, in: db)
        }
        XCTAssertEqual(affectedCount, 1)

        try await databaseManager.write { db in
            _ = try VideoTagRecord
                .filter(Column("tag_id") == savedTag!.id)
                .deleteAll(db)

            _ = try TagRecord
                .filter(Column("id") == savedTag!.id)
                .deleteAll(db)
        }

        let deletedTag = try await databaseManager.read { db in
            TagRecord.findById(savedTag!.id, in: db)
        }
        XCTAssertNil(deletedTag)

        let remainingAssociations = try await databaseManager.read { db in
            VideoTagRecord.findByTagId(savedTag!.id, in: db)
        }
        XCTAssertEqual(remainingAssociations.count, 0)
    }
}

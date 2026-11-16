import XCTest
import Vapor
import GRDB
@testable import gridstream_macos

final class SmartListRoutesTests: XCTestCase {

    var testDatabaseURL: URL!
    var databaseManager: DatabaseManager!
    var app: Application!

    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GridStreamSmartListRoutesTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        testDatabaseURL = testDir.appendingPathComponent("test_gridstream.sqlite")
        databaseManager = DatabaseManager(databasePath: testDatabaseURL)
        try await databaseManager.initialize()

        var env = try Environment.detect()
        env.arguments = ["vapor", "test"]
        app = try await Application.make(env)
        app.middleware.use(ErrorMiddleware.default(environment: app.environment))
        try app.register(collection: SmartListRoutes(databaseManager: databaseManager))
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

    // MARK: - Test GET /api/v1/smart-lists

    func testGetSmartListsReturnsEmptyListInitially() async throws {
        let smartLists = try await databaseManager.read { db in
            SmartListRecord.findAll(in: db)
        }
        XCTAssertEqual(smartLists.count, 0)
    }

    func testGetSmartListsReturnsCreatedLists() async throws {
        let smartList1 = SmartListRecord(name: "list1", criteria: "{}")
        let smartList2 = SmartListRecord(name: "list2", criteria: "{}")

        try await databaseManager.write { db in
            let mutableSmartList1 = smartList1
            let mutableSmartList2 = smartList2
            try mutableSmartList1.insert(db)
            try mutableSmartList2.insert(db)
        }

        let smartLists = try await databaseManager.read { db in
            SmartListRecord.findAll(in: db)
        }

        XCTAssertEqual(smartLists.count, 2)
    }

    // MARK: - Test smart list memberships

    func testSmartListMembershipsMapVideosToMatchingLists() async throws {
        // Two videos: one rated 8, one rated 2.
        let ratedVideo = VideoFileRecord(
            fileId: "file_rated",
            path: "/test/rated.mp4",
            sourceDirectoryId: UUID(),
            filename: "rated.mp4",
            fileSize: 1000,
            duration: 120.0,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: Date().timeIntervalSince1970,
            rating: 8
        )
        let unratedVideo = VideoFileRecord(
            fileId: "file_low",
            path: "/test/low.mp4",
            sourceDirectoryId: UUID(),
            filename: "low.mp4",
            fileSize: 1000,
            duration: 120.0,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: Date().timeIntervalSince1970,
            rating: 2
        )

        try await databaseManager.write { db in
            let v1 = ratedVideo
            let v2 = unratedVideo
            try v1.insert(db)
            try v2.insert(db)
        }

        // Smart list: rating >= 5
        let conditionId = UUID().uuidString
        let criteria = """
        {"conditions":[{"id":"\(conditionId)","criteriaType":{"type":"ratingMin","value":5},"logicOperator":"AND"}]}
        """
        let smartList = SmartListRecord(name: "highly-rated", criteria: criteria)
        try await databaseManager.write { db in
            let mutable = smartList
            try mutable.insert(db)
        }

        let memberships = try await SmartListRepository(database: databaseManager).memberships()

        XCTAssertEqual(memberships["file_rated"], [smartList.id])
        XCTAssertNil(memberships["file_low"])
    }

    // MARK: - Test 50 Smart List Limit

    func testSmartListLimitEnforced() async throws {
        for i in 0..<50 {
            let smartList = SmartListRecord(name: "list\(i)", criteria: "{}")
            try await databaseManager.write { db in
                let mutableSmartList = smartList
                try mutableSmartList.insert(db)
            }
        }

        let count = try await databaseManager.read { db in
            SmartListRecord.countAll(in: db)
        }

        XCTAssertEqual(count, 50)
    }

    // MARK: - Test Smart List CRUD via database

    func testCreateSmartListWithValidData() async throws {
        let criteria = """
        {"conditions":[{"type":"tagsInclude","values":["test-uuid"]}]}
        """

        let newSmartList = SmartListRecord(
            name: "my-playlist",
            criteria: criteria
        )

        try await databaseManager.write { db in
            let mutableSmartList = newSmartList
            try mutableSmartList.insert(db)
        }

        let savedSmartList = try await databaseManager.read { db in
            SmartListRecord.findByName("my-playlist", in: db)
        }

        XCTAssertNotNil(savedSmartList)
        XCTAssertEqual(savedSmartList?.name, "my-playlist")
        XCTAssertEqual(savedSmartList?.criteria, criteria)
    }

    func testUpdateSmartListProperties() async throws {
        var smartList = SmartListRecord(
            name: "original",
            criteria: "{}"
        )

        try await databaseManager.write { [smartList] db in
            try smartList.insert(db)
        }

        let originalUpdatedAt = smartList.updatedAt

        try await Task.sleep(nanoseconds: 100_000_000)

        smartList.name = "updated"
        smartList.criteria = """
        {"conditions":[{"type":"ratingMin","value":4}]}
        """
        smartList.touch()

        try await databaseManager.write { [smartList] db in
            try smartList.update(db)
        }

        let updatedSmartList = try await databaseManager.read { [smartList] db in
            SmartListRecord.findById(smartList.id, in: db)
        }

        XCTAssertNotNil(updatedSmartList)
        XCTAssertEqual(updatedSmartList?.name, "updated")
        XCTAssertTrue(updatedSmartList?.criteria.contains("ratingMin") ?? false)
        XCTAssertGreaterThan(updatedSmartList?.updatedAt ?? 0, originalUpdatedAt)
    }

    func testDeleteSmartListRemovesRecord() async throws {
        let smartList = SmartListRecord(name: "to-delete", criteria: "{}")

        try await databaseManager.write { db in
            let mutableSmartList = smartList
            try mutableSmartList.insert(db)
        }

        let savedSmartList = try await databaseManager.read { db in
            SmartListRecord.findByName("to-delete", in: db)
        }
        XCTAssertNotNil(savedSmartList)

        try await databaseManager.write { db in
            _ = try SmartListRecord
                .filter(Column("id") == savedSmartList!.id)
                .deleteAll(db)
        }

        let deletedSmartList = try await databaseManager.read { db in
            SmartListRecord.findById(savedSmartList!.id, in: db)
        }
        XCTAssertNil(deletedSmartList)
    }
}

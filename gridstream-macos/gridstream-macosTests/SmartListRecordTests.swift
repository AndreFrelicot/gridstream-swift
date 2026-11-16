import XCTest
import GRDB
@testable import gridstream_macos

final class SmartListRecordTests: XCTestCase {

    var testDatabaseURL: URL!
    var databaseManager: DatabaseManager!

    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GridStreamSmartListTests_\(UUID().uuidString)")
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

    // MARK: - SmartListRecord CRUD Tests

    func testSmartListRecordCreateAndFindById() async throws {
        let criteria = """
        {"conditions":[{"type":"tagsInclude","values":["uuid1","uuid2"]}]}
        """

        let smartList = SmartListRecord(
            name: "favorites",
            criteria: criteria
        )

        try await databaseManager.write { db in
            let mutableSmartList = smartList
            try mutableSmartList.insert(db)
        }

        let foundSmartList = try await databaseManager.read { db in
            SmartListRecord.findById(smartList.id, in: db)
        }

        XCTAssertNotNil(foundSmartList)
        XCTAssertEqual(foundSmartList?.name, "favorites")
        XCTAssertEqual(foundSmartList?.criteria, criteria)
    }

    func testSmartListRecordFindByNameCaseInsensitive() async throws {
        let smartList = SmartListRecord(
            name: "MyPlaylist",
            criteria: "{}"
        )

        try await databaseManager.write { db in
            let mutableSmartList = smartList
            try mutableSmartList.insert(db)
        }

        let foundSmartList = try await databaseManager.read { db in
            SmartListRecord.findByName("MYPLAYLIST", in: db)
        }

        XCTAssertNotNil(foundSmartList)
        XCTAssertEqual(foundSmartList?.name, "myplaylist")
    }

    func testSmartListRecordFindAllAndCountAll() async throws {
        let smartLists = [
            SmartListRecord(name: "list1", criteria: "{}"),
            SmartListRecord(name: "list2", criteria: "{}"),
            SmartListRecord(name: "list3", criteria: "{}")
        ]

        try await databaseManager.write { db in
            for smartList in smartLists {
                let mutableSmartList = smartList
                try mutableSmartList.insert(db)
            }
        }

        let allSmartLists = try await databaseManager.read { db in
            SmartListRecord.findAll(in: db)
        }

        let count = try await databaseManager.read { db in
            SmartListRecord.countAll(in: db)
        }

        XCTAssertEqual(allSmartLists.count, 3)
        XCTAssertEqual(count, 3)
    }

    func testSmartListRecordUpdateAndTouch() async throws {
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
        {"conditions":[{"type":"ratingMin","value":3}]}
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

    func testSmartListRecordDelete() async throws {
        let smartList = SmartListRecord(
            name: "to-delete",
            criteria: "{}"
        )

        try await databaseManager.write { db in
            let mutableSmartList = smartList
            try mutableSmartList.insert(db)
        }

        let savedSmartList = try await databaseManager.read { db in
            SmartListRecord.findById(smartList.id, in: db)
        }
        XCTAssertNotNil(savedSmartList)

        try await databaseManager.write { db in
            _ = try SmartListRecord
                .filter(Column("id") == smartList.id)
                .deleteAll(db)
        }

        let deletedSmartList = try await databaseManager.read { db in
            SmartListRecord.findById(smartList.id, in: db)
        }
        XCTAssertNil(deletedSmartList)
    }

    func testDuplicateSmartListNameThrowsError() async throws {
        let smartList1 = SmartListRecord(name: "unique", criteria: "{}")

        try await databaseManager.write { db in
            let mutableSmartList = smartList1
            try mutableSmartList.insert(db)
        }

        let smartList2 = SmartListRecord(name: "UNIQUE", criteria: "{}")

        do {
            try await databaseManager.write { db in
                let mutableSmartList = smartList2
                try mutableSmartList.insert(db)
            }
            XCTFail("Expected unique constraint violation")
        } catch {
            XCTAssertTrue(error is GRDB.DatabaseError)
        }
    }
}

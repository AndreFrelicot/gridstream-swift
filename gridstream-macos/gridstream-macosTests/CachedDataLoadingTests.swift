import XCTest
import GRDB
@testable import gridstream_macos

final class CachedDataLoadingTests: XCTestCase {

    var testDatabaseURL: URL!
    var databaseManager: DatabaseManager!

    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GridStreamCacheTests_\(UUID().uuidString)")
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

    // MARK: - fetchAllRecords Tests

    func testFetchAllRecordsReturnsAllVideoFileRecords() async throws {
        // Insert multiple video records
        let sourceDirectoryId = UUID()
        let records = [
            createVideoRecord(fileId: "file_1", filename: "video1.mp4", sourceDirectoryId: sourceDirectoryId),
            createVideoRecord(fileId: "file_2", filename: "video2.mp4", sourceDirectoryId: sourceDirectoryId),
            createVideoRecord(fileId: "file_3", filename: "video3.mp4", sourceDirectoryId: sourceDirectoryId)
        ]

        for record in records {
            try await databaseManager.write { db in
                let mutableRecord = record
                try mutableRecord.insert(db)
            }
        }

        // Fetch all records
        let fetchedRecords = try await databaseManager.read { db in
            try VideoFileRecord.fetchAllRecords(in: db)
        }

        XCTAssertEqual(fetchedRecords.count, 3)
        let fileIds = Set(fetchedRecords.map { $0.fileId })
        XCTAssertTrue(fileIds.contains("file_1"))
        XCTAssertTrue(fileIds.contains("file_2"))
        XCTAssertTrue(fileIds.contains("file_3"))
    }

    func testFetchAllRecordsReturnsEmptyArrayWhenNoneExist() async throws {
        let fetchedRecords = try await databaseManager.read { db in
            try VideoFileRecord.fetchAllRecords(in: db)
        }

        XCTAssertEqual(fetchedRecords.count, 0)
    }

    // MARK: - Catalog Version Tests

    func testFetchCatalogVersionReturnsStoredVersion() async throws {
        // The migration initializes a catalog version, so it should exist
        let version = try await databaseManager.fetchCatalogVersion()

        // Version should be a positive timestamp (in milliseconds)
        XCTAssertGreaterThan(version, 0)
    }

    func testUpdateCatalogVersionPersistsNewValue() async throws {
        let testVersion: Int64 = 1703097600000  // A specific timestamp

        try await databaseManager.updateCatalogVersion(testVersion)

        let fetchedVersion = try await databaseManager.fetchCatalogVersion()
        XCTAssertEqual(fetchedVersion, testVersion)
    }

    func testUpdateCatalogVersionGeneratesTimestampWhenNotProvided() async throws {
        let beforeUpdate = Int64(Date().timeIntervalSince1970 * 1000)

        try await databaseManager.updateCatalogVersion()

        let fetchedVersion = try await databaseManager.fetchCatalogVersion()
        let afterUpdate = Int64(Date().timeIntervalSince1970 * 1000)

        XCTAssertGreaterThanOrEqual(fetchedVersion, beforeUpdate)
        XCTAssertLessThanOrEqual(fetchedVersion, afterUpdate)
    }

    // MARK: - deleteBySourceDirectoryId Tests

    func testDeleteBySourceDirectoryIdRemovesRecordsAndThumbnails() async throws {
        let sourceDirectoryId1 = UUID()
        let sourceDirectoryId2 = UUID()

        // Insert video records for two different source directories
        let record1 = createVideoRecord(fileId: "file_1", filename: "video1.mp4", sourceDirectoryId: sourceDirectoryId1)
        let record2 = createVideoRecord(fileId: "file_2", filename: "video2.mp4", sourceDirectoryId: sourceDirectoryId1)
        let record3 = createVideoRecord(fileId: "file_3", filename: "video3.mp4", sourceDirectoryId: sourceDirectoryId2)

        for record in [record1, record2, record3] {
            try await databaseManager.write { db in
                let mutableRecord = record
                try mutableRecord.insert(db)
            }
        }

        // Insert thumbnails for the files
        let thumbnail1 = ThumbnailRecord(fileId: "file_1", imageData: Data([0x00, 0x01, 0x02]))
        let thumbnail2 = ThumbnailRecord(fileId: "file_2", imageData: Data([0x03, 0x04, 0x05]))
        let thumbnail3 = ThumbnailRecord(fileId: "file_3", imageData: Data([0x06, 0x07, 0x08]))

        for thumbnail in [thumbnail1, thumbnail2, thumbnail3] {
            try await databaseManager.write { db in
                let mutableThumbnail = thumbnail
                try mutableThumbnail.insert(db)
            }
        }

        // Delete records for sourceDirectoryId1
        let deletedCount = try await databaseManager.write { db in
            try VideoFileRecord.deleteBySourceDirectoryId(sourceDirectoryId1, in: db)
        }

        XCTAssertEqual(deletedCount, 2)

        // Verify only records from sourceDirectoryId2 remain
        let remainingRecords = try await databaseManager.read { db in
            try VideoFileRecord.fetchAllRecords(in: db)
        }
        XCTAssertEqual(remainingRecords.count, 1)
        XCTAssertEqual(remainingRecords.first?.fileId, "file_3")

        // Verify thumbnails for deleted files are also removed
        let remainingThumbnails = try await databaseManager.read { db in
            try ThumbnailRecord.fetchAll(db)
        }
        XCTAssertEqual(remainingThumbnails.count, 1)
        XCTAssertEqual(remainingThumbnails.first?.fileId, "file_3")
    }

    func testDeleteBySourceDirectoryIdReturnsZeroWhenNoRecordsMatch() async throws {
        let nonExistentSourceId = UUID()

        let deletedCount = try await databaseManager.write { db in
            try VideoFileRecord.deleteBySourceDirectoryId(nonExistentSourceId, in: db)
        }

        XCTAssertEqual(deletedCount, 0)
    }

    // MARK: - Helper Methods

    private func createVideoRecord(
        fileId: String,
        filename: String,
        sourceDirectoryId: UUID
    ) -> VideoFileRecord {
        VideoFileRecord(
            fileId: fileId,
            path: "/test/path/\(filename)",
            sourceDirectoryId: sourceDirectoryId,
            filename: filename,
            fileSize: 1000,
            duration: 120.0,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: Date().timeIntervalSince1970
        )
    }
}

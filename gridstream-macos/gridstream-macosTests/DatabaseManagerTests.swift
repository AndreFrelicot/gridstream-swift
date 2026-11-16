import XCTest
import GRDB
@testable import gridstream_macos

final class DatabaseManagerTests: XCTestCase {

    var testDatabaseURL: URL!
    var databaseManager: DatabaseManager!

    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GridStreamTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        testDatabaseURL = testDir.appendingPathComponent("test_gridstream.sqlite")
        databaseManager = DatabaseManager(databasePath: testDatabaseURL)
    }

    override func tearDown() async throws {
        try await databaseManager.close()
        let testDir = testDatabaseURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: testDir)
        databaseManager = nil
        testDatabaseURL = nil
    }

    func testDatabaseFileCreatedAtExpectedPath() async throws {
        try await databaseManager.initialize()

        let expectedPath = await databaseManager.databasePath
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedPath.path))
        XCTAssertEqual(expectedPath, testDatabaseURL)
    }

    func testConnectionPoolInitialization() async throws {
        let isInitializedBefore = await databaseManager.isInitialized
        XCTAssertFalse(isInitializedBefore)

        try await databaseManager.initialize()

        let isInitializedAfter = await databaseManager.isInitialized
        XCTAssertTrue(isInitializedAfter)

        let tableExists = try await databaseManager.read { db in
            try db.tableExists("video_files")
        }
        XCTAssertTrue(tableExists)
    }

    func testMigrationExecutesWithoutError() async throws {
        try await databaseManager.initialize()

        let columnNames: [String] = try await databaseManager.read { db in
            let columns = try db.columns(in: "video_files")
            return columns.map { $0.name }
        }

        let expectedColumns = [
            "id", "file_id", "path", "source_directory_id", "filename",
            "file_size", "duration", "width", "height", "codec",
            "last_modified", "created_at", "updated_at"
        ]

        for column in expectedColumns {
            XCTAssertTrue(columnNames.contains(column), "Missing column: \(column)")
        }

        let indexNames: [String] = try await databaseManager.read { db in
            let rows = try Row.fetchAll(db, sql: "PRAGMA index_list('video_files')")
            return rows.compactMap { $0["name"] as? String }
        }

        XCTAssertTrue(indexNames.contains("idx_video_files_file_id"), "Missing index on file_id")
        XCTAssertTrue(indexNames.contains("idx_video_files_source_directory_id"), "Missing index on source_directory_id")
    }

    func testDatabaseHandlesConcurrentAccess() async throws {
        try await databaseManager.initialize()
        let databaseManager: DatabaseManager = self.databaseManager

        await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask { @Sendable in
                    let record = VideoFileRecord(
                        fileId: "test_file_id_\(i)",
                        path: "/test/path/\(i).mp4",
                        sourceDirectoryId: UUID(),
                        filename: "video_\(i).mp4",
                        fileSize: Int64(1000 * (i + 1)),
                        duration: Double(120 * (i + 1)),
                        width: 1920,
                        height: 1080,
                        codec: "h264",
                        lastModified: Date().timeIntervalSince1970
                    )

                    do {
                        try await databaseManager.write { db in
                            let mutableRecord = record
                            try mutableRecord.insert(db)
                        }
                    } catch {
                        XCTFail("Failed to insert record \(i): \(error)")
                    }
                }
            }
        }

        let count = try await databaseManager.read { db in
            try VideoFileRecord.fetchCount(db)
        }

        XCTAssertEqual(count, 10)
    }
}

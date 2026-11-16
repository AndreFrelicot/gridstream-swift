import XCTest
@testable import gridstream_macos

final class DataDirectoryMigrationTests: XCTestCase {
    private var root: URL!
    private var source: URL!
    private var destination: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DataDirectoryMigrationTests_\(UUID().uuidString)")
        source = root.appendingPathComponent("old", isDirectory: true)
        destination = root.appendingPathComponent("new", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ name: String, in directory: URL, _ text: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: directory.appendingPathComponent(name))
    }

    private func read(_ name: String, in directory: URL) -> String? {
        (try? Data(contentsOf: directory.appendingPathComponent(name))).map { String(decoding: $0, as: UTF8.self) }
    }

    func testMovesDatabaseWithWalAndShm() throws {
        for name in DataDirectoryMigration.databaseFileNames {
            try write(name, in: source, name)
        }

        XCTAssertEqual(try DataDirectoryMigration.moveDatabase(from: source, to: destination), .moved)

        for name in DataDirectoryMigration.databaseFileNames {
            XCTAssertEqual(read(name, in: destination), name)
            XCTAssertNil(read(name, in: source))
        }
    }

    func testNeverOverwritesAnExistingDatabase() throws {
        try write("gridstream.sqlite", in: source, "old")
        try write("gridstream.sqlite", in: destination, "existing")

        XCTAssertEqual(try DataDirectoryMigration.moveDatabase(from: source, to: destination), .destinationHasDatabase)
        XCTAssertEqual(read("gridstream.sqlite", in: destination), "existing")
        XCTAssertEqual(read("gridstream.sqlite", in: source), "old")
    }

    func testPendingMoveIsAppliedOnceAndCleared() throws {
        let suite = "DataDirectoryMigrationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        try write("gridstream.sqlite", in: source, "db")
        DataDirectoryMigration.applyPendingMove(to: destination, defaults: defaults)
        XCTAssertNil(read("gridstream.sqlite", in: destination), "Nothing pending, nothing moved")

        defaults.set(source.path, forKey: DataDirectoryMigration.pendingMoveKey)
        DataDirectoryMigration.applyPendingMove(to: destination, defaults: defaults)
        XCTAssertEqual(read("gridstream.sqlite", in: destination), "db")
        XCTAssertNil(defaults.string(forKey: DataDirectoryMigration.pendingMoveKey))
    }
}

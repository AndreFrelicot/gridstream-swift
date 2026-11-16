import Foundation
import OSLog

/// Moves the database when the user changes the data directory. The database
/// is open while the app runs, so the move is recorded as pending and done on
/// the next launch, before the database is opened.
nonisolated enum DataDirectoryMigration {
    static let pendingMoveKey = "pendingDataDirectoryMoveFrom"
    static let databaseFileNames = ["gridstream.sqlite", "gridstream.sqlite-wal", "gridstream.sqlite-shm"]

    enum Result: Equatable {
        case moved
        case nothingToMove
        /// The destination already holds a database: nothing is overwritten.
        case destinationHasDatabase
    }

    private static let logger = Logger(subsystem: "com.gridstream.macos", category: "DataDirectoryMigration")

    /// Moves `gridstream.sqlite` with its `-wal` and `-shm` files from `source` to `destination`.
    static func moveDatabase(from source: URL, to destination: URL, fileManager: FileManager = .default) throws -> Result {
        let sourceDatabase = source.appendingPathComponent(databaseFileNames[0])
        guard fileManager.fileExists(atPath: sourceDatabase.path) else { return .nothingToMove }
        guard source.standardizedFileURL != destination.standardizedFileURL else { return .nothingToMove }
        guard !fileManager.fileExists(atPath: destination.appendingPathComponent(databaseFileNames[0]).path) else {
            return .destinationHasDatabase
        }

        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in databaseFileNames {
            let from = source.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: from.path) else { continue }
            try fileManager.moveItem(at: from, to: destination.appendingPathComponent(name))
        }
        return .moved
    }

    /// Performs a move recorded by `ConfigurationService.changeDataDirectory`
    /// into `destination` (the current data directory), then clears it.
    static func applyPendingMove(to destination: URL, defaults: UserDefaults = .standard) {
        guard let sourcePath = defaults.string(forKey: pendingMoveKey) else { return }
        defaults.removeObject(forKey: pendingMoveKey)

        let source = URL(fileURLWithPath: sourcePath, isDirectory: true)
        do {
            let result = try moveDatabase(from: source, to: destination)
            logger.info("Pending database move from \(sourcePath, privacy: .public): \(String(describing: result), privacy: .public)")
        } catch {
            logger.error("Failed to move the database from \(sourcePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

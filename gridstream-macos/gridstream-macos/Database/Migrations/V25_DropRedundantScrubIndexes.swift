import Foundation
import GRDB

nonisolated enum V25_DropRedundantScrubIndexes: Sendable {
    static let migrationIdentifier = "v25_drop_redundant_scrub_indexes"

    static func migrate(_ db: Database) throws {
        // Duplicate of UNIQUE(file_id, timestamp):
        try db.execute(sql: "DROP INDEX IF EXISTS idx_scrub_frames_file_timestamp")
        // Prefix of the UNIQUE composite → covered by it for file_id-only lookups:
        try db.execute(sql: "DROP INDEX IF EXISTS idx_scrub_frames_file_id")
        // Single low-cardinality column ('jpeg' for all rows), unused:
        try db.execute(sql: "DROP INDEX IF EXISTS idx_scrub_frames_format")
    }
}

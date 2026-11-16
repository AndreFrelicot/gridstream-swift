import Foundation
import GRDB

/// Partial index on `last_played_at` for queries that filter `IS NOT NULL`.
/// The smart-list "played" filter uses `last_played_at IS NOT NULL`; a partial
/// index keyed only on non-null rows is more efficient than the full B-tree
/// index from V15 for that predicate.
nonisolated enum V23_AddLastPlayedAtPartialIndex: Sendable {
    static let migrationIdentifier = "v23_add_last_played_at_partial_index"

    static func migrate(_ db: Database) throws {
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_video_files_last_played_at_not_null
            ON video_files(last_played_at)
            WHERE last_played_at IS NOT NULL
            """)
    }
}

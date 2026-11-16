import Foundation
import GRDB

/// Soft delete for video files: a file that is no longer found in a readable
/// source folder gets `missing_since` set instead of being purged with its
/// tags, ratings, annotations and captures. NULL means "present".
nonisolated enum V27_AddMissingSince: Sendable {
    static let migrationIdentifier = "v27_add_missing_since"

    static func migrate(_ db: Database) throws {
        try db.alter(table: "video_files") { t in
            t.add(column: "missing_since", .double)
        }
        try db.create(index: "idx_video_files_missing_since", on: "video_files",
                      columns: ["missing_since"])
    }
}

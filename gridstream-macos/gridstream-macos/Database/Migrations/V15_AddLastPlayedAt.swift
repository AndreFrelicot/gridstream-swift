import Foundation
import GRDB

nonisolated enum V15_AddLastPlayedAt: Sendable {
    static let migrationIdentifier = "v15_add_last_played_at"

    static func migrate(_ db: Database) throws {
        try db.alter(table: "video_files") { t in
            t.add(column: "last_played_at", .double)
        }

        try db.create(
            index: "idx_video_files_last_played_at",
            on: "video_files",
            columns: ["last_played_at"]
        )
    }
}

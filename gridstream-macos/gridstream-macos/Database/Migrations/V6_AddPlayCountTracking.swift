import Foundation
import GRDB

nonisolated enum V6_AddPlayCountTracking: Sendable {
    static let migrationIdentifier = "v6_add_play_count_tracking"

    static func migrate(_ db: Database) throws {
        // Add play_count column to video_files table (0 = never played)
        try db.alter(table: "video_files") { t in
            t.add(column: "play_count", .integer).notNull().defaults(to: 0)
        }

        // Add total_view_time column to video_files table (seconds, 0 = never viewed)
        try db.alter(table: "video_files") { t in
            t.add(column: "total_view_time", .integer).notNull().defaults(to: 0)
        }

        // Create index on video_files.play_count for efficient sorting/filtering
        try db.create(
            index: "idx_video_files_play_count",
            on: "video_files",
            columns: ["play_count"]
        )
    }
}

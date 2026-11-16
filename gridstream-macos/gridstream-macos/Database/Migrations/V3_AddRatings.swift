import Foundation
import GRDB

nonisolated enum V3_AddRatings: Sendable {
    static let migrationIdentifier = "v3_add_ratings"

    static func migrate(_ db: Database) throws {
        // Add rating column to video_files table (0 = unrated, 1-10 = actual rating)
        try db.alter(table: "video_files") { t in
            t.add(column: "rating", .integer).notNull().defaults(to: 0)
        }

        // Create index on video_files.rating for efficient filtering/sorting
        try db.create(
            index: "idx_video_files_rating",
            on: "video_files",
            columns: ["rating"]
        )

        // Add rating_enabled column to tags table (stored as INTEGER: 0 = false, 1 = true)
        try db.alter(table: "tags") { t in
            t.add(column: "rating_enabled", .integer).notNull().defaults(to: 0)
        }

        // Add rating column to video_tags junction table for per-tag ratings
        try db.alter(table: "video_tags") { t in
            t.add(column: "rating", .integer).notNull().defaults(to: 0)
        }
    }
}

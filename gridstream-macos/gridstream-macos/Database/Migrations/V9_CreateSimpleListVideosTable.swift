import Foundation
import GRDB

nonisolated enum V9_CreateSimpleListVideosTable: Sendable {
    static let migrationIdentifier = "v9_create_simple_list_videos"

    static func migrate(_ db: Database) throws {
        try db.create(table: "simple_list_videos") { t in
            t.column("id", .text).primaryKey()
            t.column("simple_list_id", .text).notNull()
            t.column("video_file_id", .text).notNull()
            t.column("position", .integer).notNull().defaults(to: 0)
            t.column("added_at", .double).notNull()
        }

        try db.create(
            index: "idx_simple_list_videos_list_id",
            on: "simple_list_videos",
            columns: ["simple_list_id"]
        )

        try db.create(
            index: "idx_simple_list_videos_video_id",
            on: "simple_list_videos",
            columns: ["video_file_id"]
        )

        try db.create(
            index: "idx_simple_list_videos_unique",
            on: "simple_list_videos",
            columns: ["simple_list_id", "video_file_id"],
            unique: true
        )
    }
}

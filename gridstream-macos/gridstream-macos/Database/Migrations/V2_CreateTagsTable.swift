import Foundation
import GRDB

nonisolated enum V2_CreateTagsTable: Sendable {
    static let migrationIdentifier = "v2_create_tags"

    static func migrate(_ db: Database) throws {
        // Create tags table
        try db.create(table: "tags") { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull().unique()
            t.column("color", .text).notNull()
            t.column("description", .text)
            t.column("created_at", .double).notNull()
            t.column("updated_at", .double).notNull()
        }

        try db.create(
            index: "idx_tags_name",
            on: "tags",
            columns: ["name"]
        )

        // Create video_tags junction table
        try db.create(table: "video_tags") { t in
            t.column("id", .text).primaryKey()
            t.column("video_file_id", .text).notNull()
                .references("video_files", column: "file_id", onDelete: .cascade)
            t.column("tag_id", .text).notNull()
                .references("tags", column: "id", onDelete: .cascade)
            t.column("created_at", .double).notNull()

            t.uniqueKey(["video_file_id", "tag_id"])
        }

        try db.create(
            index: "idx_video_tags_video_file_id",
            on: "video_tags",
            columns: ["video_file_id"]
        )

        try db.create(
            index: "idx_video_tags_tag_id",
            on: "video_tags",
            columns: ["tag_id"]
        )
    }
}

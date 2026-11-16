import Foundation
import GRDB

nonisolated enum V4_CreateThumbnailsTable: Sendable {
    static let migrationIdentifier = "v4_create_thumbnails"

    static func migrate(_ db: Database) throws {
        // Create thumbnails table with BLOB storage for image data
        try db.create(table: "thumbnails") { t in
            t.column("id", .text).primaryKey()
            t.column("file_id", .text).notNull().unique()
            t.column("image_data", .blob).notNull()
            t.column("created_at", .double).notNull()
            t.column("updated_at", .double).notNull()
        }

        // Create index on file_id for efficient lookup
        try db.create(
            index: "idx_thumbnails_file_id",
            on: "thumbnails",
            columns: ["file_id"]
        )
    }
}

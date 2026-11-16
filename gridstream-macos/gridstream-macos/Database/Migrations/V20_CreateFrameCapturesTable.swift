import Foundation
import GRDB

nonisolated enum V20_CreateFrameCapturesTable: Sendable {
    static let migrationIdentifier = "v20_create_frame_captures"

    static func migrate(_ db: Database) throws {
        try db.create(table: "frame_captures") { t in
            t.column("id", .text).primaryKey()
            t.column("file_id", .text).notNull()
            t.column("timestamp", .double).notNull()
            t.column("image_data", .blob).notNull()
            t.column("width", .integer).notNull()
            t.column("height", .integer).notNull()
            t.column("file_size", .integer).notNull()
            t.column("created_at", .double).notNull()
        }

        try db.create(
            index: "idx_frame_captures_file_id",
            on: "frame_captures",
            columns: ["file_id"]
        )

        try db.create(
            index: "idx_frame_captures_created_at",
            on: "frame_captures",
            columns: ["created_at"]
        )
    }
}

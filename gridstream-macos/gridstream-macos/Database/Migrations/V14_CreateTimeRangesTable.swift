import Foundation
import GRDB

nonisolated enum V14_CreateTimeRangesTable: Sendable {
    static let migrationIdentifier = "v14_create_time_ranges"

    static func migrate(_ db: Database) throws {
        try db.create(table: "time_ranges") { t in
            t.column("id", .text).primaryKey()
            t.column("video_file_id", .text).notNull()
            t.column("start_time", .double).notNull()
            t.column("end_time", .double).notNull()
            t.column("label", .text)
            t.column("created_at", .double).notNull()
            t.column("updated_at", .double).notNull()
        }

        try db.create(
            index: "idx_time_ranges_video_file_id",
            on: "time_ranges",
            columns: ["video_file_id"]
        )
    }
}

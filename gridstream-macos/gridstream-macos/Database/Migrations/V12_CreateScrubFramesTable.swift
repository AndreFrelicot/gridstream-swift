import Foundation
import GRDB

nonisolated enum V12_CreateScrubFramesTable: Sendable {
    static let migrationIdentifier = "v12_create_scrub_frames"

    static func migrate(_ db: Database) throws {
        try db.create(table: "scrub_frames") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("file_id", .text).notNull()
            t.column("timestamp", .double).notNull()
            t.column("frame_data", .blob).notNull()
            t.column("quality", .integer).defaults(to: 85)
            t.column("created_at", .double).notNull()
            t.uniqueKey(["file_id", "timestamp"])
        }

        try db.create(
            index: "idx_scrub_frames_file_id",
            on: "scrub_frames",
            columns: ["file_id"]
        )

        try db.create(
            index: "idx_scrub_frames_file_timestamp",
            on: "scrub_frames",
            columns: ["file_id", "timestamp"]
        )
    }
}

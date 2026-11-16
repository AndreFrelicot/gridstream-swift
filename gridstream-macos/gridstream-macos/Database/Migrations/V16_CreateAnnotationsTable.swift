import Foundation
import GRDB

nonisolated enum V16_CreateAnnotationsTable: Sendable {
    static let migrationIdentifier = "v16_create_annotations"

    static func migrate(_ db: Database) throws {
        try db.create(table: "video_annotations") { t in
            t.column("id", .text).primaryKey()
            t.column("video_file_id", .text).notNull()
            t.column("frame_time", .double).notNull()
            t.column("frame_rate", .double).notNull()
            t.column("strokes_json", .text).notNull()
            t.column("created_at", .double).notNull()
            t.column("updated_at", .double).notNull()
            t.uniqueKey(["video_file_id", "frame_time"])
        }

        try db.create(
            index: "idx_video_annotations_video_file_id",
            on: "video_annotations",
            columns: ["video_file_id"]
        )
    }
}

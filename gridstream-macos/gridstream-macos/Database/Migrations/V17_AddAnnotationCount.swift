import Foundation
import GRDB

nonisolated enum V17_AddAnnotationCount: Sendable {
    static let migrationIdentifier = "v17_add_annotation_count"

    static func migrate(_ db: Database) throws {
        try db.alter(table: "video_files") { t in
            t.add(column: "annotation_count", .integer).defaults(to: 0)
        }

        // Backfill existing annotation counts
        try db.execute(sql: """
            UPDATE video_files SET annotation_count = (
                SELECT COUNT(*) FROM video_annotations
                WHERE video_annotations.video_file_id = video_files.file_id
            )
            """)
    }
}

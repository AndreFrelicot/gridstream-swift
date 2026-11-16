import Foundation
import GRDB

nonisolated enum V24_AddScrubFrameCount: Sendable {
    static let migrationIdentifier = "v24_add_scrub_frame_count"

    static func migrate(_ db: Database) throws {
        try db.alter(table: "video_files") { t in
            t.add(column: "scrub_frame_count", .integer).defaults(to: 0)
        }

        // One-time backfill (expensive on a large DB — runs once).
        try db.execute(sql: """
            UPDATE video_files SET scrub_frame_count = (
                SELECT COUNT(*) FROM scrub_frames
                WHERE scrub_frames.file_id = video_files.file_id
            )
            """)
    }
}

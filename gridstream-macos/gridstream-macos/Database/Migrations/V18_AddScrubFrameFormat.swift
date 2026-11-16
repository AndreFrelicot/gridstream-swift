import Foundation
import GRDB

nonisolated enum V18_AddScrubFrameFormat: Sendable {
    static let migrationIdentifier = "v18_add_scrub_frame_format"

    static func migrate(_ db: Database) throws {
        // Add format column: "jpeg" or "heic". Existing rows default to "heic"
        // since all frames before this migration were generated as HEIC.
        try db.alter(table: "scrub_frames") { t in
            t.add(column: "format", .text).notNull().defaults(to: "heic")
        }

        // Index for fast HEIC frame lookups during conversion
        try db.create(
            index: "idx_scrub_frames_format",
            on: "scrub_frames",
            columns: ["format"]
        )
    }
}

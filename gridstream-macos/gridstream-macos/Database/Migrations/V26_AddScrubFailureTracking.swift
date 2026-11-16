import Foundation
import GRDB

nonisolated enum V26_AddScrubFailureTracking: Sendable {
    static let migrationIdentifier = "v26_add_scrub_failure_tracking"

    static func migrate(_ db: Database) throws {
        try db.alter(table: "video_files") { t in
            t.add(column: "scrub_attempt_count", .integer).defaults(to: 0)
            t.add(column: "scrub_failed", .integer).defaults(to: 0)
            t.add(column: "scrub_last_error", .text)
            t.add(column: "scrub_last_attempt_at", .double)
        }
        // Partial index so the idle-pool fetch (WHERE scrub_failed = 0) and the
        // blocked-list fetch (WHERE scrub_failed = 1) stay cheap.
        try db.create(index: "idx_video_files_scrub_failed", on: "video_files",
                      columns: ["scrub_failed"])
    }
}

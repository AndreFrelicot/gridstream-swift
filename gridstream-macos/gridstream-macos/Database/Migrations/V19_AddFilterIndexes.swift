import Foundation
import GRDB

nonisolated enum V19_AddFilterIndexes: Sendable {
    static let migrationIdentifier = "v19_add_filter_indexes"

    static func migrate(_ db: Database) throws {
        // Indexes for columns used in filter queries but not yet indexed
        try db.create(index: "idx_video_files_filename", on: "video_files", columns: ["filename"])
        try db.create(index: "idx_video_files_file_size", on: "video_files", columns: ["file_size"])
        try db.create(index: "idx_video_files_created_at", on: "video_files", columns: ["created_at"])
        try db.create(index: "idx_video_files_last_modified", on: "video_files", columns: ["last_modified"])
        try db.create(index: "idx_video_files_annotation_count", on: "video_files", columns: ["annotation_count"])
    }
}

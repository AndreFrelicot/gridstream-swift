import Foundation
import GRDB

nonisolated enum V1_CreateVideoFilesTable: Sendable {
    static let migrationIdentifier = "v1_create_video_files"

    static func migrate(_ db: Database) throws {
        try db.create(table: "video_files") { t in
            t.column("id", .text).primaryKey()
            t.column("file_id", .text).notNull().unique()
            t.column("path", .text).notNull()
            t.column("source_directory_id", .text).notNull()
            t.column("filename", .text).notNull()
            t.column("file_size", .integer).notNull()
            t.column("duration", .double).notNull()
            t.column("width", .integer).notNull()
            t.column("height", .integer).notNull()
            t.column("codec", .text).notNull()
            t.column("last_modified", .double).notNull()
            t.column("created_at", .double).notNull()
            t.column("updated_at", .double).notNull()
        }

        try db.create(
            index: "idx_video_files_file_id",
            on: "video_files",
            columns: ["file_id"]
        )

        try db.create(
            index: "idx_video_files_source_directory_id",
            on: "video_files",
            columns: ["source_directory_id"]
        )
    }
}

import Foundation
import GRDB

nonisolated enum V13_CreateSourceDirectoriesTable: Sendable {
    static let migrationIdentifier = "v13_create_source_directories"

    static func migrate(_ db: Database) throws {
        try db.create(table: "source_directories") { t in
            t.column("id", .text).primaryKey()
            t.column("path", .text).notNull()
            t.column("is_enabled", .boolean).notNull().defaults(to: true)
            t.column("last_scanned", .double)
            t.column("bookmark_data", .blob)
            t.column("created_at", .double).notNull()
            t.column("updated_at", .double).notNull()
        }

        try db.create(
            index: "idx_source_directories_path",
            on: "source_directories",
            columns: ["path"],
            unique: true
        )
    }
}

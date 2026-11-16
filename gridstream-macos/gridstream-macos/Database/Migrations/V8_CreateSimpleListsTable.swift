import Foundation
import GRDB

nonisolated enum V8_CreateSimpleListsTable: Sendable {
    static let migrationIdentifier = "v8_create_simple_lists"

    static func migrate(_ db: Database) throws {
        try db.create(table: "simple_lists") { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull().unique()
            t.column("sort_order", .text).notNull().defaults(to: "filename")
            t.column("created_at", .double).notNull()
            t.column("updated_at", .double).notNull()
        }

        try db.create(
            index: "idx_simple_lists_name",
            on: "simple_lists",
            columns: ["name"]
        )
    }
}

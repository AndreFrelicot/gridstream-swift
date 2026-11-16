import Foundation
import GRDB

nonisolated enum V7_CreateSmartListsTable: Sendable {
    static let migrationIdentifier = "v7_create_smart_lists"

    static func migrate(_ db: Database) throws {
        try db.create(table: "smart_lists") { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull().unique()
            t.column("criteria", .text).notNull()
            t.column("created_at", .double).notNull()
            t.column("updated_at", .double).notNull()
        }

        try db.create(
            index: "idx_smart_lists_name",
            on: "smart_lists",
            columns: ["name"]
        )
    }
}

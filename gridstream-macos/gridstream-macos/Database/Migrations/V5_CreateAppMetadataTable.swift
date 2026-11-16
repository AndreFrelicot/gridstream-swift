import Foundation
import GRDB

nonisolated enum V5_CreateAppMetadataTable: Sendable {
    static let migrationIdentifier = "v5_create_app_metadata"

    static func migrate(_ db: Database) throws {
        // Create app_metadata table for storing application-wide settings
        // Using key-value pairs for flexibility
        try db.create(table: "app_metadata") { t in
            t.column("key", .text).primaryKey()
            t.column("value", .text).notNull()
            t.column("updated_at", .double).notNull()
        }

        // Initialize catalog_version with current timestamp
        let now = Date().timeIntervalSince1970
        try db.execute(
            sql: "INSERT INTO app_metadata (key, value, updated_at) VALUES (?, ?, ?)",
            arguments: ["catalog_version", String(Int64(now * 1000)), now]
        )
    }
}

import Foundation
import GridStreamAPI
import OSLog
import GRDB

/// Re-encodes stored smart list criteria in canonical form (ISO 8601 dates
/// without fractional seconds, UUID condition ids). Best effort: rows that
/// cannot be decoded are left untouched and logged.
nonisolated enum V28_NormalizeSmartListCriteria: Sendable {
    static let migrationIdentifier = "v28_normalize_smart_list_criteria"

    private static let logger = Logger(subsystem: "com.gridstream.macos", category: "Migrations")

    static func migrate(_ db: Database) throws {
        let rows = try Row.fetchAll(db, sql: "SELECT id, name, criteria FROM smart_lists")
        for row in rows {
            let id: UUID = row["id"]
            let name: String = row["name"]
            let criteria: String = row["criteria"]
            do {
                let canonical = try SmartListCriteria.decode(json: criteria).canonicalJSON()
                if canonical != criteria {
                    try db.execute(
                        sql: "UPDATE smart_lists SET criteria = ? WHERE id = ?",
                        arguments: [canonical, id]
                    )
                }
            } catch {
                logger.warning("Smart list '\(name, privacy: .public)' has undecodable criteria, left unchanged: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

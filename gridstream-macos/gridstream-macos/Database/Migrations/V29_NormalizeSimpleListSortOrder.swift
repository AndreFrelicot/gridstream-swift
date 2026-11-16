import Foundation
import GRDB
import GridStreamAPI

/// Rewrites simple list `sort_order` to the canonical snake_case values;
/// camelCase aliases are mapped and unknown values become `filename`.
nonisolated enum V29_NormalizeSimpleListSortOrder: Sendable {
    static let migrationIdentifier = "v29_normalize_simple_list_sort_order"

    static func migrate(_ db: Database) throws {
        let rows = try Row.fetchAll(db, sql: "SELECT id, sort_order FROM simple_lists")
        for row in rows {
            let id: UUID = row["id"]
            let sortOrder: String = row["sort_order"]
            let canonical = SimpleListSortOrder.canonical(sortOrder) ?? SimpleListSortOrder.defaultValue
            if canonical != sortOrder {
                try db.execute(
                    sql: "UPDATE simple_lists SET sort_order = ? WHERE id = ?",
                    arguments: [canonical, id]
                )
            }
        }
    }
}

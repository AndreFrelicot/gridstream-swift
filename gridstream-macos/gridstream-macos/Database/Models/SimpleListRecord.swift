import Foundation
import GRDB

nonisolated struct SimpleListRecord: Sendable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "simple_lists"

    var id: UUID
    var name: String
    var sortOrder: String
    var createdAt: Double
    var updatedAt: Double

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID = UUID(),
        name: String,
        sortOrder: String = "filename",
        createdAt: Double = Date().timeIntervalSince1970,
        updatedAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.name = name.lowercased()
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(row: Row) throws {
        id = row["id"]
        name = row["name"]
        sortOrder = row["sort_order"]
        createdAt = row["created_at"]
        updatedAt = row["updated_at"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["name"] = name
        container["sort_order"] = sortOrder
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
    }

    mutating func touch() {
        updatedAt = Date().timeIntervalSince1970
    }
}

// MARK: - Query Helpers

nonisolated extension SimpleListRecord {
    static func findByName(_ name: String, in db: Database) -> SimpleListRecord? {
        try? SimpleListRecord
            .filter(Column("name") == name.lowercased())
            .fetchOne(db)
    }

    static func findById(_ id: UUID, in db: Database) -> SimpleListRecord? {
        try? SimpleListRecord
            .filter(Column("id") == id)
            .fetchOne(db)
    }

    static func findAll(in db: Database) -> [SimpleListRecord] {
        (try? SimpleListRecord.fetchAll(db)) ?? []
    }

    static func countAll(in db: Database) -> Int {
        (try? SimpleListRecord.fetchCount(db)) ?? 0
    }
}

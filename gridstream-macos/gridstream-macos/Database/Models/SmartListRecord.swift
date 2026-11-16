import Foundation
import GRDB
import GridStreamAPI

nonisolated struct SmartListRecord: Sendable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "smart_lists"

    var id: UUID
    var name: String
    var criteria: String
    var createdAt: Double
    var updatedAt: Double

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case criteria
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID = UUID(),
        name: String,
        criteria: String,
        createdAt: Double = Date().timeIntervalSince1970,
        updatedAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.name = name.lowercased()
        self.criteria = criteria
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(row: Row) throws {
        id = row["id"]
        name = row["name"]
        criteria = row["criteria"]
        createdAt = row["created_at"]
        updatedAt = row["updated_at"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["name"] = name
        container["criteria"] = criteria
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
    }

    mutating func touch() {
        updatedAt = Date().timeIntervalSince1970
    }
}

// MARK: - Query Helpers

nonisolated extension SmartListRecord {
    static func findByName(_ name: String, in db: Database) -> SmartListRecord? {
        try? SmartListRecord
            .filter(Column("name") == name.lowercased())
            .fetchOne(db)
    }

    static func findById(_ id: UUID, in db: Database) -> SmartListRecord? {
        try? SmartListRecord
            .filter(Column("id") == id)
            .fetchOne(db)
    }

    static func findAll(in db: Database) -> [SmartListRecord] {
        (try? SmartListRecord.fetchAll(db)) ?? []
    }

    static func countAll(in db: Database) -> Int {
        (try? SmartListRecord.fetchCount(db)) ?? 0
    }
}

// MARK: - Criteria maintenance

nonisolated extension SmartListRecord {
    /// Removes `tagId` from every smart list's criteria (contract §2), storing the
    /// result in canonical form. Lists whose criteria cannot be decoded are left
    /// untouched. Returns the number of lists changed.
    @discardableResult
    static func removeTagFromCriteria(_ tagId: UUID, in db: Database) throws -> Int {
        let now = Date().timeIntervalSince1970
        var changed = 0
        for smartList in try SmartListRecord.fetchAll(db)
        where smartList.criteria.range(of: tagId.uuidString, options: .caseInsensitive) != nil {
            guard let criteria = try? SmartListCriteria.decode(json: smartList.criteria),
                  let updated = criteria.removingTag(tagId) else {
                continue
            }
            try db.execute(
                sql: "UPDATE smart_lists SET criteria = ?, updated_at = ? WHERE id = ?",
                arguments: [try updated.canonicalJSON(), now, smartList.id]
            )
            changed += 1
        }
        return changed
    }
}

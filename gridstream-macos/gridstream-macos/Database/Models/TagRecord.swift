import Foundation
import OSLog
import GRDB

nonisolated struct TagRecord: Sendable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "tags"

    var id: UUID
    var name: String
    var color: String
    var description: String?
    var ratingEnabled: Bool
    var createdAt: Double
    var updatedAt: Double

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case color
        case description
        case ratingEnabled = "rating_enabled"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID = UUID(),
        name: String,
        color: String,
        description: String? = nil,
        ratingEnabled: Bool = false,
        createdAt: Double = Date().timeIntervalSince1970,
        updatedAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.name = name.lowercased()
        self.color = color
        self.description = description
        self.ratingEnabled = ratingEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(row: Row) throws {
        id = row["id"]
        name = row["name"]
        color = row["color"]
        description = row["description"]
        ratingEnabled = (row["rating_enabled"] as Int?) == 1
        createdAt = row["created_at"]
        updatedAt = row["updated_at"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["name"] = name
        container["color"] = color
        container["description"] = description
        container["rating_enabled"] = ratingEnabled ? 1 : 0
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
    }

    mutating func touch() {
        updatedAt = Date().timeIntervalSince1970
    }
}

// MARK: - Query Helpers

nonisolated extension TagRecord {
    private static let logger = Logger(subsystem: "com.gridstream.macos", category: "TagRecord")

    static func findByName(_ name: String, in db: Database) -> TagRecord? {
        try? TagRecord
            .filter(Column("name") == name.lowercased())
            .fetchOne(db)
    }

    static func findById(_ id: UUID, in db: Database) -> TagRecord? {
        try? TagRecord
            .filter(Column("id") == id)
            .fetchOne(db)
    }

    static func findAll(in db: Database) -> [TagRecord] {
        do {
            return try TagRecord.fetchAll(db)
        } catch {
            logger.error("findAll failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    static func countAll(in db: Database) -> Int {
        (try? TagRecord.fetchCount(db)) ?? 0
    }

    static func countVideos(for tagId: UUID, in db: Database) -> Int {
        let sql = "SELECT COUNT(*) FROM video_tags WHERE tag_id = ?"
        return (try? Int.fetchOne(db, sql: sql, arguments: [tagId])) ?? 0
    }
}

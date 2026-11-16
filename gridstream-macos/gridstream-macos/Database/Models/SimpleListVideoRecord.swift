import Foundation
import GRDB

nonisolated struct SimpleListVideoRecord: Sendable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "simple_list_videos"

    var id: UUID
    var simpleListId: UUID
    var videoFileId: String
    var position: Int
    var addedAt: Double

    enum CodingKeys: String, CodingKey {
        case id
        case simpleListId = "simple_list_id"
        case videoFileId = "video_file_id"
        case position
        case addedAt = "added_at"
    }

    init(
        id: UUID = UUID(),
        simpleListId: UUID,
        videoFileId: String,
        position: Int = 0,
        addedAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.simpleListId = simpleListId
        self.videoFileId = videoFileId
        self.position = position
        self.addedAt = addedAt
    }

    init(row: Row) throws {
        id = row["id"]
        simpleListId = row["simple_list_id"]
        videoFileId = row["video_file_id"]
        position = row["position"]
        addedAt = row["added_at"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["simple_list_id"] = simpleListId
        container["video_file_id"] = videoFileId
        container["position"] = position
        container["added_at"] = addedAt
    }
}

// MARK: - Query Helpers

nonisolated extension SimpleListVideoRecord {
    static func findByListId(_ listId: UUID, in db: Database) -> [SimpleListVideoRecord] {
        (try? SimpleListVideoRecord
            .filter(Column("simple_list_id") == listId)
            .order(Column("position"))
            .fetchAll(db)) ?? []
    }

    static func findByVideoFileId(_ videoFileId: String, in db: Database) -> [SimpleListVideoRecord] {
        (try? SimpleListVideoRecord
            .filter(Column("video_file_id") == videoFileId)
            .fetchAll(db)) ?? []
    }

    static func findByListIdAndVideoFileId(_ listId: UUID, _ videoFileId: String, in db: Database) -> SimpleListVideoRecord? {
        try? SimpleListVideoRecord
            .filter(Column("simple_list_id") == listId && Column("video_file_id") == videoFileId)
            .fetchOne(db)
    }

    static func deleteByListId(_ listId: UUID, in db: Database) throws {
        _ = try SimpleListVideoRecord
            .filter(Column("simple_list_id") == listId)
            .deleteAll(db)
    }

    static func countByListId(_ listId: UUID, in db: Database) -> Int {
        (try? SimpleListVideoRecord
            .filter(Column("simple_list_id") == listId)
            .fetchCount(db)) ?? 0
    }

    static func getMaxPosition(forListId listId: UUID, in db: Database) -> Int {
        let records = findByListId(listId, in: db)
        return records.map(\.position).max() ?? -1
    }
}

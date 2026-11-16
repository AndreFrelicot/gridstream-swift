import Foundation
import GRDB

nonisolated struct ThumbnailRecord: Sendable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "thumbnails"

    var id: UUID
    var fileId: String
    var imageData: Data
    var createdAt: Double
    var updatedAt: Double

    enum CodingKeys: String, CodingKey {
        case id
        case fileId = "file_id"
        case imageData = "image_data"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID = UUID(),
        fileId: String,
        imageData: Data,
        createdAt: Double = Date().timeIntervalSince1970,
        updatedAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.fileId = fileId
        self.imageData = imageData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(row: Row) throws {
        id = row["id"]
        fileId = row["file_id"]
        imageData = row["image_data"]
        createdAt = row["created_at"]
        updatedAt = row["updated_at"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["file_id"] = fileId
        container["image_data"] = imageData
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
    }

    mutating func touch() {
        updatedAt = Date().timeIntervalSince1970
    }
}

// MARK: - Query Helpers

nonisolated extension ThumbnailRecord {
    static func findByFileId(_ fileId: String, in db: Database) throws -> ThumbnailRecord? {
        try ThumbnailRecord
            .filter(Column("file_id") == fileId)
            .fetchOne(db)
    }

    static func exists(forFileId fileId: String, in db: Database) throws -> Bool {
        let count = try ThumbnailRecord
            .filter(Column("file_id") == fileId)
            .fetchCount(db)
        return count > 0
    }

    static func deleteByFileId(_ fileId: String, in db: Database) throws -> Bool {
        let count = try ThumbnailRecord
            .filter(Column("file_id") == fileId)
            .deleteAll(db)
        return count > 0
    }
}

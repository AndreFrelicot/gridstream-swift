import Foundation
import GRDB

nonisolated struct FrameCaptureRecord: Sendable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "frame_captures"

    var id: String
    var fileId: String
    var timestamp: Double
    var imageData: Data
    var width: Int
    var height: Int
    var fileSize: Int
    var createdAt: Double

    enum CodingKeys: String, CodingKey {
        case id
        case fileId = "file_id"
        case timestamp
        case imageData = "image_data"
        case width
        case height
        case fileSize = "file_size"
        case createdAt = "created_at"
    }

    init(
        id: String = UUID().uuidString,
        fileId: String,
        timestamp: Double,
        imageData: Data,
        width: Int,
        height: Int,
        fileSize: Int,
        createdAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.fileId = fileId
        self.timestamp = timestamp
        self.imageData = imageData
        self.width = width
        self.height = height
        self.fileSize = fileSize
        self.createdAt = createdAt
    }

    /// Columns selected for list queries (excludes image_data blob)
    static let metadataColumns = [
        Column("id"), Column("file_id"), Column("timestamp"),
        Column("width"), Column("height"), Column("file_size"), Column("created_at")
    ]

    init(row: Row) throws {
        id = row["id"]
        fileId = row["file_id"]
        timestamp = row["timestamp"]
        // Support lightweight queries that exclude image_data
        let optionalImageData: Data? = row["image_data"]
        imageData = optionalImageData ?? Data()
        width = row["width"]
        height = row["height"]
        fileSize = row["file_size"]
        createdAt = row["created_at"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["file_id"] = fileId
        container["timestamp"] = timestamp
        container["image_data"] = imageData
        container["width"] = width
        container["height"] = height
        container["file_size"] = fileSize
        container["created_at"] = createdAt
    }
}

// MARK: - Query Helpers

nonisolated extension FrameCaptureRecord {
    static func findByFileId(_ fileId: String, in db: Database) throws -> [FrameCaptureRecord] {
        try FrameCaptureRecord
            .select(metadataColumns)
            .filter(Column("file_id") == fileId)
            .order(Column("created_at").desc)
            .fetchAll(db)
    }

    static func findById(_ id: String, in db: Database) throws -> FrameCaptureRecord? {
        try FrameCaptureRecord
            .filter(Column("id") == id)
            .fetchOne(db)
    }

    static func count(forFileId fileId: String, in db: Database) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM frame_captures WHERE file_id = ?",
            arguments: [fileId]
        ) ?? 0
    }

    static func deleteById(_ id: String, in db: Database) throws -> Bool {
        let changes = try FrameCaptureRecord
            .filter(Column("id") == id)
            .deleteAll(db)
        return changes > 0
    }
}

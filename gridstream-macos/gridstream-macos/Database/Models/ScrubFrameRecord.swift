import Foundation
import GRDB

nonisolated struct ScrubFrameRecord: Sendable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "scrub_frames"

    var id: Int64?
    var fileId: String
    var timestamp: Double
    var frameData: Data
    var quality: Int
    var createdAt: Double
    var format: String

    enum CodingKeys: String, CodingKey {
        case id
        case fileId = "file_id"
        case timestamp
        case frameData = "frame_data"
        case quality
        case createdAt = "created_at"
        case format
    }

    init(
        id: Int64? = nil,
        fileId: String,
        timestamp: Double,
        frameData: Data,
        quality: Int = 85,
        createdAt: Double = Date().timeIntervalSince1970,
        format: String = "jpeg"
    ) {
        self.id = id
        self.fileId = fileId
        self.timestamp = timestamp
        self.frameData = frameData
        self.quality = quality
        self.createdAt = createdAt
        self.format = format
    }

    init(row: Row) throws {
        id = row["id"]
        fileId = row["file_id"]
        timestamp = row["timestamp"]
        frameData = row["frame_data"]
        quality = row["quality"]
        createdAt = row["created_at"]
        format = row["format"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["file_id"] = fileId
        container["timestamp"] = timestamp
        container["frame_data"] = frameData
        container["quality"] = quality
        container["created_at"] = createdAt
        container["format"] = format
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Query Helpers

nonisolated extension ScrubFrameRecord {
    static func find(fileId: String, timestamp: Double, in db: Database) throws -> ScrubFrameRecord? {
        try ScrubFrameRecord
            .filter(Column("file_id") == fileId && Column("timestamp") == timestamp)
            .fetchOne(db)
    }

    static func timestamps(forFileId fileId: String, in db: Database) throws -> [Double] {
        try ScrubFrameRecord
            .filter(Column("file_id") == fileId)
            .select(Column("timestamp"))
            .order(Column("timestamp"))
            .asRequest(of: Double.self)
            .fetchAll(db)
    }

    static func deleteByFileId(_ fileId: String, in db: Database) throws -> Int {
        try ScrubFrameRecord
            .filter(Column("file_id") == fileId)
            .deleteAll(db)
    }

    static func count(forFileId fileId: String, in db: Database) throws -> Int {
        try ScrubFrameRecord
            .filter(Column("file_id") == fileId)
            .fetchCount(db)
    }

    static func deleteAll(in db: Database) throws -> Int {
        try ScrubFrameRecord.deleteAll(db)
    }
}

import Foundation
import GRDB

nonisolated struct TimeRangeRecord: Sendable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "time_ranges"

    var id: UUID
    var videoFileId: String
    var startTime: Double
    var endTime: Double
    var label: String?
    var createdAt: Double
    var updatedAt: Double

    enum CodingKeys: String, CodingKey {
        case id
        case videoFileId = "video_file_id"
        case startTime = "start_time"
        case endTime = "end_time"
        case label
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID = UUID(),
        videoFileId: String,
        startTime: Double,
        endTime: Double,
        label: String? = nil,
        createdAt: Double = Date().timeIntervalSince1970,
        updatedAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.videoFileId = videoFileId
        self.startTime = startTime
        self.endTime = endTime
        self.label = label
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(row: Row) throws {
        id = row["id"]
        videoFileId = row["video_file_id"]
        startTime = row["start_time"]
        endTime = row["end_time"]
        label = row["label"]
        createdAt = row["created_at"]
        updatedAt = row["updated_at"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["video_file_id"] = videoFileId
        container["start_time"] = startTime
        container["end_time"] = endTime
        container["label"] = label
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
    }

    mutating func touch() {
        updatedAt = Date().timeIntervalSince1970
    }
}

// MARK: - Query Helpers

nonisolated extension TimeRangeRecord {
    static func findByVideoFileId(_ videoFileId: String, in db: Database) -> [TimeRangeRecord] {
        (try? TimeRangeRecord
            .filter(Column("video_file_id") == videoFileId)
            .order(Column("start_time"))
            .fetchAll(db)) ?? []
    }

    static func findById(_ id: UUID, in db: Database) -> TimeRangeRecord? {
        try? TimeRangeRecord
            .filter(Column("id") == id)
            .fetchOne(db)
    }

    static func deleteByVideoFileId(_ videoFileId: String, in db: Database) throws {
        _ = try TimeRangeRecord
            .filter(Column("video_file_id") == videoFileId)
            .deleteAll(db)
    }
}

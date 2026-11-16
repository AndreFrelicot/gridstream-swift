import Foundation
import GRDB

nonisolated struct AnnotationRecord: Sendable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "video_annotations"

    var id: UUID
    var videoFileId: String
    var frameTime: Double
    var frameRate: Double
    var strokesJSON: String
    var text: String?
    var createdAt: Double
    var updatedAt: Double

    enum CodingKeys: String, CodingKey {
        case id
        case videoFileId = "video_file_id"
        case frameTime = "frame_time"
        case frameRate = "frame_rate"
        case strokesJSON = "strokes_json"
        case text
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID = UUID(),
        videoFileId: String,
        frameTime: Double,
        frameRate: Double,
        strokesJSON: String,
        text: String? = nil,
        createdAt: Double = Date().timeIntervalSince1970,
        updatedAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.videoFileId = videoFileId
        self.frameTime = frameTime
        self.frameRate = frameRate
        self.strokesJSON = strokesJSON
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(row: Row) throws {
        id = row["id"]
        videoFileId = row["video_file_id"]
        frameTime = row["frame_time"]
        frameRate = row["frame_rate"]
        strokesJSON = row["strokes_json"]
        text = row["text"]
        createdAt = row["created_at"]
        updatedAt = row["updated_at"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["video_file_id"] = videoFileId
        container["frame_time"] = frameTime
        container["frame_rate"] = frameRate
        container["strokes_json"] = strokesJSON
        container["text"] = text
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
    }

    mutating func touch() {
        updatedAt = Date().timeIntervalSince1970
    }
}

// MARK: - Query Helpers

nonisolated extension AnnotationRecord {
    static func findByVideoFileId(_ videoFileId: String, in db: Database) throws -> [AnnotationRecord] {
        try AnnotationRecord
            .filter(Column("video_file_id") == videoFileId)
            .order(Column("frame_time"))
            .fetchAll(db)
    }

    /// Throws on database errors: callers must not treat a failed read as
    /// "not found" (an upsert would then insert a duplicate).
    static func findByVideoFileIdAndFrameTime(_ videoFileId: String, frameTime: Double, in db: Database) throws -> AnnotationRecord? {
        try AnnotationRecord
            .filter(Column("video_file_id") == videoFileId && Column("frame_time") == frameTime)
            .fetchOne(db)
    }

    static func findById(_ id: UUID, in db: Database) throws -> AnnotationRecord? {
        try AnnotationRecord
            .filter(Column("id") == id)
            .fetchOne(db)
    }

    static func deleteByVideoFileId(_ videoFileId: String, in db: Database) throws {
        _ = try AnnotationRecord
            .filter(Column("video_file_id") == videoFileId)
            .deleteAll(db)
    }

    static func listFrameTimes(forVideoFileId videoFileId: String, in db: Database) throws -> [Double] {
        try Double.fetchAll(
            db,
            sql: "SELECT frame_time FROM video_annotations WHERE video_file_id = ? ORDER BY frame_time",
            arguments: [videoFileId]
        )
    }
}

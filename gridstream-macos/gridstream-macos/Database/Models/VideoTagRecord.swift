import Foundation
import OSLog
import GRDB

nonisolated struct VideoTagRecord: Sendable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "video_tags"

    var id: UUID
    var videoFileId: String
    var tagId: UUID
    var rating: Int
    var createdAt: Double

    enum CodingKeys: String, CodingKey {
        case id
        case videoFileId = "video_file_id"
        case tagId = "tag_id"
        case rating
        case createdAt = "created_at"
    }

    init(
        id: UUID = UUID(),
        videoFileId: String,
        tagId: UUID,
        rating: Int = 0,
        createdAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.videoFileId = videoFileId
        self.tagId = tagId
        self.rating = rating
        self.createdAt = createdAt
    }

    init(row: Row) throws {
        id = row["id"]
        videoFileId = row["video_file_id"]
        tagId = row["tag_id"]
        rating = row["rating"] ?? 0
        createdAt = row["created_at"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["video_file_id"] = videoFileId
        container["tag_id"] = tagId
        container["rating"] = rating
        container["created_at"] = createdAt
    }
}

// MARK: - Query Helpers

nonisolated extension VideoTagRecord {
    private static let logger = Logger(subsystem: "com.gridstream.macos", category: "VideoTagRecord")

    static func findByVideoFileId(_ videoFileId: String, in db: Database) -> [VideoTagRecord] {
        do {
            return try VideoTagRecord
                .filter(Column("video_file_id") == videoFileId)
                .fetchAll(db)
        } catch {
            logger.error("findByVideoFileId failed for \(videoFileId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    static func findByTagId(_ tagId: UUID, in db: Database) -> [VideoTagRecord] {
        do {
            return try VideoTagRecord
                .filter(Column("tag_id") == tagId)
                .fetchAll(db)
        } catch {
            logger.error("findByTagId failed for \(tagId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    static func findByVideoFileIdAndTagId(_ videoFileId: String, _ tagId: UUID, in db: Database) -> VideoTagRecord? {
        try? VideoTagRecord
            .filter(Column("video_file_id") == videoFileId)
            .filter(Column("tag_id") == tagId)
            .fetchOne(db)
    }

    @discardableResult
    static func deleteByVideoFileIdAndTagId(_ videoFileId: String, _ tagId: UUID, in db: Database) throws -> Int {
        try VideoTagRecord
            .filter(Column("video_file_id") == videoFileId)
            .filter(Column("tag_id") == tagId)
            .deleteAll(db)
    }

    static func findByTagIdWithRating(_ tagId: UUID, minRating: Int?, maxRating: Int?, in db: Database) throws -> [VideoTagRecord] {
        var request = VideoTagRecord.filter(Column("tag_id") == tagId)

        if let min = minRating {
            request = request.filter(Column("rating") >= min)
        }

        if let max = maxRating {
            request = request.filter(Column("rating") <= max)
        }

        return try request.fetchAll(db)
    }

    static func findByVideoFileIdWithRatings(_ videoFileId: String, in db: Database) -> [VideoTagRecord] {
        do {
            return try VideoTagRecord
                .filter(Column("video_file_id") == videoFileId)
                .fetchAll(db)
        } catch {
            logger.error("findByVideoFileIdWithRatings failed for \(videoFileId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

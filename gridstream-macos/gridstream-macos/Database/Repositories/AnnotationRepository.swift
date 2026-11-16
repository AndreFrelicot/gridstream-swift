import Foundation
import GRDB

/// Persistence of frame annotations (`video_annotations`) and of the
/// denormalized `video_files.annotation_count`.
nonisolated struct AnnotationRepository: Sendable {
    let database: DatabaseManager

    func annotations(ofVideo fileId: String) async throws -> [AnnotationRecord] {
        try await database.read { db in
            try AnnotationRecord.findByVideoFileId(fileId, in: db)
        }
    }

    func frameTimes(ofVideo fileId: String) async throws -> [Double] {
        try await database.read { db in
            try AnnotationRecord.listFrameTimes(forVideoFileId: fileId, in: db)
        }
    }

    /// Creates or replaces the annotation of `fileId` at `frameTime`.
    /// Returns the stored record and whether it was created.
    func upsert(
        fileId: String,
        frameTime: Double,
        frameRate: Double,
        strokesJSON: String,
        text: String?
    ) async throws -> (record: AnnotationRecord, created: Bool) {
        try await database.writeCatalog { db in
            guard try VideoFileRecord.findByFileId(fileId, in: db) != nil else {
                throw RepositoryError.notFound("Video not found")
            }

            let result: (record: AnnotationRecord, created: Bool)
            if var existing = try AnnotationRecord.findByVideoFileIdAndFrameTime(fileId, frameTime: frameTime, in: db) {
                existing.frameRate = frameRate
                existing.strokesJSON = strokesJSON
                existing.text = text
                existing.touch()
                try existing.update(db)
                result = (existing, false)
            } else {
                let record = AnnotationRecord(
                    videoFileId: fileId,
                    frameTime: frameTime,
                    frameRate: frameRate,
                    strokesJSON: strokesJSON,
                    text: text
                )
                try record.insert(db)
                result = (record, true)
            }

            try Self.syncAnnotationCount(fileId, in: db)
            return .changed(result)
        }
    }

    /// Deletes an annotation of `fileId` (404 when it belongs to another video).
    func delete(id: UUID, ofVideo fileId: String) async throws {
        try await database.writeCatalog { db in
            guard let record = try AnnotationRecord.findById(id, in: db), record.videoFileId == fileId else {
                throw RepositoryError.notFound("Annotation not found for this video")
            }

            let deletedCount = try AnnotationRecord.filter(Column("id") == id).deleteAll(db)
            guard deletedCount > 0 else { return .unchanged }

            try Self.syncAnnotationCount(fileId, in: db)
            return .changed
        }
    }

    private static func syncAnnotationCount(_ fileId: String, in db: Database) throws {
        let count = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM video_annotations WHERE video_file_id = ?",
            arguments: [fileId]
        ) ?? 0
        try db.execute(sql: "UPDATE video_files SET annotation_count = ? WHERE file_id = ?", arguments: [count, fileId])
    }
}

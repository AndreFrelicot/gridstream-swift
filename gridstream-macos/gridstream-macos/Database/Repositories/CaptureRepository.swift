import Foundation
import GRDB
import GridStreamAPI

/// A page of capture metadata with the filename of each capture's video.
nonisolated struct CapturePage: Sendable {
    let records: [FrameCaptureRecord]
    let filenames: [String: String]
    let total: Int
}

/// Persistence of frame captures (`frame_captures`).
nonisolated struct CaptureRepository: Sendable {
    let database: DatabaseManager

    func insert(_ record: FrameCaptureRecord) async throws {
        try await database.writeCatalog { db in
            try record.insert(db)
            return .changed
        }
    }

    /// Captures of a video with its filename; 404 when the video is unknown.
    func captures(ofVideo fileId: String) async throws -> (records: [FrameCaptureRecord], filename: String?) {
        try await database.read { db in
            guard let video = try VideoFileRecord.findByFileId(fileId, in: db) else {
                throw RepositoryError.notFound("Video not found")
            }
            return (try FrameCaptureRecord.findByFileId(fileId, in: db), video.filename)
        }
    }

    /// Newest-first page of capture metadata (no image data), optionally
    /// restricted to one video and/or the videos matching `criteria`.
    func page(fileId: String?, criteria: SmartListCriteria?, pagination: Pagination) async throws -> CapturePage {
        var allowedFileIds: Set<String>?
        if let criteria {
            let matching = try await CriteriaEvaluator().evaluateCriteria(criteria, db: database)
            // No matching video, no capture (and no `IN ()` clause, which SQLite rejects)
            if matching.isEmpty {
                return CapturePage(records: [], filenames: [:], total: 0)
            }
            allowedFileIds = matching
        }

        return try await database.read { [allowedFileIds] db in
            var query = FrameCaptureRecord.select(FrameCaptureRecord.metadataColumns)

            if let fileId {
                query = query.filter(Column("file_id") == fileId)
            }
            if let allowedFileIds {
                query = query.filter(Array(allowedFileIds).contains(Column("file_id")))
            }

            let total = try query.fetchCount(db)
            let records = try query
                .order(Column("created_at").desc)
                .limit(pagination.limit, offset: pagination.offset)
                .fetchAll(db)

            var filenames: [String: String] = [:]
            for record in records where filenames[record.fileId] == nil {
                if let video = try VideoFileRecord.findByFileId(record.fileId, in: db) {
                    filenames[record.fileId] = video.filename
                }
            }
            return CapturePage(records: records, filenames: filenames, total: total)
        }
    }

    /// Full capture including its JPEG data.
    func find(id: String) async throws -> FrameCaptureRecord {
        try await database.read { db in
            guard let capture = try FrameCaptureRecord.findById(id, in: db) else {
                throw RepositoryError.notFound("Capture not found")
            }
            return capture
        }
    }

    func delete(id: String) async throws {
        try await database.writeCatalog { db in
            guard try FrameCaptureRecord.findById(id, in: db) != nil else {
                throw RepositoryError.notFound("Capture not found")
            }
            return try FrameCaptureRecord.deleteById(id, in: db) ? .changed : .unchanged
        }
    }
}

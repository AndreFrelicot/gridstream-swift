import Foundation
import GRDB

/// Persistence of a video's time ranges (`time_ranges`).
nonisolated struct TimeRangeRepository: Sendable {
    let database: DatabaseManager

    func ranges(ofVideo fileId: String) async throws -> [TimeRangeRecord] {
        try await database.read { db in
            TimeRangeRecord.findByVideoFileId(fileId, in: db)
        }
    }

    /// Inserts a range for an existing video (404 otherwise).
    func create(_ record: TimeRangeRecord) async throws -> TimeRangeRecord {
        try await database.writeCatalog { db in
            guard try VideoFileRecord.findByFileId(record.videoFileId, in: db) != nil else {
                throw RepositoryError.notFound("Video not found")
            }
            try record.insert(db)
            return .changed(record)
        }
    }

    /// Moves/relabels a range of `fileId`; a nil `label` keeps the current one.
    func update(
        id: UUID,
        ofVideo fileId: String,
        startTime: Double,
        endTime: Double,
        label: String?
    ) async throws -> TimeRangeRecord {
        try await database.writeCatalog { db in
            var record = try Self.requireRange(id, ofVideo: fileId, in: db)
            record.startTime = startTime
            record.endTime = endTime
            if let label {
                record.label = label
            }
            record.touch()
            try record.update(db)
            return .changed(record)
        }
    }

    func delete(id: UUID, ofVideo fileId: String) async throws {
        try await database.writeCatalog { db in
            _ = try Self.requireRange(id, ofVideo: fileId, in: db)
            _ = try TimeRangeRecord.filter(Column("id") == id).deleteAll(db)
            return .changed
        }
    }

    private static func requireRange(_ id: UUID, ofVideo fileId: String, in db: Database) throws -> TimeRangeRecord {
        guard let record = TimeRangeRecord.findById(id, in: db) else {
            throw RepositoryError.notFound("Time range not found")
        }
        guard record.videoFileId == fileId else {
            throw RepositoryError.notFound("Time range not found for this video")
        }
        return record
    }
}

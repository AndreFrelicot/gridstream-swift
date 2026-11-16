import Foundation
import GRDB

nonisolated struct VideoFileRecord: Sendable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "video_files"

    var id: UUID
    var fileId: String
    var path: String
    var sourceDirectoryId: UUID
    var filename: String
    var fileSize: Int64
    var duration: Double
    var width: Int
    var height: Int
    var codec: String
    var lastModified: Double
    var createdAt: Double
    var updatedAt: Double
    var rating: Int
    var playCount: Int
    var totalViewTime: Int
    var lastPlayedAt: Double?
    var annotationCount: Int
    var scrubFrameCount: Int
    var scrubAttemptCount: Int
    var scrubFailed: Bool
    var scrubLastError: String?
    var scrubLastAttemptAt: Double?
    var missingSince: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case fileId = "file_id"
        case path
        case sourceDirectoryId = "source_directory_id"
        case filename
        case fileSize = "file_size"
        case duration
        case width
        case height
        case codec
        case lastModified = "last_modified"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case rating
        case playCount = "play_count"
        case totalViewTime = "total_view_time"
        case lastPlayedAt = "last_played_at"
        case annotationCount = "annotation_count"
        case scrubFrameCount = "scrub_frame_count"
        case scrubAttemptCount = "scrub_attempt_count"
        case scrubFailed = "scrub_failed"
        case scrubLastError = "scrub_last_error"
        case scrubLastAttemptAt = "scrub_last_attempt_at"
        case missingSince = "missing_since"
    }

    init(
        id: UUID = UUID(),
        fileId: String,
        path: String,
        sourceDirectoryId: UUID,
        filename: String,
        fileSize: Int64,
        duration: Double,
        width: Int,
        height: Int,
        codec: String,
        lastModified: Double,
        createdAt: Double = Date().timeIntervalSince1970,
        updatedAt: Double = Date().timeIntervalSince1970,
        rating: Int = 0,
        playCount: Int = 0,
        totalViewTime: Int = 0,
        lastPlayedAt: Double? = nil,
        annotationCount: Int = 0,
        scrubFrameCount: Int = 0,
        scrubAttemptCount: Int = 0,
        scrubFailed: Bool = false,
        scrubLastError: String? = nil,
        scrubLastAttemptAt: Double? = nil,
        missingSince: Double? = nil
    ) {
        self.id = id
        self.fileId = fileId
        self.path = path
        self.sourceDirectoryId = sourceDirectoryId
        self.filename = filename
        self.fileSize = fileSize
        self.duration = duration
        self.width = width
        self.height = height
        self.codec = codec
        self.lastModified = lastModified
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rating = rating
        self.playCount = playCount
        self.totalViewTime = totalViewTime
        self.lastPlayedAt = lastPlayedAt
        self.annotationCount = annotationCount
        self.scrubFrameCount = scrubFrameCount
        self.scrubAttemptCount = scrubAttemptCount
        self.scrubFailed = scrubFailed
        self.scrubLastError = scrubLastError
        self.scrubLastAttemptAt = scrubLastAttemptAt
        self.missingSince = missingSince
    }

    init(row: Row) throws {
        id = row["id"]
        fileId = row["file_id"]
        path = row["path"]
        sourceDirectoryId = row["source_directory_id"]
        filename = row["filename"]
        fileSize = row["file_size"]
        duration = row["duration"]
        width = row["width"]
        height = row["height"]
        codec = row["codec"]
        lastModified = row["last_modified"]
        createdAt = row["created_at"]
        updatedAt = row["updated_at"]
        rating = row["rating"] ?? 0
        playCount = row["play_count"] ?? 0
        totalViewTime = row["total_view_time"] ?? 0
        lastPlayedAt = row["last_played_at"]
        annotationCount = row["annotation_count"] ?? 0
        scrubFrameCount = row["scrub_frame_count"] ?? 0
        scrubAttemptCount = row["scrub_attempt_count"] ?? 0
        scrubFailed = (row["scrub_failed"] ?? 0) != 0
        scrubLastError = row["scrub_last_error"]
        scrubLastAttemptAt = row["scrub_last_attempt_at"]
        missingSince = row["missing_since"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["file_id"] = fileId
        container["path"] = path
        container["source_directory_id"] = sourceDirectoryId
        container["filename"] = filename
        container["file_size"] = fileSize
        container["duration"] = duration
        container["width"] = width
        container["height"] = height
        container["codec"] = codec
        container["last_modified"] = lastModified
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
        container["rating"] = rating
        container["play_count"] = playCount
        container["total_view_time"] = totalViewTime
        container["last_played_at"] = lastPlayedAt
        container["annotation_count"] = annotationCount
        container["scrub_frame_count"] = scrubFrameCount
        container["scrub_attempt_count"] = scrubAttemptCount
        container["scrub_failed"] = scrubFailed
        container["scrub_last_error"] = scrubLastError
        container["scrub_last_attempt_at"] = scrubLastAttemptAt
        container["missing_since"] = missingSince
    }

    mutating func touch() {
        updatedAt = Date().timeIntervalSince1970
    }
}

// MARK: - Query Helpers

nonisolated extension VideoFileRecord {
    /// Fetches all VideoFileRecords from the database.
    /// Used for initial cache load on app startup.
    static func fetchAllRecords(in db: Database) throws -> [VideoFileRecord] {
        try VideoFileRecord.fetchAll(db)
    }

    // MARK: - Catalog Visibility (soft delete, disabled folders)

    /// SQL condition matching the rows visible in the catalog: present on disk
    /// (not soft-deleted) and not belonging to a disabled source folder.
    nonisolated static let liveCondition = """
        missing_since IS NULL AND source_directory_id NOT IN \
        (SELECT id FROM source_directories WHERE is_enabled = 0)
        """

    /// Request over the rows visible in the catalog.
    static func liveRequest() -> QueryInterfaceRequest<VideoFileRecord> {
        VideoFileRecord.filter(sql: liveCondition)
    }

    /// File IDs of every row visible in the catalog.
    static func liveFileIds(in db: Database) throws -> Set<String> {
        Set(try String.fetchAll(db, sql: "SELECT file_id FROM video_files WHERE \(liveCondition)"))
    }

    /// Finds a row by fileId only if it is visible in the catalog.
    static func findLiveByFileId(_ fileId: String, in db: Database) throws -> VideoFileRecord? {
        try liveRequest()
            .filter(Column("file_id") == fileId)
            .fetchOne(db)
    }

    /// Soft-deletes a row: it disappears from the catalog but keeps its tags,
    /// ratings, annotations, time ranges and captures until it reappears or
    /// is purged explicitly. Returns true when the row changed.
    @discardableResult
    static func markMissing(id: UUID, at time: Double, in db: Database) throws -> Bool {
        try db.execute(
            sql: "UPDATE video_files SET missing_since = ? WHERE id = ? AND missing_since IS NULL",
            arguments: [time, id]
        )
        return db.changesCount > 0
    }

    static func countMissing(in db: Database) throws -> Int {
        try VideoFileRecord.filter(Column("missing_since") != nil).fetchCount(db)
    }

    /// Permanently deletes every soft-deleted row with all its associated data.
    /// Only reachable from the explicit "Purge missing videos…" settings action.
    @discardableResult
    static func purgeMissing(in db: Database) throws -> Int {
        let records = try VideoFileRecord.filter(Column("missing_since") != nil).fetchAll(db)
        for record in records {
            try deleteWithAssociations(record, in: db)
        }
        return records.count
    }

    // MARK: - Scanner Writes

    /// Writes only the columns the scanner owns (location and file metadata),
    /// leaving user data (rating, play stats, annotation and scrub counters)
    /// untouched, and clears `missing_since`. Targeted so that a rating or play
    /// count written while a scan runs is never overwritten by a stale snapshot.
    static func updateScannedMetadata(
        id: UUID,
        path: String,
        sourceDirectoryId: UUID,
        filename: String,
        metadata: VideoMetadata,
        now: Double,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
                UPDATE video_files
                SET path = ?, source_directory_id = ?, filename = ?, file_size = ?,
                    duration = ?, width = ?, height = ?, codec = ?, last_modified = ?,
                    updated_at = ?, missing_since = NULL
                WHERE id = ?
                """,
            arguments: [
                path, sourceDirectoryId, filename, metadata.fileSize,
                metadata.duration, metadata.width, metadata.height, metadata.codec,
                metadata.lastModified.timeIntervalSince1970, now, id
            ]
        )
    }

    /// Drops the scrub frames of a file whose content changed in place (same
    /// path, same fileId, different size or duration) so clients stop seeing
    /// frames of the old content; they are regenerated on demand.
    static func purgeScrubFrames(fileId: String, in db: Database) throws {
        _ = try ScrubFrameRecord.deleteByFileId(fileId, in: db)
        try db.execute(
            sql: """
                UPDATE video_files
                SET scrub_frame_count = 0, scrub_attempt_count = 0, scrub_failed = 0,
                    scrub_last_error = NULL
                WHERE file_id = ?
                """,
            arguments: [fileId]
        )
    }

    /// Marks a row as present again (and re-homes it to `sourceDirectoryId`).
    static func markPresent(id: UUID, sourceDirectoryId: UUID, now: Double, in db: Database) throws {
        try db.execute(
            sql: """
                UPDATE video_files
                SET missing_since = NULL, source_directory_id = ?, updated_at = ?
                WHERE id = ?
                """,
            arguments: [sourceDirectoryId, now, id]
        )
    }

    // MARK: - Scrub Failure Tracking

    /// Non-failed candidates for the idle indexing pool (present files only).
    static func fetchScrubCandidates(in db: Database) throws -> [VideoFileRecord] {
        try VideoFileRecord
            .filter(Column("scrub_failed") == false)
            .filter(Column("missing_since") == nil)
            .fetchAll(db)
    }

    static func fetchScrubBlocked(in db: Database) throws -> [VideoFileRecord] {
        try VideoFileRecord.filter(Column("scrub_failed") == true)
            .order(Column("scrub_last_attempt_at").desc).fetchAll(db)
    }

    static func recordScrubSuccess(fileId: String, in db: Database) throws {
        try db.execute(sql: """
            UPDATE video_files
            SET scrub_attempt_count = 0, scrub_failed = 0, scrub_last_error = NULL
            WHERE file_id = ?
            """, arguments: [fileId])
    }

    /// Increments the attempt counter; flags the video once it reaches `maxAttempts`.
    static func recordScrubFailure(fileId: String, error: String, now: Double,
                                   maxAttempts: Int, in db: Database) throws {
        try db.execute(sql: """
            UPDATE video_files
            SET scrub_attempt_count = scrub_attempt_count + 1,
                scrub_last_error = ?,
                scrub_last_attempt_at = ?,
                scrub_failed = CASE WHEN scrub_attempt_count + 1 >= ? THEN 1 ELSE 0 END
            WHERE file_id = ?
            """, arguments: [error, now, maxAttempts, fileId])
    }

    static func resetScrubFailure(fileId: String, in db: Database) throws {
        try db.execute(sql: """
            UPDATE video_files
            SET scrub_failed = 0, scrub_attempt_count = 0, scrub_last_error = NULL
            WHERE file_id = ?
            """, arguments: [fileId])
    }

    static func findByFileId(_ fileId: String, in db: Database) throws -> VideoFileRecord? {
        try VideoFileRecord
            .filter(Column("file_id") == fileId)
            .fetchOne(db)
    }

    static func findBySourceDirectoryId(_ sourceDirectoryId: UUID, in db: Database) throws -> [VideoFileRecord] {
        try VideoFileRecord
            .filter(Column("source_directory_id") == sourceDirectoryId)
            .fetchAll(db)
    }

    static func findByRating(_ rating: Int, in db: Database) throws -> [VideoFileRecord] {
        try VideoFileRecord
            .filter(Column("rating") == rating)
            .fetchAll(db)
    }

    static func findByRatingRange(min: Int, max: Int, in db: Database) throws -> [VideoFileRecord] {
        try VideoFileRecord
            .filter(Column("rating") >= min && Column("rating") <= max)
            .fetchAll(db)
    }

    static func findUnrated(in db: Database) throws -> [VideoFileRecord] {
        try VideoFileRecord
            .filter(Column("rating") == 0)
            .fetchAll(db)
    }

    /// Deletes all VideoFileRecords matching a given sourceDirectoryId.
    /// Also deletes associated records for those files.
    /// Used when a source directory is disabled/unchecked.
    /// Returns the number of video records deleted.
    @discardableResult
    static func deleteBySourceDirectoryId(_ sourceDirectoryId: UUID, in db: Database) throws -> Int {
        // First, get all file IDs for records in this source directory
        let records = try VideoFileRecord
            .filter(Column("source_directory_id") == sourceDirectoryId)
            .fetchAll(db)

        for record in records {
            try deleteWithAssociations(record, in: db)
        }

        return records.count
    }

    static func deleteWithAssociations(_ record: VideoFileRecord, in db: Database) throws {
        let fileId = record.fileId

        _ = try ThumbnailRecord.deleteByFileId(fileId, in: db)
        _ = try VideoTagRecord
            .filter(Column("video_file_id") == fileId)
            .deleteAll(db)
        _ = try SimpleListVideoRecord
            .filter(Column("video_file_id") == fileId)
            .deleteAll(db)
        try TimeRangeRecord.deleteByVideoFileId(fileId, in: db)
        try AnnotationRecord.deleteByVideoFileId(fileId, in: db)
        _ = try ScrubFrameRecord.deleteByFileId(fileId, in: db)
        _ = try FrameCaptureRecord
            .filter(Column("file_id") == fileId)
            .deleteAll(db)
        _ = try VideoFileRecord.deleteOne(db, key: record.id)
    }

    // MARK: - Playback Statistics

    /// Upper bound of the view time accepted in a single report (one day).
    nonisolated static let maxViewTimePerReport = 86_400

    /// Applies a playback report with targeted, overflow-safe column updates:
    /// `addViewTime` is clamped to 0…86_400 and counters saturate at `Int.max`.
    /// Must run inside a write transaction. Returns nil when the video is unknown.
    static func applyPlaybackReport(
        fileId: String,
        incrementPlayCount: Bool,
        addViewTime: Int,
        now: Double = Date().timeIntervalSince1970,
        in db: Database
    ) throws -> (playCount: Int, totalViewTime: Int)? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT play_count, total_view_time FROM video_files WHERE file_id = ?",
            arguments: [fileId]
        ) else {
            return nil
        }

        let currentPlayCount: Int = row["play_count"] ?? 0
        let currentViewTime: Int = row["total_view_time"] ?? 0
        let viewTime = min(max(addViewTime, 0), maxViewTimePerReport)

        let playCount = incrementPlayCount ? currentPlayCount.saturatingAdding(1) : currentPlayCount
        let totalViewTime = currentViewTime.saturatingAdding(viewTime)

        guard incrementPlayCount || viewTime > 0 else {
            return (playCount, totalViewTime)
        }

        try db.execute(
            sql: """
                UPDATE video_files
                SET play_count = ?, total_view_time = ?,
                    last_played_at = CASE WHEN ? THEN ? ELSE last_played_at END,
                    updated_at = ?
                WHERE file_id = ?
                """,
            arguments: [playCount, totalViewTime, incrementPlayCount, now, now, fileId]
        )
        return (playCount, totalViewTime)
    }

    // MARK: - Play Count Query Helpers

    /// Finds all videos with a specific play count.
    static func findByPlayCount(_ count: Int, in db: Database) throws -> [VideoFileRecord] {
        try VideoFileRecord
            .filter(Column("play_count") == count)
            .fetchAll(db)
    }

    /// Finds all videos with at least the specified minimum play count.
    static func findByMinPlayCount(_ min: Int, in db: Database) throws -> [VideoFileRecord] {
        try VideoFileRecord
            .filter(Column("play_count") >= min)
            .fetchAll(db)
    }

    /// Finds all unplayed videos (play_count = 0).
    static func findUnplayed(in db: Database) throws -> [VideoFileRecord] {
        try VideoFileRecord
            .filter(Column("play_count") == 0)
            .fetchAll(db)
    }

    /// Finds the most played videos, sorted by play count descending.
    /// - Parameter limit: Maximum number of videos to return
    static func findMostPlayed(limit: Int, in db: Database) throws -> [VideoFileRecord] {
        try VideoFileRecord
            .order(Column("play_count").desc)
            .limit(limit)
            .fetchAll(db)
    }
}

nonisolated extension Int {
    /// Addition that clamps to `Int.max` / `Int.min` instead of trapping.
    nonisolated func saturatingAdding(_ other: Int) -> Int {
        let (result, overflow) = addingReportingOverflow(other)
        guard overflow else { return result }
        return other > 0 ? .max : .min
    }
}

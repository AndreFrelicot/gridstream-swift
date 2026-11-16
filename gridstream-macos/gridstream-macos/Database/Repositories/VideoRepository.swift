import Foundation
import GRDB
import GridStreamAPI
import OSLog

/// Per-tag rating bounds of a `tags`/`tagRatings` video filter.
nonisolated struct VideoTagRatingFilter: Sendable, Equatable {
    let tagId: UUID
    let minRating: Int?
    let maxRating: Int?
}

/// Parsed filters, sort and page of `GET /api/v1/videos`. Every non-nil or
/// non-empty field narrows the result (intersection).
nonisolated struct VideoListQuery: Sendable {
    var criteria: SmartListCriteria?
    var search: String?
    /// Source folders whose name matches `search` (resolved by the caller from
    /// the catalog): their videos match the search too.
    var searchSourceDirectoryIds: [UUID] = []
    var sourceDirectoryId: UUID?
    var tagIds: [UUID] = []
    var tagRatings: [VideoTagRatingFilter] = []
    var excludeTagIds: [UUID] = []
    var simpleListIds: [UUID] = []
    var smartListIds: [UUID] = []
    /// DB UUIDs or fileIds.
    var videoIds: [String] = []
    var exactRating: Int?
    var minRating: Int?
    var maxRating: Int?
    var unrated: Bool?
    var played: Bool?
    var unplayed: Bool?
    var minPlayCount: Int?
    var maxPlayCount: Int?
    var minFileSize: Int64?
    var maxFileSize: Int64?
    var hasAnnotations: Bool?
    var minAnnotationCount: Int?
    var maxAnnotationCount: Int?
    var hasTextAnnotations: Bool?
    var annotationTextSearch: String?
    var hasTimeRanges: Bool?
    var filenameStartsWith: String?
    var filenameEndsWith: String?
    var filenameRegex: String?
    /// Seconds since 1970.
    var addedAfter: Double?
    var addedBefore: Double?
    var modifiedAfter: Double?
    var modifiedBefore: Double?
    /// Legacy single-tag rating filter (`tag_id`, `tag_min_rating`, `tag_max_rating`).
    var legacyTagRating: VideoTagRatingFilter?
    var sort: String?
    var pagination = Pagination(limit: 10_000, offset: 0)
}

/// Persistence of videos (`video_files`) and of their per-video data:
/// global rating, playback statistics, thumbnails and scrub status.
nonisolated struct VideoRepository: Sendable {
    private static let logger = Logger(subsystem: "com.gridstream.macos", category: "VideoRepository")

    let database: DatabaseManager

    // MARK: - Lookups

    /// Any stored row, live or not.
    func find(fileId: String) async throws -> VideoFileRecord? {
        try await database.read { db in
            try VideoFileRecord.findByFileId(fileId, in: db)
        }
    }

    /// Any stored row, live or not; 404 "Video not found" when unknown.
    func require(fileId: String) async throws -> VideoFileRecord {
        guard let record = try await find(fileId: fileId) else {
            throw RepositoryError.notFound("Video not found")
        }
        return record
    }

    /// A row visible in the catalog, by database UUID.
    func findLive(id: UUID) async throws -> VideoFileRecord? {
        try await database.read { db in
            try VideoFileRecord.liveRequest().filter(Column("id") == id).fetchOne(db)
        }
    }

    /// A row visible in the catalog, by fileId.
    func findLive(fileId: String) async throws -> VideoFileRecord? {
        try await database.read { db in
            try VideoFileRecord.findLiveByFileId(fileId, in: db)
        }
    }

    /// Tags (with per-video rating) and thumbnail `updatedAt` of one video.
    func details(fileId: String) async throws -> (tags: [TagSummary], thumbnailUpdatedAt: Double?) {
        try await database.read { db in
            (
                TagRepository.tagSummariesWithRatings(forFileId: fileId, in: db),
                try Self.thumbnailTimestamps(fileIds: [fileId], in: db)[fileId]
            )
        }
    }

    /// Tags (with per-video rating) and thumbnail `updatedAt` of many videos.
    func details(fileIds: [String]) async throws -> (tags: [String: [TagSummary]], thumbnailUpdatedAt: [String: Double]) {
        try await database.read { db in
            (
                try TagRepository.tagSummariesWithRatings(forFileIds: fileIds, in: db),
                try Self.thumbnailTimestamps(fileIds: fileIds, in: db)
            )
        }
    }

    // MARK: - List

    /// One page of the live videos matching `query`, and the total match count.
    func list(_ query: VideoListQuery) async throws -> (records: [VideoFileRecord], total: Int) {
        let evaluator = CriteriaEvaluator()

        var criteriaFileIds: Set<String>?
        if let criteria = query.criteria {
            criteriaFileIds = try await evaluator.evaluateCriteria(criteria, db: database)
            Self.logger.info("Criteria evaluation returned \(criteriaFileIds?.count ?? 0) matching file IDs")
        }

        // Smart lists are evaluated one by one and intersected
        var smartListFileIds: Set<String>?
        for smartListId in query.smartListIds {
            let fileIds = try await evaluator.evaluateCondition(.smartListInclude(smartListId: smartListId), db: database)
            smartListFileIds = smartListFileIds.map { $0.intersection(fileIds) } ?? fileIds
            if smartListFileIds?.isEmpty == true { break }
        }
        if smartListFileIds?.isEmpty == true {
            return ([], 0)
        }

        let restrictions = (criteria: criteriaFileIds, smartLists: smartListFileIds)
        return try await database.read { db in
            try Self.list(query, criteriaFileIds: restrictions.criteria, smartListFileIds: restrictions.smartLists, in: db)
        }
    }

    private static func list(
        _ query: VideoListQuery,
        criteriaFileIds: Set<String>?,
        smartListFileIds: Set<String>?,
        in db: Database
    ) throws -> (records: [VideoFileRecord], total: Int) {
        let limit = query.pagination.limit
        let offset = query.pagination.offset

        // File IDs having every requested tag, with their rating bounds
        var tagFileIds: Set<String>?
        if !query.tagIds.isEmpty {
            let fileIds = try fileIdsWithAllTags(query.tagIds, ratings: query.tagRatings, in: db)
            if fileIds.isEmpty { return ([], 0) }
            tagFileIds = fileIds
        }

        var excludedFileIds = Set<String>()
        for tagId in query.excludeTagIds {
            excludedFileIds.formUnion(VideoTagRecord.findByTagId(tagId, in: db).map(\.videoFileId))
        }

        // Videos in every requested simple list
        var simpleListFileIds: Set<String>?
        for listId in query.simpleListIds {
            let fileIds = Set(SimpleListVideoRecord.findByListId(listId, in: db).map(\.videoFileId))
            simpleListFileIds = simpleListFileIds.map { $0.intersection(fileIds) } ?? fileIds
            if simpleListFileIds?.isEmpty == true { return ([], 0) }
        }

        var legacyTagRatingFileIds: Set<String>?
        if let filter = query.legacyTagRating, filter.minRating != nil || filter.maxRating != nil {
            legacyTagRatingFileIds = Set(try VideoTagRecord.findByTagIdWithRating(
                filter.tagId, minRating: filter.minRating, maxRating: filter.maxRating, in: db
            ).map(\.videoFileId))
        }

        // Soft-deleted videos and videos of disabled source folders are not in the catalog
        var request = VideoFileRecord.liveRequest()

        if let criteriaFileIds {
            if criteriaFileIds.isEmpty { return ([], 0) }
            request = request.filter(criteriaFileIds.contains(Column("file_id")))
        }

        if let sourceDirectoryId = query.sourceDirectoryId {
            request = request.filter(Column("source_directory_id") == sourceDirectoryId)
        }

        // Search across filename and source folder name
        if let search = query.search, !search.isEmpty {
            let pattern = "%\(CriteriaEvaluator.escapeLike(search))%"
            if query.searchSourceDirectoryIds.isEmpty {
                request = request.filter(Column("filename").like(pattern, escape: "\\"))
            } else {
                request = request.filter(
                    Column("filename").like(pattern, escape: "\\") ||
                    query.searchSourceDirectoryIds.contains(Column("source_directory_id"))
                )
            }
        }

        if let startsWith = query.filenameStartsWith, !startsWith.isEmpty {
            request = request.filter(Column("filename").like("\(CriteriaEvaluator.escapeLike(startsWith))%", escape: "\\"))
        }
        if let endsWith = query.filenameEndsWith, !endsWith.isEmpty {
            request = request.filter(Column("filename").like("%\(CriteriaEvaluator.escapeLike(endsWith))", escape: "\\"))
        }

        if query.unrated == true {
            request = request.filter(Column("rating") == 0)
        } else if let exactRating = query.exactRating {
            request = request.filter(Column("rating") == exactRating)
        } else {
            if let minRating = query.minRating {
                request = request.filter(Column("rating") >= minRating)
            }
            if let maxRating = query.maxRating {
                request = request.filter(Column("rating") <= maxRating)
            }
        }

        // Played at least once
        if query.played == true {
            request = request.filter(Column("last_played_at") != nil)
        }

        if query.unplayed == true {
            request = request.filter(Column("play_count") == 0)
        } else {
            if let minPlayCount = query.minPlayCount {
                request = request.filter(Column("play_count") >= minPlayCount)
            }
            if let maxPlayCount = query.maxPlayCount {
                request = request.filter(Column("play_count") <= maxPlayCount)
            }
        }

        // File size in bytes
        if let minFileSize = query.minFileSize {
            request = request.filter(Column("file_size") >= minFileSize)
        }
        if let maxFileSize = query.maxFileSize {
            request = request.filter(Column("file_size") <= maxFileSize)
        }

        if let hasAnnotations = query.hasAnnotations {
            request = request.filter(hasAnnotations ? Column("annotation_count") > 0 : Column("annotation_count") == 0)
        }
        if let minAnnotationCount = query.minAnnotationCount {
            request = request.filter(Column("annotation_count") >= minAnnotationCount)
        }
        if let maxAnnotationCount = query.maxAnnotationCount {
            request = request.filter(Column("annotation_count") <= maxAnnotationCount)
        }
        if let hasTextAnnotations = query.hasTextAnnotations {
            let fileIds = try fileIdsWithTextAnnotations(hasTextAnnotations, in: db)
            request = request.filter(fileIds.contains(Column("file_id")))
        }
        if let ftsQuery = query.annotationTextSearch.flatMap(CriteriaEvaluator.annotationTextFTSQuery(for:)) {
            let fileIds = Set(try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT video_file_id
                    FROM video_annotation_text_fts
                    WHERE video_annotation_text_fts MATCH ?
                    """,
                arguments: [ftsQuery]
            ))
            request = request.filter(fileIds.contains(Column("file_id")))
        }
        if let hasTimeRanges = query.hasTimeRanges {
            let fileIds = try CriteriaEvaluator.videoFileIdsWithPlayableTimeRanges(hasTimeRanges, in: db)
            request = request.filter(fileIds.contains(Column("file_id")))
        }

        if let addedAfter = query.addedAfter {
            request = request.filter(Column("created_at") > addedAfter)
        }
        if let addedBefore = query.addedBefore {
            request = request.filter(Column("created_at") < addedBefore)
        }
        if let modifiedAfter = query.modifiedAfter {
            request = request.filter(Column("last_modified") > modifiedAfter)
        }
        if let modifiedBefore = query.modifiedBefore {
            request = request.filter(Column("last_modified") < modifiedBefore)
        }

        if let tagFileIds {
            request = request.filter(tagFileIds.contains(Column("file_id")))
        }
        if let legacyTagRatingFileIds {
            request = request.filter(legacyTagRatingFileIds.contains(Column("file_id")))
        }
        if !excludedFileIds.isEmpty {
            request = request.filter(!excludedFileIds.contains(Column("file_id")))
        }
        if let simpleListFileIds {
            request = request.filter(simpleListFileIds.contains(Column("file_id")))
        }
        if let smartListFileIds {
            request = request.filter(smartListFileIds.contains(Column("file_id")))
        }

        // Explicit video selection, by DB UUID or fileId
        if !query.videoIds.isEmpty {
            let videoUUIDs = query.videoIds.compactMap { UUID(uuidString: $0) }
            if videoUUIDs.isEmpty {
                request = request.filter(query.videoIds.contains(Column("file_id")))
            } else {
                request = request.filter(videoUUIDs.contains(Column("id")) || query.videoIds.contains(Column("file_id")))
            }
        }

        request = sorted(request, by: query.sort)

        // A regex cannot run in SQLite: filter in Swift, then paginate
        if let pattern = query.filenameRegex {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                return ([], 0)
            }
            let matching = try request.fetchAll(db).filter { record in
                regex.firstMatch(in: record.filename, range: NSRange(record.filename.startIndex..., in: record.filename)) != nil
            }
            return (Array(matching.dropFirst(offset).prefix(limit)), matching.count)
        }

        let total = try request.fetchCount(db)
        let records = try request.limit(limit, offset: offset).fetchAll(db)
        return (records, total)
    }

    private static func sorted(
        _ request: QueryInterfaceRequest<VideoFileRecord>,
        by sort: String?
    ) -> QueryInterfaceRequest<VideoFileRecord> {
        switch sort {
        case "rating_asc":
            request.order(Column("rating").asc)
        case "rating_desc":
            request.order(Column("rating").desc)
        case "filename_desc":
            request.order(Column("filename").collating(.localizedCaseInsensitiveCompare).desc)
        case "playCount_asc", "play_count_asc":
            request.order(Column("play_count").asc)
        case "playCount_desc", "play_count_desc":
            request.order(Column("play_count").desc)
        case "lastPlayed_desc", "last_played_desc":
            request.order(Column("last_played_at").desc)
        case "lastPlayed_asc", "last_played_asc":
            request.order(Column("last_played_at").asc)
        default:
            // "filename_asc" and unknown values
            request.order(Column("filename").collating(.localizedCaseInsensitiveCompare).asc)
        }
    }

    /// Videos having every tag of `tagIds`, honoring the rating bounds given
    /// for some of them (duplicate tagIds in `ratings`: last one wins).
    private static func fileIdsWithAllTags(
        _ tagIds: [UUID],
        ratings: [VideoTagRatingFilter],
        in db: Database
    ) throws -> Set<String> {
        let ratingsByTagId = Dictionary(ratings.map { ($0.tagId, $0) }, uniquingKeysWith: { _, last in last })

        var result: Set<String>?
        for tagId in tagIds {
            let videoTags: [VideoTagRecord]
            if let filter = ratingsByTagId[tagId], filter.minRating != nil || filter.maxRating != nil {
                videoTags = try VideoTagRecord.findByTagIdWithRating(
                    tagId, minRating: filter.minRating, maxRating: filter.maxRating, in: db
                )
            } else {
                videoTags = VideoTagRecord.findByTagId(tagId, in: db)
            }

            let fileIds = Set(videoTags.map(\.videoFileId))
            result = result.map { $0.intersection(fileIds) } ?? fileIds
            if result?.isEmpty == true { return [] }
        }
        return result ?? []
    }

    private static func fileIdsWithTextAnnotations(_ value: Bool, in db: Database) throws -> Set<String> {
        let withText = """
            SELECT DISTINCT video_file_id
            FROM video_annotations
            WHERE text IS NOT NULL
              AND TRIM(text) <> ''
            """
        if value {
            return Set(try String.fetchAll(db, sql: withText))
        }
        return Set(try String.fetchAll(db, sql: "SELECT file_id FROM video_files WHERE file_id NOT IN (\(withText))"))
    }

    private static func thumbnailTimestamps(fileIds: [String], in db: Database) throws -> [String: Double] {
        guard !fileIds.isEmpty else { return [:] }
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT file_id, updated_at FROM thumbnails WHERE file_id IN (\(fileIds.map { _ in "?" }.joined(separator: ",")))",
            arguments: StatementArguments(fileIds)
        )
        var result: [String: Double] = [:]
        for row in rows {
            result[row["file_id"]] = row["updated_at"]
        }
        return result
    }

    // MARK: - Rating

    /// Targeted column update: never rewrites the whole row from a stale
    /// snapshot (a concurrent scan or play-count report would be overwritten).
    func setRating(_ rating: Int, fileId: String) async throws {
        let now = Date().timeIntervalSince1970
        try await database.writeCatalog { db in
            try db.execute(
                sql: "UPDATE video_files SET rating = ?, updated_at = ? WHERE file_id = ?",
                arguments: [rating, now, fileId]
            )
            guard db.changesCount > 0 else {
                throw RepositoryError.notFound("Video not found")
            }
            return .changed
        }
    }

    /// Rates every video of a source folder; returns how many were rated.
    func setRating(_ rating: Int, inSourceDirectory sourceDirectoryId: UUID) async throws -> Int {
        let now = Date().timeIntervalSince1970
        return try await database.writeCatalog { db in
            try db.execute(
                sql: "UPDATE video_files SET rating = ?, updated_at = ? WHERE source_directory_id = ?",
                arguments: [rating, now, sourceDirectoryId]
            )
            let affected = db.changesCount
            guard affected > 0 else {
                throw RepositoryError.notFound("Source directory not found or contains no videos")
            }
            return .changed(affected)
        }
    }

    // MARK: - Playback statistics

    /// Applies a playback report (see `VideoFileRecord.applyPlaybackReport`).
    func applyPlaybackReport(
        fileId: String,
        incrementPlayCount: Bool,
        addViewTime: Int
    ) async throws -> (playCount: Int, totalViewTime: Int) {
        try await database.writeCatalog { db in
            guard let stats = try VideoFileRecord.applyPlaybackReport(
                fileId: fileId,
                incrementPlayCount: incrementPlayCount,
                addViewTime: addViewTime,
                in: db
            ) else {
                throw RepositoryError.notFound("Video not found")
            }
            return incrementPlayCount || addViewTime > 0 ? .changed(stats) : .unchanged(stats)
        }
    }

    // MARK: - Thumbnails

    /// JPEG thumbnail of a stored video. 404 when the video or its thumbnail is unknown.
    func thumbnail(fileId: String) async throws -> Data {
        try await database.read { db in
            guard try VideoFileRecord.findByFileId(fileId, in: db) != nil else {
                throw RepositoryError.notFound("Video not found")
            }
            guard let thumbnail = try ThumbnailRecord.findByFileId(fileId, in: db) else {
                throw RepositoryError.notFound("Thumbnail not found for video")
            }
            return thumbnail.imageData
        }
    }

    /// Stores a new thumbnail; returns its `updatedAt`.
    func saveThumbnail(_ imageData: Data, fileId: String) async throws -> Double {
        try await database.writeCatalog { db in
            if var existing = try ThumbnailRecord.findByFileId(fileId, in: db) {
                existing.imageData = imageData
                existing.touch()
                try existing.update(db)
                return .changed(existing.updatedAt)
            }
            let thumbnail = ThumbnailRecord(fileId: fileId, imageData: imageData)
            try thumbnail.insert(db)
            return .changed(thumbnail.updatedAt)
        }
    }

    // MARK: - Scrub status

    /// Videos whose scrub frame generation keeps failing.
    func scrubBlocked() async throws -> [VideoFileRecord] {
        try await database.read { db in
            try VideoFileRecord.fetchScrubBlocked(in: db)
        }
    }

    /// Clears a video's scrub failure so generation is retried (not a catalog change).
    func resetScrubFailure(fileId: String) async throws {
        try await database.write { db in
            try VideoFileRecord.resetScrubFailure(fileId: fileId, in: db)
        }
    }
}

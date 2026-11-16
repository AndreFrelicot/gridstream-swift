import Foundation
import GridStreamAPI
import OSLog
import Vapor

nonisolated struct VideoCatalogStorageKey: StorageKey {
    typealias Value = VideoCatalogProvider
}

nonisolated struct VideoCatalogSnapshot: Sendable {
    let videos: [VideoItem]
    let sourceDirectories: [SourceDirectory]
}

nonisolated protocol VideoCatalogProvider: Sendable {
    func getVideos() -> [VideoItem]
    func getSourceDirectories() -> [SourceDirectory]
    func getVideoByFileId(_ fileId: String) -> VideoItem?
    func getSnapshot() -> VideoCatalogSnapshot
}

nonisolated extension VideoCatalogProvider {
    func getSnapshot() -> VideoCatalogSnapshot {
        VideoCatalogSnapshot(videos: getVideos(), sourceDirectories: getSourceDirectories())
    }
}


nonisolated struct VideoRoutes: RouteCollection {
    private let logger = Logger(subsystem: "com.gridstream.macos", category: "VideoRoutes")
    private let videos: VideoRepository

    init(databaseManager: DatabaseManager) {
        self.videos = VideoRepository(database: databaseManager)
    }

    func boot(routes: RoutesBuilder) throws {
        let api = routes.grouped("api", "v1")
        let videos = api.grouped("videos")

        videos.get(use: listVideos)
        videos.get(":id", use: getVideo)
        videos.get("by-file-id", ":fileId", use: getVideoByFileId)

        // Source directories endpoint
        let sourceDirectories = api.grouped("source-directories")
        sourceDirectories.get(use: listSourceDirectories)
    }

    // MARK: - GET /api/v1/videos

    @Sendable
    private func listVideos(req: Request) async throws -> PaginatedVideosResponse {
        let catalog = try req.catalogProvider()
        let sourceDirectories = catalog.getSourceDirectories()
        let sourceDirectoryMap = Dictionary(sourceDirectories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let query = try videoListQuery(from: req, sourceDirectories: sourceDirectories)
        let result = try await videos.list(query)

        let fileIds = result.records.map(\.fileId)
        let details = try await videos.details(fileIds: fileIds)
        let items = result.records.map { record in
            VideoItem.api(
                record: record,
                sourceDirectory: sourceDirectoryMap[record.sourceDirectoryId],
                tags: details.tags[record.fileId] ?? [],
                thumbnailUpdatedAt: details.thumbnailUpdatedAt[record.fileId]
            )
        }

        logger.debug("Database query returned \(items.count) videos (total: \(result.total))")

        return PaginatedVideosResponse(
            videos: items,
            total: result.total,
            limit: query.pagination.limit,
            offset: query.pagination.offset
        )
    }

    /// Parses the list query string. The `criteria` JSON and the flat
    /// parameters combine by intersection.
    private func videoListQuery(from req: Request, sourceDirectories: [SourceDirectory]) throws -> VideoListQuery {
        var query = VideoListQuery()
        query.sort = req.query[String.self, at: "sort"]
        query.pagination = try req.pagination(defaultLimit: 10000)

        if let criteria = req.query[String.self, at: "criteria"] {
            query.criteria = try QueryValidation.criteria(json: criteria)
        }

        query.search = req.query[String.self, at: "search"]
        query.searchSourceDirectoryIds = sourceDirectoryIds(matching: query.search, in: sourceDirectories)
        query.sourceDirectoryId = req.query[String.self, at: "sourceDirectoryId"].flatMap { UUID(uuidString: $0) }
        query.videoIds = req.query[String.self, at: "videoIds"]?.split(separator: ",").map { String($0) } ?? []
        query.tagIds = uuidList(req, at: "tags")
        query.excludeTagIds = uuidList(req, at: "excludeTags")
        query.simpleListIds = uuidList(req, at: "simpleListIds")
        query.smartListIds = uuidList(req, at: "smartListIds")

        query.minRating = req.query[Int.self, at: "minRating"] ?? req.query[Int.self, at: "min_rating"]
        query.maxRating = req.query[Int.self, at: "maxRating"] ?? req.query[Int.self, at: "max_rating"]
        query.exactRating = req.query[Int.self, at: "rating"]
        query.unrated = req.query[Bool.self, at: "unrated"]
        query.played = req.query[Bool.self, at: "played"]
        query.unplayed = req.query[Bool.self, at: "unplayed"]
        query.minPlayCount = req.query[Int.self, at: "minPlayCount"]
        query.maxPlayCount = req.query[Int.self, at: "maxPlayCount"]
        query.minFileSize = req.query[Int64.self, at: "minFileSize"]
        query.maxFileSize = req.query[Int64.self, at: "maxFileSize"]

        query.hasAnnotations = optionalBoolQuery(req, at: "hasAnnotations")
        query.minAnnotationCount = req.query[Int.self, at: "minAnnotationCount"]
        query.maxAnnotationCount = req.query[Int.self, at: "maxAnnotationCount"]
        query.hasTextAnnotations = optionalBoolQuery(req, at: "hasTextAnnotations")
        query.annotationTextSearch = req.query[String.self, at: "annotationTextSearch"]
        query.hasTimeRanges = optionalBoolQuery(req, at: "hasTimeRanges") ?? optionalBoolQuery(req, at: "hasSegments")

        query.filenameStartsWith = req.query[String.self, at: "filenameStartsWith"]
        query.filenameEndsWith = req.query[String.self, at: "filenameEndsWith"]
        query.filenameRegex = req.query[String.self, at: "filenameRegex"]
        if let filenameRegex = query.filenameRegex, filenameRegex.count > SmartListCriteria.maxPatternLength {
            throw Abort(.badRequest, reason: "filenameRegex must be at most \(SmartListCriteria.maxPatternLength) characters")
        }

        query.addedAfter = epochQuery(req, at: "addedAfter")
        query.addedBefore = epochQuery(req, at: "addedBefore")
        query.modifiedAfter = epochQuery(req, at: "modifiedAfter")
        query.modifiedBefore = epochQuery(req, at: "modifiedBefore")

        // Format: "uuid:min-max,uuid:min-max", e.g. "550e8400-…:3-8,6ba7b810-…:-5"
        let tagRatingsString = req.query[String.self, at: "tagRatings"]
        query.tagRatings = parseTagRatingsParameter(tagRatingsString)
        if let tagRatingsString {
            logger.info("Received tagRatings parameter: \(tagRatingsString)")
        }
        for filter in query.tagRatings {
            logger.info("Parsed tag rating filter: tagId=\(filter.tagId), min=\(filter.minRating?.description ?? "nil"), max=\(filter.maxRating?.description ?? "nil")")
        }

        // Legacy single-tag rating filter
        if let tagId = req.query[String.self, at: "tag_id"].flatMap({ UUID(uuidString: $0) }) {
            query.legacyTagRating = VideoTagRatingFilter(
                tagId: tagId,
                minRating: req.query[Int.self, at: "tag_min_rating"],
                maxRating: req.query[Int.self, at: "tag_max_rating"]
            )
        }

        return query
    }

    private func uuidList(_ req: Request, at key: String) -> [UUID] {
        req.query[String.self, at: key]?.split(separator: ",").compactMap { UUID(uuidString: String($0)) } ?? []
    }

    private func epochQuery(_ req: Request, at key: String) -> Double? {
        req.query[String.self, at: key].flatMap { TolerantDateDecoding.date(from: $0)?.timeIntervalSince1970 }
    }

    private func sourceDirectoryIds(matching search: String?, in sourceDirectories: [SourceDirectory]) -> [UUID] {
        guard let search,
              !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return sourceDirectories.compactMap { sourceDirectory in
            let name = VideoItem.directoryName(of: sourceDirectory.path)
            return name.localizedCaseInsensitiveContains(search) ? sourceDirectory.id : nil
        }
    }

    private func optionalBoolQuery(_ req: Request, at key: String) -> Bool? {
        guard let raw = req.query[String.self, at: key]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !raw.isEmpty else {
            return nil
        }

        switch raw {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            return nil
        }
    }

    // MARK: - GET /api/v1/videos/:id

    @Sendable
    private func getVideo(req: Request) async throws -> VideoItem {
        let videoId = try req.requireUUID("id", label: "video")
        let catalog = try req.catalogProvider()

        guard let record = try await videos.findLive(id: videoId) else {
            throw Abort(.notFound, reason: "Video not found")
        }
        return try await apiItem(for: record, sourceDirectories: catalog.getSourceDirectories())
    }

    // MARK: - GET /api/v1/videos/by-file-id/:fileId

    @Sendable
    private func getVideoByFileId(req: Request) async throws -> VideoItem {
        let fileId = try req.requireParameter("fileId", reason: "Missing file ID")
        let catalog = try req.catalogProvider()

        guard let record = try await videos.findLive(fileId: fileId) else {
            throw Abort(.notFound, reason: "Video not found")
        }
        return try await apiItem(for: record, sourceDirectories: catalog.getSourceDirectories())
    }

    private func apiItem(for record: VideoFileRecord, sourceDirectories: [SourceDirectory]) async throws -> VideoItem {
        let details = try await videos.details(fileId: record.fileId)
        return VideoItem.api(
            record: record,
            sourceDirectory: sourceDirectories.first(where: { $0.id == record.sourceDirectoryId }),
            tags: details.tags,
            thumbnailUpdatedAt: details.thumbnailUpdatedAt
        )
    }

    // MARK: - GET /api/v1/source-directories

    @Sendable
    private func listSourceDirectories(req: Request) async throws -> SourceDirectoriesResponse {
        let catalog = try req.catalogProvider()
        let directories = catalog.getSourceDirectories()

        let directoryInfos = directories.map { dir in
            SourceDirectoryDTO(
                id: dir.id.uuidString,
                name: VideoItem.directoryName(of: dir.path),
                path: dir.path
            )
        }

        logger.info("Returning \(directoryInfos.count) source directories")
        for dir in directoryInfos {
            logger.debug("  Directory: id=\(dir.id), name=\(dir.name)")
        }

        return SourceDirectoriesResponse(directories: directoryInfos)
    }

    // MARK: - Query parsing

    /// Parses the tagRatings query parameter into individual tag rating filters.
    /// Format: "uuid:min-max,uuid:min-max" where min or max can be empty
    /// Examples: "uuid1:3-8" (3 to 8), "uuid2:-5" (up to 5), "uuid3:3-" (3 and above)
    private func parseTagRatingsParameter(_ tagRatingsString: String?) -> [VideoTagRatingFilter] {
        guard let tagRatingsString = tagRatingsString, !tagRatingsString.isEmpty else {
            return []
        }

        var filters: [VideoTagRatingFilter] = []

        for component in tagRatingsString.split(separator: ",") {
            let parts = component.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  let tagId = UUID(uuidString: String(parts[0])) else {
                continue
            }

            let ratingRange = String(parts[1])
            let rangeParts = ratingRange.split(separator: "-", omittingEmptySubsequences: false)

            var minRating: Int?
            var maxRating: Int?

            if rangeParts.count >= 1 {
                let minStr = String(rangeParts[0])
                if !minStr.isEmpty {
                    minRating = Int(minStr)
                }
            }

            if rangeParts.count >= 2 {
                let maxStr = String(rangeParts[1])
                if !maxStr.isEmpty {
                    maxRating = Int(maxStr)
                }
            }

            filters.append(VideoTagRatingFilter(tagId: tagId, minRating: minRating, maxRating: maxRating))
        }

        return filters
    }
}

//
//  ContentLibraryService.swift
//  gridstream-ipad
//

import Foundation
import GridStreamAPI
import OSLog

/// Service for fetching and managing videos in the Content Library.
/// Provides methods for filtered video fetching, tag application, rating updates,
/// and bulk operations.
@MainActor
final class ContentLibraryService {
    private let sessionManager: ServerSessionManager

    init(sessionManager: ServerSessionManager? = nil) {
        self.sessionManager = sessionManager ?? .shared
    }

    // Explicit teardown avoids the isolated-deinit back-deploy shim when
    // SwiftUI releases this service outside a Swift task.
    deinit {}

    private func api(_ serverURL: URL) -> APIClient {
        APIClient(serverURL: serverURL, session: sessionManager)
    }

    // MARK: - Video Fetching

    /// Fetches videos from the server with optional filters.
    /// - Parameters:
    ///   - serverURL: The base server URL
    ///   - filters: Optional filters to apply (search, tags, ratings, source directory, play count)
    ///   - sortOption: Optional sort option for the results
    ///   - limit: Maximum number of videos to return (default 100)
    ///   - offset: Offset for pagination (default 0)
    /// - Returns: A tuple containing the videos and total count
    func fetchVideos(
        from serverURL: URL,
        filters: ContentLibraryFilters = ContentLibraryFilters(),
        sortOption: ContentLibrarySortOption? = nil,
        limit: Int = 100,
        offset: Int = 0
    ) async throws -> (videos: [VideoItem], total: Int) {
        var queryItems: [URLQueryItem] = []

        // Add filter parameters
        if !filters.searchText.isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: filters.searchText))
        }

        if !filters.activeTagFilters.isEmpty {
            let tagIds = filters.activeTagFilters.map { $0.tag.id.uuidString }.joined(separator: ",")
            queryItems.append(URLQueryItem(name: "tags", value: tagIds))

            // Add tag ratings if any have filters
            let ratingsWithFilter = filters.activeTagFilters.filter { $0.hasRatingFilter }
            AppLogger.video.info("Active tag filters: \(filters.activeTagFilters.count), with rating filter: \(ratingsWithFilter.count)")
            for tagFilter in filters.activeTagFilters {
                AppLogger.video.info("  Tag: \(tagFilter.tag.name), minRating: \(tagFilter.minRating?.description ?? "nil"), maxRating: \(tagFilter.maxRating?.description ?? "nil"), hasFilter: \(tagFilter.hasRatingFilter)")
            }
            if !ratingsWithFilter.isEmpty {
                let tagRatingsString = ratingsWithFilter.map { filter -> String in
                    let min = filter.minRating.map { String($0) } ?? ""
                    let max = filter.maxRating.map { String($0) } ?? ""
                    return "\(filter.tag.id.uuidString):\(min)-\(max)"
                }.joined(separator: ",")
                AppLogger.video.info("Sending tagRatings parameter: \(tagRatingsString)")
                queryItems.append(URLQueryItem(name: "tagRatings", value: tagRatingsString))
            }
        }

        if let minRating = filters.minRating {
            queryItems.append(URLQueryItem(name: "minRating", value: String(minRating)))
        }

        if let maxRating = filters.maxRating {
            queryItems.append(URLQueryItem(name: "maxRating", value: String(maxRating)))
        }

        if let sourceDirectoryId = filters.sourceDirectoryId {
            AppLogger.video.debug("Filtering by sourceDirectoryId: \(sourceDirectoryId)")
            queryItems.append(URLQueryItem(name: "sourceDirectoryId", value: sourceDirectoryId))
        }

        // Play count filters
        if let minPlayCount = filters.minPlayCount {
            queryItems.append(URLQueryItem(name: "minPlayCount", value: String(minPlayCount)))
        }

        if filters.unplayedOnly {
            queryItems.append(URLQueryItem(name: "unplayed", value: "true"))
        }

        if filters.playedOnly {
            queryItems.append(URLQueryItem(name: "played", value: "true"))
        }

        if filters.unratedOnly {
            queryItems.append(URLQueryItem(name: "unrated", value: "true"))
        }

        if let hasAnnotations = filters.hasAnnotations {
            queryItems.append(URLQueryItem(name: "hasAnnotations", value: String(hasAnnotations)))
        }

        if let minAnnotationCount = filters.minAnnotationCount {
            queryItems.append(URLQueryItem(name: "minAnnotationCount", value: String(minAnnotationCount)))
        }

        if let maxAnnotationCount = filters.maxAnnotationCount {
            queryItems.append(URLQueryItem(name: "maxAnnotationCount", value: String(maxAnnotationCount)))
        }

        if let hasTextAnnotations = filters.hasTextAnnotations {
            queryItems.append(URLQueryItem(name: "hasTextAnnotations", value: String(hasTextAnnotations)))
        }

        if !filters.annotationTextSearch.isEmpty {
            queryItems.append(URLQueryItem(name: "annotationTextSearch", value: filters.annotationTextSearch))
        }

        if let videoIds = filters.videoIds, !videoIds.isEmpty {
            AppLogger.video.info("fetchVideos: Adding videoIds filter with \(videoIds.count) ids")
            queryItems.append(URLQueryItem(name: "videoIds", value: videoIds.joined(separator: ",")))
        }

        // Add sort parameter
        if let sort = sortOption {
            queryItems.append(URLQueryItem(name: "sort", value: sort.rawValue))
        }

        // Add pagination parameters
        queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        queryItems.append(URLQueryItem(name: "offset", value: String(offset)))

        let videosResponse = try await api(serverURL).fetch(PaginatedVideosResponse.self, "videos", query: queryItems)
        let total = videosResponse.total

        return (videosResponse.videos, total)
    }

    /// Fetches videos from the server using Smart List criteria, sent as a
    /// single JSON `criteria` query parameter.
    /// - Parameters:
    ///   - serverURL: The base server URL
    ///   - criteria: The Smart List criteria to apply
    ///   - limit: Maximum number of videos to return (default 100)
    ///   - offset: Offset for pagination (default 0)
    /// - Returns: A tuple containing the videos and total count
    func fetchVideosWithSmartListCriteria(
        from serverURL: URL,
        criteria: SmartListCriteria,
        limit: Int = 100,
        offset: Int = 0
    ) async throws -> (videos: [VideoItem], total: Int) {
        var queryItems: [URLQueryItem] = []

        // Encode criteria as JSON and send as single param
        let criteriaData = try JSONEncoder.gridStream().encode(criteria)
        if let criteriaJSON = String(data: criteriaData, encoding: .utf8) {
            queryItems.append(URLQueryItem(name: "criteria", value: criteriaJSON))
        }

        // Add pagination parameters
        queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        queryItems.append(URLQueryItem(name: "offset", value: String(offset)))

        let videosResponse = try await api(serverURL).fetch(PaginatedVideosResponse.self, "videos", query: queryItems)
        let total = videosResponse.total

        AppLogger.video.debug("Fetched \(videosResponse.videos.count) videos matching Smart List criteria (total: \(total))")
        return (videosResponse.videos, total)
    }

    // MARK: - Catalog Status

    /// Fetches the catalog status (version) from the server.
    /// Used to detect when the video catalog has changed.
    /// - Parameter serverURL: The base server URL
    /// - Returns: The catalog version as Int64 timestamp
    func fetchCatalogStatus(from serverURL: URL) async throws -> Int64 {
        let statusResponse = try await api(serverURL).fetch(CatalogStatusDTO.self, "catalog/status")
        AppLogger.video.debug("Fetched catalog version: \(statusResponse.version)")
        return statusResponse.version
    }

    // MARK: - Tag Operations

    /// Fetches all available tags from the server.
    func fetchTags(from serverURL: URL) async throws -> [TagInfo] {
        try await api(serverURL).fetch(TagsResponse.self, "tags").tags.map {
            TagInfo(id: $0.id, name: $0.name, color: $0.color, ratingEnabled: $0.ratingEnabled, videoCount: $0.videoCount)
        }
    }

    /// Creates a new tag on the server.
    /// - Parameters:
    ///   - name: The name of the tag
    ///   - color: The hex color code for the tag (must be from TagColorPalette)
    ///   - description: Optional description for the tag
    ///   - ratingEnabled: Whether ratings are enabled for this tag
    ///   - serverURL: The base server URL
    /// - Returns: The created TagInfo
    func createTag(
        name: String,
        color: String,
        description: String?,
        ratingEnabled: Bool,
        serverURL: URL
    ) async throws -> TagInfo {
        let createRequest = CreateTagRequest(
            name: name,
            color: color,
            description: description,
            ratingEnabled: ratingEnabled
        )
        let tagDTO = try await api(serverURL).fetch(
            TagDTO.self, .post, "tags", body: createRequest, expecting: [201]
        )
        AppLogger.video.info("Created tag: \(name)")
        return tagDTO.tagInfo
    }

    /// Updates an existing tag on the server.
    /// - Parameters:
    ///   - id: The UUID of the tag to update
    ///   - name: The new name (optional)
    ///   - color: The new color (optional)
    ///   - description: The new description (optional)
    ///   - ratingEnabled: Whether ratings are enabled (optional)
    ///   - serverURL: The base server URL
    /// - Returns: The updated TagInfo
    func updateTag(
        id: UUID,
        name: String?,
        color: String?,
        description: String?,
        ratingEnabled: Bool?,
        serverURL: URL
    ) async throws -> TagInfo {
        let updateRequest = UpdateTagRequest(
            name: name,
            color: color,
            description: description,
            ratingEnabled: ratingEnabled
        )
        let tagDTO = try await api(serverURL).fetch(
            TagDTO.self, .put, "tags/\(id.uuidString)", body: updateRequest
        )
        AppLogger.video.info("Updated tag: \(tagDTO.name)")
        return tagDTO.tagInfo
    }

    /// Deletes a tag from the server.
    /// - Parameters:
    ///   - id: The UUID of the tag to delete
    ///   - serverURL: The base server URL
    func deleteTag(id: UUID, serverURL: URL) async throws {
        try await api(serverURL).send(.delete, "tags/\(id.uuidString)")
        AppLogger.video.info("Deleted tag: \(id.uuidString)")
    }

    /// Attaches one tag to a video (idempotent, additive — contract §4).
    /// - Returns: The tag IDs now on the video, as reported by the server.
    @discardableResult
    func attachTag(fileId: String, tagId: UUID, serverURL: URL) async throws -> Set<UUID> {
        let tagsResponse = try await api(serverURL).fetch(
            CLVideoTagsResponse.self, .post, "videos/\(fileId)/tags/\(tagId.uuidString.lowercased())",
            expecting: [200, 201]
        )
        return Set(tagsResponse.tags.elements.map(\.id))
    }

    /// Detaches one tag from a video, leaving its other tags untouched.
    func detachTag(fileId: String, tagId: UUID, serverURL: URL) async throws {
        // 404: the tag was already detached (e.g. from another client).
        try await api(serverURL).send(
            .delete, "videos/\(fileId)/tags/\(tagId.uuidString.lowercased())",
            expecting: Set(200..<300).union([404])
        )
    }

    /// Adds and/or removes tags on many videos in one transaction
    /// (`POST /tags/apply`, contract §4). Existing tags not listed are kept.
    /// - Returns: The number of videos the server updated.
    @discardableResult
    func applyTagChanges(
        toFileIds fileIds: [String],
        addTagIds: [UUID],
        removeTagIds: [UUID] = [],
        serverURL: URL
    ) async throws -> Int {
        let client = api(serverURL)
        let data = try await client.send(
            .post, "tags/apply",
            body: BulkTagApplyRequest(fileIds: fileIds, addTagIds: addTagIds, removeTagIds: removeTagIds)
        )
        let result = try? client.decode(BulkTagApplyResponse.self, from: data)
        AppLogger.video.info("Applied tag changes to \(fileIds.count) videos (+\(addTagIds.count) -\(removeTagIds.count))")
        return result?.updated ?? fileIds.count
    }

    // MARK: - Rating Operations

    /// Sets the global rating for a video.
    func setRating(
        forVideoId videoId: String,
        rating: Int,
        serverURL: URL
    ) async throws {
        try await api(serverURL).send(.put, "videos/\(videoId)/rating", body: RatingRequest(rating: rating))
        AppLogger.video.info("Successfully set rating \(rating) for video \(videoId)")
    }

    /// Sets the rating for multiple videos.
    func setRatingBulk(
        forVideoIds videoIds: [String],
        rating: Int,
        serverURL: URL
    ) async throws {
        // Set rating for each video sequentially
        for videoId in videoIds {
            try await setRating(forVideoId: videoId, rating: rating, serverURL: serverURL)
        }
    }

    // MARK: - Per-Tag Rating Operations

    /// Sets the per-tag rating for a specific tag on a video.
    func setTagRating(forVideoId videoId: String, tagId: UUID, rating: Int, serverURL: URL) async throws {
        try await api(serverURL).send(
            .put, "videos/\(videoId)/tags/\(tagId.uuidString)/rating", body: RatingRequest(rating: rating)
        )
    }

    // MARK: - Source Directories

    /// Fetches all source directories for the filter dropdown.
    func fetchSourceDirectories(from serverURL: URL) async throws -> [SourceDirectoryDTO] {
        let dirResponse = try await api(serverURL).fetch(SourceDirectoriesResponse.self, "source-directories")
        AppLogger.video.debug("Fetched \(dirResponse.directories.count) source directories")
        return dirResponse.directories
    }

    // MARK: - Video Info

    /// Fetches video info for a single video by file ID.
    /// - Parameters:
    ///   - fileId: The unique file identifier of the video
    ///   - serverURL: The base server URL
    /// - Returns: The VideoItem if found, nil otherwise
    func fetchVideoInfo(forFileId fileId: String, serverURL: URL) async throws -> VideoItem? {
        try await api(serverURL).fetchIfPresent(VideoItem.self, "videos/by-file-id/\(fileId)")
    }

    // MARK: - Playback Stats

    /// Updates playback statistics for a video.
    /// - Parameters:
    ///   - fileId: The unique file identifier of the video
    ///   - incrementPlayCount: Whether to increment the play count by 1
    ///   - addViewTime: Seconds of view time to add
    ///   - serverURL: The base server URL
    /// - Returns: The updated playback stats from the server
    func updatePlaybackStats(
        fileId: String,
        incrementPlayCount: Bool,
        addViewTime: Int,
        serverURL: URL
    ) async throws -> PlaybackStatsDTO {
        AppLogger.playback.debug("Updating playback stats for \(fileId): increment=\(incrementPlayCount), addTime=\(addViewTime)")
        let statsResponse = try await api(serverURL).fetch(
            PlaybackStatsDTO.self, .post, "videos/\(fileId)/playback-stats",
            body: PlaybackStatsRequest(incrementPlayCount: incrementPlayCount, addViewTime: addViewTime)
        )
        AppLogger.playback.info("Updated playback stats for \(fileId): playCount=\(statsResponse.playCount), totalViewTime=\(statsResponse.totalViewTime)")
        return statsResponse
    }
}

// MARK: - Response Models (Sendable)

/// Response of `POST /videos/:fileId/tags/:tagId` (the video's tags).
struct CLVideoTagsResponse: Decodable, Sendable {
    struct TagRef: Decodable, Sendable {
        let id: UUID
    }

    let tags: LossyArray<TagRef>
}

extension TagDTO {
    var tagInfo: TagInfo {
        TagInfo(id: id, name: name, color: color, ratingEnabled: ratingEnabled)
    }
}

// MARK: - Source Directory Model

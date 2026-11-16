import Foundation

// MARK: - Videos

/// A catalog video as returned by `GET /api/v1/videos` and the video routes.
///
/// `id` is the database UUID; video-scoped routes use the stable,
/// content-derived `fileId`.
public struct VideoItem: Codable, Identifiable, Sendable {
    public let id: UUID
    public let fileId: String
    public let filename: String
    public let relativePath: String
    public let sourceDirectoryId: UUID
    public let duration: Double
    public let width: Int
    public let height: Int
    public let codec: String
    public let fileSize: Int64
    public let lastModified: Date
    public let rating: Int
    public let playCount: Int
    public let totalViewTime: Int
    public let lastPlayedAt: Date?
    public let annotationCount: Int
    public let tags: [TagSummary]?
    public let thumbnailUrl: String?
    public let sourceDirectoryName: String?

    private enum CodingKeys: String, CodingKey {
        case id, fileId, filename, relativePath, sourceDirectoryId, duration, width, height, codec
        case fileSize, lastModified, rating, playCount, totalViewTime, lastPlayedAt, annotationCount
        case tags, thumbnailUrl, sourceDirectoryName
    }

    public init(
        id: UUID = UUID(),
        fileId: String,
        filename: String,
        relativePath: String,
        sourceDirectoryId: UUID,
        duration: Double,
        width: Int,
        height: Int,
        codec: String,
        fileSize: Int64,
        lastModified: Date,
        rating: Int = 0,
        playCount: Int = 0,
        totalViewTime: Int = 0,
        lastPlayedAt: Date? = nil,
        annotationCount: Int = 0,
        tags: [TagSummary]? = nil,
        thumbnailUrl: String? = nil,
        sourceDirectoryName: String? = nil
    ) {
        self.id = id
        self.fileId = fileId
        self.filename = filename
        self.relativePath = relativePath
        self.sourceDirectoryId = sourceDirectoryId
        self.duration = duration
        self.width = width
        self.height = height
        self.codec = codec
        self.fileSize = fileSize
        self.lastModified = lastModified
        self.rating = rating
        self.playCount = playCount
        self.totalViewTime = totalViewTime
        self.lastPlayedAt = lastPlayedAt
        self.annotationCount = annotationCount
        self.tags = tags
        self.thumbnailUrl = thumbnailUrl
        self.sourceDirectoryName = sourceDirectoryName
    }

    /// Tolerant decoding: missing counters and rating read as 0.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileId = try container.decode(String.self, forKey: .fileId)
        filename = try container.decode(String.self, forKey: .filename)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        sourceDirectoryId = try container.decode(UUID.self, forKey: .sourceDirectoryId)
        duration = try container.decode(Double.self, forKey: .duration)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        codec = try container.decode(String.self, forKey: .codec)
        fileSize = try container.decode(Int64.self, forKey: .fileSize)
        lastModified = try container.decode(Date.self, forKey: .lastModified)
        rating = try container.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        playCount = try container.decodeIfPresent(Int.self, forKey: .playCount) ?? 0
        totalViewTime = try container.decodeIfPresent(Int.self, forKey: .totalViewTime) ?? 0
        lastPlayedAt = try container.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
        annotationCount = try container.decodeIfPresent(Int.self, forKey: .annotationCount) ?? 0
        tags = try container.decodeIfPresent([TagSummary].self, forKey: .tags)
        thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        sourceDirectoryName = try container.decodeIfPresent(String.self, forKey: .sourceDirectoryName)
    }
}

/// `GET /api/v1/videos`.
public struct PaginatedVideosResponse: Codable, Sendable {
    public let videos: [VideoItem]
    public let total: Int
    public let limit: Int
    public let offset: Int

    public init(videos: [VideoItem], total: Int, limit: Int, offset: Int) {
        self.videos = videos
        self.total = total
        self.limit = limit
        self.offset = offset
    }
}

// MARK: - Playback stats

/// Body of `POST /api/v1/videos/:fileId/playback-stats`.
public struct PlaybackStatsRequest: Codable, Sendable {
    public let incrementPlayCount: Bool
    public let addViewTime: Int

    public init(incrementPlayCount: Bool, addViewTime: Int) {
        self.incrementPlayCount = incrementPlayCount
        self.addViewTime = addViewTime
    }
}

/// Response of `POST /api/v1/videos/:fileId/playback-stats`.
public struct PlaybackStatsDTO: Codable, Sendable {
    public let playCount: Int
    public let totalViewTime: Int

    public init(playCount: Int, totalViewTime: Int) {
        self.playCount = playCount
        self.totalViewTime = totalViewTime
    }
}

// MARK: - Ratings

/// Body of `PUT /api/v1/videos/:fileId/rating` and
/// `PUT /api/v1/videos/:fileId/tags/:tagId/rating`.
public struct RatingRequest: Codable, Sendable {
    public let rating: Int

    public init(rating: Int) {
        self.rating = rating
    }
}

/// Response of the rating routes.
public struct RatingDTO: Codable, Sendable {
    public let rating: Int

    public init(rating: Int) {
        self.rating = rating
    }
}

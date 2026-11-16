import Foundation

// MARK: - Tags

/// A tag with its video count (`GET /api/v1/tags`, `/tags/:id`).
public struct TagDTO: Codable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let color: String
    public let description: String?
    public let ratingEnabled: Bool
    public let videoCount: Int
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        name: String,
        color: String,
        description: String?,
        ratingEnabled: Bool,
        videoCount: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.description = description
        self.ratingEnabled = ratingEnabled
        self.videoCount = videoCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Lightweight tag embedded in video responses.
public struct TagSummary: Codable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let color: String
    public let ratingEnabled: Bool
    /// Per-video tag rating (only present when the tag is attached to a video).
    public let rating: Int?

    public init(id: UUID, name: String, color: String, ratingEnabled: Bool, rating: Int? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.ratingEnabled = ratingEnabled
        self.rating = rating
    }
}

/// Body of `POST /api/v1/tags`.
public struct CreateTagRequest: Codable, Sendable {
    public let name: String
    public let color: String
    public let description: String?
    public let ratingEnabled: Bool?

    public init(name: String, color: String, description: String?, ratingEnabled: Bool?) {
        self.name = name
        self.color = color
        self.description = description
        self.ratingEnabled = ratingEnabled
    }
}

/// Body of `PUT /api/v1/tags/:id`.
public struct UpdateTagRequest: Codable, Sendable {
    public let name: String?
    public let color: String?
    public let description: String?
    public let ratingEnabled: Bool?

    public init(name: String?, color: String?, description: String?, ratingEnabled: Bool?) {
        self.name = name
        self.color = color
        self.description = description
        self.ratingEnabled = ratingEnabled
    }
}

/// Response of `DELETE /api/v1/tags/:id`.
public struct TagDeleteResponse: Codable, Sendable {
    public let success: Bool
    public let message: String
    public let affectedVideoCount: Int

    public init(success: Bool, message: String, affectedVideoCount: Int) {
        self.success = success
        self.message = message
        self.affectedVideoCount = affectedVideoCount
    }
}

/// `GET /api/v1/tags`.
public struct TagsResponse: Codable, Sendable {
    public let tags: [TagDTO]

    public init(tags: [TagDTO]) {
        self.tags = tags
    }
}

// MARK: - Video tags (contract §4)

/// Body of `POST /api/v1/videos/:fileId/tags` (replaces the full set) and of
/// the source-directory bulk tag route.
public struct ApplyTagsRequest: Codable, Sendable {
    public let tagIds: [UUID]

    public init(tagIds: [UUID]) {
        self.tagIds = tagIds
    }
}

/// A video's tags (`GET/POST /api/v1/videos/:fileId/tags[/:tagId]`).
public struct VideoTagsResponse: Codable, Sendable {
    public let tags: [TagSummary]

    public init(tags: [TagSummary]) {
        self.tags = tags
    }
}

/// Body of `POST /api/v1/tags/apply`.
///
/// Tag ids are encoded as lowercase UUID strings; decoding accepts any case.
public struct BulkTagApplyRequest: Codable, Sendable {
    public let fileIds: [String]
    public let addTagIds: [UUID]?
    public let removeTagIds: [UUID]?

    private enum CodingKeys: String, CodingKey {
        case fileIds, addTagIds, removeTagIds
    }

    public init(fileIds: [String], addTagIds: [UUID]?, removeTagIds: [UUID]?) {
        self.fileIds = fileIds
        self.addTagIds = addTagIds
        self.removeTagIds = removeTagIds
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fileIds, forKey: .fileIds)
        try container.encodeIfPresent(addTagIds.map(Self.lowercased), forKey: .addTagIds)
        try container.encodeIfPresent(removeTagIds.map(Self.lowercased), forKey: .removeTagIds)
    }

    private static func lowercased(_ ids: [UUID]) -> [String] {
        ids.map { $0.uuidString.lowercased() }
    }
}

/// Response of `POST /api/v1/tags/apply`: number of videos whose tags changed.
public struct BulkTagApplyResponse: Codable, Sendable {
    public let updated: Int

    public init(updated: Int) {
        self.updated = updated
    }
}

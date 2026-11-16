import Foundation

// MARK: - Sort order (contract §3)

/// Simple list sort orders. The canonical wire values are snake_case.
public enum SimpleListSortOrder: String, Codable, CaseIterable, Sendable {
    case filename = "filename"
    case filenameDesc = "filename_desc"
    case fileSize = "file_size"
    case fileSizeDesc = "file_size_desc"
    case playCount = "play_count"
    case playCountDesc = "play_count_desc"
    case playTime = "play_time"
    case playTimeDesc = "play_time_desc"
    case dateAdded = "date_added"
    case dateAddedDesc = "date_added_desc"

    /// The value stored when a client sends none.
    public static let defaultValue = SimpleListSortOrder.filename.rawValue

    /// Every canonical value, in declaration order.
    public static let canonicalValues = allCases.map(\.rawValue)

    /// Server validation: the canonical value for `value` (canonical or a
    /// camelCase alias such as `filenameDesc`), nil if unknown.
    public static func canonical(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if canonicalValues.contains(trimmed) {
            return trimmed
        }
        var snake = ""
        for character in trimmed {
            if character.isUppercase {
                snake.append("_")
                snake.append(contentsOf: character.lowercased())
            } else {
                snake.append(character)
            }
        }
        return canonicalValues.contains(snake) ? snake : nil
    }

    /// Client decoding: maps canonical snake_case, camelCase aliases and any
    /// casing to a sort order; unknown values become `.filename`, so one odd
    /// value never fails a whole list.
    public init(lenient raw: String) {
        if let exact = SimpleListSortOrder(rawValue: raw) {
            self = exact
            return
        }
        let normalized = raw.lowercased().filter { $0.isLetter }
        self = SimpleListSortOrder.allCases.first {
            $0.rawValue.replacingOccurrences(of: "_", with: "") == normalized
        } ?? .filename
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SimpleListSortOrder(lenient: raw)
    }
}

// MARK: - Simple lists

/// A simple (hand-picked) list of videos, by `fileId`.
public struct SimpleListDTO: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public var videoIds: [String]
    public let videoCount: Int
    public let sortOrder: SimpleListSortOrder
    public let createdAt: Date
    public let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, name, videoIds, videoCount, sortOrder, createdAt, updatedAt
    }

    public init(
        id: UUID = UUID(),
        name: String,
        videoIds: [String] = [],
        videoCount: Int? = nil,
        sortOrder: SimpleListSortOrder = .filename,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.videoIds = videoIds
        self.videoCount = videoCount ?? videoIds.count
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Tolerant decoding: a missing `videoIds`, `videoCount`, `sortOrder` or
    /// date never fails the list.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        videoIds = try container.decodeIfPresent([String].self, forKey: .videoIds) ?? []
        videoCount = try container.decodeIfPresent(Int.self, forKey: .videoCount) ?? videoIds.count
        sortOrder = try container.decodeIfPresent(SimpleListSortOrder.self, forKey: .sortOrder) ?? .filename
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

/// Body of `POST /api/v1/simple-lists`. `sortOrder` is validated by the server.
public struct CreateSimpleListRequest: Codable, Sendable {
    public let name: String
    public let sortOrder: String?

    public init(name: String, sortOrder: String? = nil) {
        self.name = name
        self.sortOrder = sortOrder
    }
}

/// Body of `PUT /api/v1/simple-lists/:id`. `sortOrder` is validated by the server.
public struct UpdateSimpleListRequest: Codable, Sendable {
    public let name: String?
    public let sortOrder: String?

    public init(name: String?, sortOrder: String?) {
        self.name = name
        self.sortOrder = sortOrder
    }
}

/// Body of `POST /api/v1/simple-lists/:id/videos` and the matching DELETE.
public struct AddVideosRequest: Codable, Sendable {
    public let videoIds: [String]

    public init(videoIds: [String]) {
        self.videoIds = videoIds
    }
}

/// Response of `DELETE /api/v1/simple-lists/:id`.
public struct SimpleListDeleteResponse: Codable, Sendable {
    public let success: Bool
    public let message: String

    public init(success: Bool, message: String) {
        self.success = success
        self.message = message
    }
}

/// `GET /api/v1/simple-lists`.
public struct SimpleListsResponse: Codable, Sendable {
    public let simpleLists: [SimpleListDTO]

    public init(simpleLists: [SimpleListDTO]) {
        self.simpleLists = simpleLists
    }
}

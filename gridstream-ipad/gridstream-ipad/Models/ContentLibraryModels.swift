//
//  ContentLibraryModels.swift
//  gridstream-ipad
//

import Foundation
import GridStreamAPI
import SwiftUI

// MARK: - Tag Information

/// Represents tag information for display in the Content Library
struct TagInfo: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let name: String
    let color: String
    let ratingEnabled: Bool
    let videoCount: Int

    nonisolated var swiftUIColor: Color {
        Color(hex: color) ?? .gray
    }

    /// Creates a TagInfo from a TagSummary (from API response).
    init(from summary: TagSummary) {
        self.id = summary.id
        self.name = summary.name
        self.color = summary.color
        self.ratingEnabled = summary.ratingEnabled
        self.videoCount = 0
    }

    init(id: UUID, name: String, color: String, ratingEnabled: Bool, videoCount: Int = 0) {
        self.id = id
        self.name = name
        self.color = color
        self.ratingEnabled = ratingEnabled
        self.videoCount = videoCount
    }

    /// Converts an array of TagSummary to TagInfo.
    static func from(_ summaries: [TagSummary]?) -> [TagInfo] {
        guard let summaries = summaries else { return [] }
        return summaries.map { TagInfo(from: $0) }
    }

    /// Converts an array of TagSummary to TagInfo and extracts per-tag ratings.
    /// Returns a tuple of (tags, tagRatings dictionary).
    static func fromWithRatings(_ summaries: [TagSummary]?) -> (tags: [TagInfo], tagRatings: [UUID: Int]) {
        guard let summaries = summaries else { return ([], [:]) }
        var tags: [TagInfo] = []
        var tagRatings: [UUID: Int] = [:]

        for summary in summaries {
            tags.append(TagInfo(from: summary))
            // Only include rating if the tag has rating enabled and a rating value exists
            if summary.ratingEnabled, let rating = summary.rating {
                tagRatings[summary.id] = rating
            }
        }

        return (tags, tagRatings)
    }
}

// MARK: - Tag Filter

/// Represents a tag filter with optional rating range
struct TagFilter: Equatable, Hashable, Sendable {
    let tag: TagInfo
    var minRating: Int?
    var maxRating: Int?

    var hasRatingFilter: Bool {
        minRating != nil || maxRating != nil
    }

    var displayText: String {
        if let min = minRating, let max = maxRating {
            if min == max {
                return "\(tag.name) ♥\(min)"
            }
            return "\(tag.name) ♥\(min)-\(max)"
        } else if let min = minRating {
            return "\(tag.name) ♥\(min)+"
        } else if let max = maxRating {
            return "\(tag.name) ♥≤\(max)"
        }
        return tag.name
    }

    init(tag: TagInfo, minRating: Int? = nil, maxRating: Int? = nil) {
        self.tag = tag
        self.minRating = minRating
        self.maxRating = maxRating
    }

    init(tag: TagInfo) {
        self.tag = tag
        self.minRating = nil
        self.maxRating = nil
    }
}

// MARK: - Filter Chip

/// Represents a removable filter chip in the Content Library
enum FilterChip: Identifiable, Equatable, Sendable {
    case tagFilter(TagFilter)
    case minRating(value: Int)
    case maxRating(value: Int)
    case sourceDirectory(id: String, name: String)
    case search(text: String)
    case unplayed
    case played
    case minPlayCount(value: Int)
    case unrated
    case hasAnnotations(value: Bool)
    case annotationCountMin(value: Int)
    case annotationCountMax(value: Int)
    case hasTextAnnotations(value: Bool)
    case annotationTextSearch(text: String)

    var id: String {
        switch self {
        case .tagFilter(let filter):
            return "tag-\(filter.tag.id.uuidString)"
        case .minRating(let value):
            return "minRating-\(value)"
        case .maxRating(let value):
            return "maxRating-\(value)"
        case .sourceDirectory(let id, _):
            return "sourceDir-\(id)"
        case .search(let text):
            return "search-\(text)"
        case .unplayed:
            return "unplayed"
        case .played:
            return "played"
        case .minPlayCount(let value):
            return "minPlayCount-\(value)"
        case .unrated:
            return "unrated"
        case .hasAnnotations(let value):
            return "hasAnnotations-\(value)"
        case .annotationCountMin(let value):
            return "annotationCountMin-\(value)"
        case .annotationCountMax(let value):
            return "annotationCountMax-\(value)"
        case .hasTextAnnotations(let value):
            return "hasTextAnnotations-\(value)"
        case .annotationTextSearch(let text):
            return "annotationTextSearch-\(text)"
        }
    }

    var displayText: String {
        switch self {
        case .tagFilter(let filter):
            return filter.displayText
        case .minRating(let value):
            return String(localized: "Min: \(value) hearts")
        case .maxRating(let value):
            return String(localized: "Max: \(value) hearts")
        case .sourceDirectory(_, let name):
            return name
        case .search(let text):
            return "\"\(text)\""
        case .unplayed:
            return String(localized: "Unplayed")
        case .played:
            return String(localized: "Played")
        case .minPlayCount(let value):
            return String(localized: "Played \(value)+ times")
        case .unrated:
            return String(localized: "Unrated")
        case .hasAnnotations(let value):
            return value ? String(localized: "Has Annotations") : String(localized: "No Annotations")
        case .annotationCountMin(let value):
            return String(localized: "Annotations \(value)+")
        case .annotationCountMax(let value):
            return String(localized: "Annotations ≤\(value)")
        case .hasTextAnnotations(let value):
            return value ? String(localized: "Has Text Annotation") : String(localized: "No Text Annotation")
        case .annotationTextSearch(let text):
            return String(localized: "Annotation text: \"\(text)\"")
        }
    }

    var color: Color {
        switch self {
        case .tagFilter(let filter):
            return filter.tag.swiftUIColor
        case .minRating, .maxRating:
            return .orange
        case .sourceDirectory:
            return .blue
        case .search:
            return .purple
        case .unplayed, .played, .minPlayCount:
            return .teal
        case .unrated:
            return .orange
        case .hasAnnotations, .annotationCountMin, .annotationCountMax, .hasTextAnnotations, .annotationTextSearch:
            return .indigo
        }
    }
}

// MARK: - Content Library Filters

/// Holds all active filter state for the Content Library
struct ContentLibraryFilters: Equatable, Sendable {
    var searchText: String = ""
    var activeTagFilters: [TagFilter] = []
    var minRating: Int?
    var maxRating: Int?
    var sourceDirectoryId: String?
    var sourceDirectoryName: String?
    var minPlayCount: Int?
    var unplayedOnly: Bool = false
    var playedOnly: Bool = false
    var unratedOnly: Bool = false
    var hasAnnotations: Bool?
    var minAnnotationCount: Int?
    var maxAnnotationCount: Int?
    var hasTextAnnotations: Bool?
    var annotationTextSearch: String = ""
    var videoIds: [String]?

    nonisolated init(
        searchText: String = "",
        activeTagFilters: [TagFilter] = [],
        minRating: Int? = nil,
        maxRating: Int? = nil,
        sourceDirectoryId: String? = nil,
        sourceDirectoryName: String? = nil,
        minPlayCount: Int? = nil,
        unplayedOnly: Bool = false,
        playedOnly: Bool = false,
        unratedOnly: Bool = false,
        hasAnnotations: Bool? = nil,
        minAnnotationCount: Int? = nil,
        maxAnnotationCount: Int? = nil,
        hasTextAnnotations: Bool? = nil,
        annotationTextSearch: String = "",
        videoIds: [String]? = nil
    ) {
        self.searchText = searchText
        self.activeTagFilters = activeTagFilters
        self.minRating = minRating
        self.maxRating = maxRating
        self.sourceDirectoryId = sourceDirectoryId
        self.sourceDirectoryName = sourceDirectoryName
        self.minPlayCount = minPlayCount
        self.unplayedOnly = unplayedOnly
        self.playedOnly = playedOnly
        self.unratedOnly = unratedOnly
        self.hasAnnotations = hasAnnotations
        self.minAnnotationCount = minAnnotationCount
        self.maxAnnotationCount = maxAnnotationCount
        self.hasTextAnnotations = hasTextAnnotations
        self.annotationTextSearch = annotationTextSearch
        self.videoIds = videoIds
    }

    var hasActiveFilters: Bool {
        !searchText.isEmpty ||
        !activeTagFilters.isEmpty ||
        minRating != nil ||
        maxRating != nil ||
        sourceDirectoryId != nil ||
        minPlayCount != nil ||
        unplayedOnly ||
        playedOnly ||
        unratedOnly ||
        hasAnnotations != nil ||
        minAnnotationCount != nil ||
        maxAnnotationCount != nil ||
        hasTextAnnotations != nil ||
        !annotationTextSearch.isEmpty ||
        (videoIds != nil && !videoIds!.isEmpty)
    }

    var activeChips: [FilterChip] {
        var chips: [FilterChip] = []

        if !searchText.isEmpty {
            chips.append(.search(text: searchText))
        }

        for tagFilter in activeTagFilters {
            chips.append(.tagFilter(tagFilter))
        }

        if let min = minRating {
            chips.append(.minRating(value: min))
        }

        if let max = maxRating {
            chips.append(.maxRating(value: max))
        }

        if let dirId = sourceDirectoryId, let dirName = sourceDirectoryName {
            chips.append(.sourceDirectory(id: dirId, name: dirName))
        }

        if unplayedOnly {
            chips.append(.unplayed)
        }

        if playedOnly {
            chips.append(.played)
        }

        if unratedOnly {
            chips.append(.unrated)
        }

        if let minPlay = minPlayCount {
            chips.append(.minPlayCount(value: minPlay))
        }

        if let hasAnno = hasAnnotations {
            chips.append(.hasAnnotations(value: hasAnno))
        }

        if let minAnno = minAnnotationCount {
            chips.append(.annotationCountMin(value: minAnno))
        }

        if let maxAnno = maxAnnotationCount {
            chips.append(.annotationCountMax(value: maxAnno))
        }

        if let hasTextAnno = hasTextAnnotations {
            chips.append(.hasTextAnnotations(value: hasTextAnno))
        }

        if !annotationTextSearch.isEmpty {
            chips.append(.annotationTextSearch(text: annotationTextSearch))
        }

        return chips
    }

    mutating func removeChip(_ chip: FilterChip) {
        switch chip {
        case .tagFilter(let filter):
            activeTagFilters.removeAll { $0.tag.id == filter.tag.id }
        case .minRating:
            minRating = nil
        case .maxRating:
            maxRating = nil
        case .sourceDirectory:
            sourceDirectoryId = nil
            sourceDirectoryName = nil
        case .search:
            searchText = ""
        case .unplayed:
            unplayedOnly = false
        case .played:
            playedOnly = false
        case .minPlayCount:
            minPlayCount = nil
        case .unrated:
            unratedOnly = false
        case .hasAnnotations:
            hasAnnotations = nil
        case .annotationCountMin:
            minAnnotationCount = nil
        case .annotationCountMax:
            maxAnnotationCount = nil
        case .hasTextAnnotations:
            hasTextAnnotations = nil
        case .annotationTextSearch:
            annotationTextSearch = ""
        }
    }

    mutating func clear() {
        searchText = ""
        activeTagFilters = []
        minRating = nil
        maxRating = nil
        sourceDirectoryId = nil
        sourceDirectoryName = nil
        minPlayCount = nil
        unplayedOnly = false
        playedOnly = false
        unratedOnly = false
        hasAnnotations = nil
        minAnnotationCount = nil
        maxAnnotationCount = nil
        hasTextAnnotations = nil
        annotationTextSearch = ""
        videoIds = nil
    }
}

// MARK: - Sort Option

/// Sort options for the Content Library
enum ContentLibrarySortOption: String, CaseIterable, Identifiable {
    case filenameAsc = "filename_asc"
    case filenameDesc = "filename_desc"
    case ratingAsc = "rating_asc"
    case ratingDesc = "rating_desc"
    case playCountAsc = "playCount_asc"
    case playCountDesc = "playCount_desc"
    case lastPlayedDesc = "lastPlayed_desc"
    case lastPlayedAsc = "lastPlayed_asc"

    var id: String { rawValue }

    var displayText: LocalizedStringResource {
        switch self {
        case .filenameAsc:
            return "Filename (A-Z)"
        case .filenameDesc:
            return "Filename (Z-A)"
        case .ratingAsc:
            return "Rating (Low to High)"
        case .ratingDesc:
            return "Rating (High to Low)"
        case .playCountAsc:
            return "Least Played"
        case .playCountDesc:
            return "Most Played"
        case .lastPlayedDesc:
            return "Recently Played"
        case .lastPlayedAsc:
            return "Least Recently Played"
        }
    }

    var icon: String {
        switch self {
        case .filenameAsc, .filenameDesc:
            return "textformat.abc"
        case .ratingAsc, .ratingDesc:
            return "heart.fill"
        case .playCountAsc, .playCountDesc:
            return "play.fill"
        case .lastPlayedDesc, .lastPlayedAsc:
            return "clock.arrow.circlepath"
        }
    }
}

// MARK: - Rating Info

/// Represents rating information for a video
struct VideoRatingInfo: Equatable {
    var globalRating: Int
    var tagRatings: [UUID: Int]

    init(globalRating: Int = 0, tagRatings: [UUID: Int] = [:]) {
        self.globalRating = globalRating
        self.tagRatings = tagRatings
    }
}

// MARK: - Heart Rating Size

/// Size configuration for the HeartRatingView
enum HeartRatingSize {
    case large
    case small

    var heartSize: CGFloat {
        switch self {
        case .large: return 24
        case .small: return 16
        }
    }

    var spacing: CGFloat {
        switch self {
        case .large: return 4
        case .small: return 2
        }
    }
}

// MARK: - Color Extension for Hex

extension Color {
    nonisolated init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Content Library Filter Cache

@MainActor
final class ContentLibraryFilterCache {
    static let shared = ContentLibraryFilterCache()

    private(set) var cachedFilters: ContentLibraryFilters?

    private init() {}

    func save(_ filters: ContentLibraryFilters) {
        guard filters.hasActiveFilters else {
            cachedFilters = nil
            return
        }
        cachedFilters = filters
    }

    func restore() -> ContentLibraryFilters? {
        cachedFilters
    }

    func clear() {
        cachedFilters = nil
    }
}

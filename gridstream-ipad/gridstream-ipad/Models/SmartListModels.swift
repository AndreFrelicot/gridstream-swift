//
//  SmartListModels.swift
//  gridstream-ipad
//

import Foundation
import GridStreamAPI

// MARK: - Smart List Info

/// Represents smart list information for display in the iPad app
struct SmartListInfo: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    let name: String
    let criteria: SmartListCriteria
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        criteria: SmartListCriteria,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.criteria = criteria
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Smart List Criteria

extension SmartListCriteria {
    /// Returns a human-readable summary of the criteria
    var summary: LocalizedStringResource {
        guard !conditions.isEmpty else {
            return "No filters"
        }

        if conditions.count == 1 {
            return conditions[0].criteriaType.displayName
        }

        return "\(conditions.count) filters"
    }
}

// MARK: - Logic Operator

extension LogicOperator {
    var displayName: String {
        rawValue
    }
}

// MARK: - Tag Rating Filter

extension TagRatingFilter {
    var hasRatingFilter: Bool {
        minRating != nil || maxRating != nil
    }
}

// MARK: - Criteria Type

extension CriteriaType {
    /// Human-readable name for the criteria type
    var displayName: LocalizedStringResource {
        switch self {
        case .tagsInclude:
            return "Tags Include"
        case .tagsExclude:
            return "Tags Exclude"
        case .ratingMin:
            return "Min Rating"
        case .ratingMax:
            return "Max Rating"
        case .sourceDirectory:
            return "Source Directory"
        case .fileSizeMin:
            return "Min File Size"
        case .fileSizeMax:
            return "Max File Size"
        case .filenameContains:
            return "Filename Contains"
        case .filenameStartsWith:
            return "Filename Starts With"
        case .filenameEndsWith:
            return "Filename Ends With"
        case .filenameRegex:
            return "Filename Matches"
        case .dateAddedAfter:
            return "Added After"
        case .dateAddedBefore:
            return "Added Before"
        case .dateModifiedAfter:
            return "Modified After"
        case .dateModifiedBefore:
            return "Modified Before"
        case .playCountMin:
            return "Min Play Count"
        case .playCountMax:
            return "Max Play Count"
        case .hasAnnotations(let value):
            return value ? "Has Annotations" : "No Annotations"
        case .annotationCountMin:
            return "Min Annotation Count"
        case .annotationCountMax:
            return "Max Annotation Count"
        case .hasTextAnnotations(let value):
            return value ? "Has Text Annotation" : "No Text Annotation"
        case .annotationTextSearch:
            return "Annotation Text Search"
        case .hasTimeRanges(let value):
            return value ? "Has Segments" : "No Segments"
        case .unrated:
            return "Unrated"
        case .unplayed:
            return "Unplayed"
        case .simpleListInclude:
            return "In Simple List"
        case .smartListInclude:
            return "In Smart List"
        }
    }

    /// Category for grouping related criteria types
    var category: CriteriaCategory {
        switch self {
        case .tagsInclude, .tagsExclude:
            return .tags
        case .ratingMin, .ratingMax, .unrated:
            return .rating
        case .sourceDirectory:
            return .source
        case .fileSizeMin, .fileSizeMax:
            return .fileSize
        case .filenameContains, .filenameStartsWith, .filenameEndsWith, .filenameRegex:
            return .filename
        case .dateAddedAfter, .dateAddedBefore, .dateModifiedAfter, .dateModifiedBefore:
            return .date
        case .playCountMin, .playCountMax, .unplayed:
            return .playCount
        case .hasAnnotations, .annotationCountMin, .annotationCountMax, .hasTextAnnotations, .annotationTextSearch:
            return .annotations
        case .hasTimeRanges:
            return .segments
        case .simpleListInclude:
            return .simpleList
        case .smartListInclude:
            return .smartList
        }
    }
}

// MARK: - Criteria Category

/// Categories for grouping related criteria types
enum CriteriaCategory: String, CaseIterable {
    case tags = "Tags"
    case rating = "Rating"
    case source = "Source"
    case fileSize = "File Size"
    case filename = "Filename"
    case date = "Date"
    case playCount = "Play Count"
    case annotations = "Annotations"
    case segments = "Segments"
    case simpleList = "Simple List"
    case smartList = "Smart List"

    var displayName: LocalizedStringResource {
        switch self {
        case .tags: return "Tags"
        case .rating: return "Rating"
        case .source: return "Source"
        case .fileSize: return "File Size"
        case .filename: return "Filename"
        case .date: return "Date"
        case .playCount: return "Play Count"
        case .annotations: return "Annotations"
        case .segments: return "Segments"
        case .simpleList: return "Simple List"
        case .smartList: return "Smart List"
        }
    }
}

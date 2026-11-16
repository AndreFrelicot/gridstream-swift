//
//  SmartListQueryBuilder.swift
//  gridstream-ipad
//
//  Smart List criteria queries used when a tag is about to be deleted.
//

import Foundation
import GridStreamAPI

/// Finds the Smart Lists whose criteria reference a tag.
enum SmartListQueryBuilder {

    // MARK: - Smart List Tag Queries

    /// Checks if a Smart List contains references to a specific tag.
    /// - Parameters:
    ///   - smartList: The Smart List to check
    ///   - tagId: The tag ID to search for
    /// - Returns: True if the Smart List references the tag
    static func smartListContainsTag(_ smartList: SmartListInfo, tagId: UUID) -> Bool {
        for condition in smartList.criteria.conditions {
            switch condition.criteriaType {
            case .tagsInclude(let tagIds, _), .tagsExclude(let tagIds):
                if tagIds.contains(tagId) {
                    return true
                }
            default:
                continue
            }
        }
        return false
    }

    /// Finds all Smart Lists that reference a specific tag.
    /// - Parameters:
    ///   - smartLists: Array of Smart Lists to search
    ///   - tagId: The tag ID to search for
    /// - Returns: Array of Smart Lists that reference the tag
    static func findSmartListsContainingTag(_ smartLists: [SmartListInfo], tagId: UUID) -> [SmartListInfo] {
        return smartLists.filter { smartListContainsTag($0, tagId: tagId) }
    }
}

//
//  SimpleListModels.swift
//  gridstream-ipad
//

import Foundation
import GridStreamAPI

// MARK: - Simple List Sort Order

extension SimpleListSortOrder {
    var displayName: LocalizedStringResource {
        switch self {
        case .filename:
            return "Filename (A-Z)"
        case .filenameDesc:
            return "Filename (Z-A)"
        case .fileSize:
            return "File Size (Smallest)"
        case .fileSizeDesc:
            return "File Size (Largest)"
        case .playCount:
            return "Play Count (Lowest)"
        case .playCountDesc:
            return "Play Count (Highest)"
        case .playTime:
            return "Play Time (Shortest)"
        case .playTimeDesc:
            return "Play Time (Longest)"
        case .dateAdded:
            return "Date Added (Oldest)"
        case .dateAddedDesc:
            return "Date Added (Newest)"
        }
    }
}

// MARK: - Simple List

extension SimpleListDTO {
    var isEmpty: Bool {
        videoIds.isEmpty
    }
}

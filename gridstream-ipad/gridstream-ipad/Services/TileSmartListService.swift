//
//  TileSmartListService.swift
//  gridstream-ipad
//
//  Handles video fetching for tiles based on their attached Smart List.
//  Coordinates with SmartListService and ContentLibraryService to filter
//  videos according to Smart List criteria.
//

import Foundation
import GridStreamAPI
import OSLog

/// Result of fetching videos for a tile with Smart List filtering.
struct TileVideoFetchResult: Sendable {
    let tileIndex: Int
    let videos: [VideoItem]
    let total: Int
    let smartListId: UUID?
    let isEmpty: Bool
}

/// Service for fetching videos for tiles with Smart List integration.
/// When a tile has an attached Smart List, videos are filtered according
/// to the Smart List's criteria.
@MainActor
final class TileSmartListService {
    private let contentLibraryService: ContentLibraryService
    private let smartListService: SmartListService

    init(
        contentLibraryService: ContentLibraryService,
        smartListService: SmartListService
    ) {
        self.contentLibraryService = contentLibraryService
        self.smartListService = smartListService
    }

    convenience init() {
        self.init(contentLibraryService: ContentLibraryService(), smartListService: SmartListService())
    }

    // Explicit teardown avoids the isolated-deinit back-deploy shim when
    // SwiftUI releases this service outside a Swift task.
    deinit {}

    // MARK: - Fetch Videos for Tile

    /// Fetches videos for a tile, applying Smart List filters if attached.
    /// - Parameters:
    ///   - tileIndex: The index of the tile
    ///   - smartListId: Optional Smart List UUID to filter by
    ///   - smartLists: Current list of Smart Lists for criteria lookup
    ///   - serverURL: The base server URL
    /// - Returns: TileVideoFetchResult with videos and metadata
    func fetchVideosForTile(
        tileIndex: Int,
        smartListId: UUID?,
        smartLists: [SmartListInfo],
        serverURL: URL
    ) async throws -> TileVideoFetchResult {
        // If no Smart List attached, return indication of full catalog behavior
        guard let smartListId = smartListId else {
            return TileVideoFetchResult(
                tileIndex: tileIndex,
                videos: [],
                total: 0,
                smartListId: nil,
                isEmpty: false // No Smart List means full catalog, not empty
            )
        }

        // Find the Smart List
        guard let smartList = smartLists.first(where: { $0.id == smartListId }) else {
            AppLogger.video.warning("Smart List \(smartListId.uuidString) not found for tile \(tileIndex)")
            return TileVideoFetchResult(
                tileIndex: tileIndex,
                videos: [],
                total: 0,
                smartListId: smartListId,
                isEmpty: true
            )
        }

        // Fetch videos with Smart List criteria
        let result = try await contentLibraryService.fetchVideosWithSmartListCriteria(
            from: serverURL,
            criteria: smartList.criteria
        )

        AppLogger.video.debug("Fetched \(result.videos.count) videos for tile \(tileIndex) with Smart List '\(smartList.name)'")

        return TileVideoFetchResult(
            tileIndex: tileIndex,
            videos: result.videos,
            total: result.total,
            smartListId: smartListId,
            isEmpty: result.videos.isEmpty
        )
    }

    // MARK: - Smart List Change Detection

    /// Picks a random video from the Smart List filtered results for a tile.
    /// - Parameters:
    ///   - smartListId: The Smart List UUID
    ///   - smartLists: Current list of Smart Lists
    ///   - serverURL: The base server URL
    /// - Returns: A random VideoItem from the filtered results, or nil if empty
    func pickRandomVideoForSmartList(
        smartListId: UUID,
        smartLists: [SmartListInfo],
        serverURL: URL
    ) async throws -> VideoItem? {
        guard let smartList = smartLists.first(where: { $0.id == smartListId }) else {
            return nil
        }

        let result = try await contentLibraryService.fetchVideosWithSmartListCriteria(
            from: serverURL,
            criteria: smartList.criteria
        )

        guard !result.videos.isEmpty else {
            return nil
        }

        return result.videos.randomElement()
    }
}

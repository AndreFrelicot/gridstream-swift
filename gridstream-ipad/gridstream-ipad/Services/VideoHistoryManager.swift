//
//  VideoHistoryManager.swift
//  gridstream-ipad
//

import Foundation
import GridStreamAPI
import OSLog

/// Manages video catalog and provides random video selection for tiles.
/// Also maintains per-tile video navigation history.
@Observable
final class VideoHistoryManager {
    /// Cached list of available videos from the server
    private(set) var availableVideos: [VideoItem] = []

    /// Per-tile video history, keyed by tile index
    private var tileHistories: [Int: TileVideoHistory] = [:]

    /// Server URL for fetching videos
    private var serverURL: URL?

    /// The video API service
    private let apiService = VideoAPIService()

    // MARK: - Video List Management

    /// Sets the server URL and optionally fetches videos
    func configure(serverURL: URL) async {
        self.serverURL = serverURL
        await refreshVideoList()
    }

    /// Refreshes the video list from the server
    func refreshVideoList() async {
        guard let serverURL = serverURL else {
            AppLogger.video.warning("Cannot refresh video list: no server URL configured")
            return
        }

        do {
            let videos = try await apiService.fetchVideos(from: serverURL)
            await MainActor.run {
                self.availableVideos = videos
            }
            AppLogger.video.info("Loaded \(videos.count) videos for random selection")
        } catch {
            AppLogger.video.error("Failed to load video list: \(error.localizedDescription)")
        }
    }

    // MARK: - Random Video Selection

    /// Selects a random video from the available list
    /// - Parameter excluding: Optional file ID (`VideoItem.fileId`, what tiles
    ///   store as `videoId`) to exclude from selection (to avoid repeating)
    /// - Returns: A random VideoItem, or nil if no videos available
    func randomVideo(excluding currentVideoId: String? = nil) -> VideoItem? {
        guard !availableVideos.isEmpty else {
            AppLogger.video.warning("Cannot select random video: no videos available")
            return nil
        }

        // Filter out the current video if specified. Tiles identify videos
        // by file ID; comparing against the database UUID excluded nothing.
        let candidates: [VideoItem]
        if let excludeId = currentVideoId, availableVideos.count > 1 {
            candidates = availableVideos.filter { $0.fileId != excludeId }
        } else {
            candidates = availableVideos
        }

        guard let selected = candidates.randomElement() else {
            return availableVideos.randomElement()
        }

        AppLogger.video.debug("Selected random video: \(selected.filename)")
        return selected
    }

    // MARK: - Tile History Management

    /// Gets or creates the history for a specific tile
    func history(forTile index: Int) -> TileVideoHistory {
        if let existing = tileHistories[index] {
            return existing
        }

        let history = TileVideoHistory()
        tileHistories[index] = history
        return history
    }

    /// Clears history for a specific tile
    func clearHistory(forTile index: Int) {
        tileHistories[index]?.clear()
        tileHistories.removeValue(forKey: index)
    }

    /// Clears all tile histories
    func clearAllHistories() {
        for (_, history) in tileHistories {
            history.clear()
        }
        tileHistories.removeAll()
    }

    /// Reindexes histories when tiles are removed or reordered
    func reindexHistories(newIndices: [Int: Int]) {
        var newHistories: [Int: TileVideoHistory] = [:]
        for (oldIndex, newIndex) in newIndices {
            if let history = tileHistories[oldIndex] {
                newHistories[newIndex] = history
            }
        }
        tileHistories = newHistories
    }

    // MARK: - Convenience Methods

    /// Builds a stream URL for a video
    func buildStreamURL(for video: VideoItem) -> URL? {
        guard let serverURL = serverURL else { return nil }
        return VideoURLBuilder.buildStreamURL(from: serverURL, videoId: video.fileId)
    }

    /// Gets the current server URL
    var currentServerURL: URL? {
        serverURL
    }
}

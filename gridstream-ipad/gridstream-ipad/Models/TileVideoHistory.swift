//
//  TileVideoHistory.swift
//  gridstream-ipad
//

import CoreGraphics
import Foundation
import OSLog

/// Represents a single entry in the video history stack
struct VideoHistoryEntry: Identifiable, Equatable {
    let id: UUID
    let videoId: String
    let videoURL: URL
    var lastFrame: CGImage?
    var playbackTime: Double
    var playCount: Int
    var totalViewTime: Int
    let timestamp: Date

    init(
        videoId: String,
        videoURL: URL,
        lastFrame: CGImage? = nil,
        playbackTime: Double = 0,
        playCount: Int = 0,
        totalViewTime: Int = 0
    ) {
        self.id = UUID()
        self.videoId = videoId
        self.videoURL = videoURL
        self.lastFrame = lastFrame
        self.playbackTime = playbackTime
        self.playCount = playCount
        self.totalViewTime = totalViewTime
        self.timestamp = Date()
    }

    static func == (lhs: VideoHistoryEntry, rhs: VideoHistoryEntry) -> Bool {
        lhs.id == rhs.id
    }
}

/// Manages video navigation history for a single tile
/// Supports back/forward navigation with frame snapshots for transitions
@Observable
final class TileVideoHistory {
    /// Maximum number of entries to keep in history
    private static let maxHistorySize = 20

    /// The history stack of video entries
    private(set) var entries: [VideoHistoryEntry] = []

    /// Current position in the history stack (-1 means no history)
    private(set) var currentIndex: Int = -1

    /// Returns true if we can navigate to a previous video
    var canGoBack: Bool {
        currentIndex > 0
    }

    /// Returns true if we can navigate to a next video (forward in history)
    var canGoForward: Bool {
        currentIndex < entries.count - 1 && currentIndex >= 0
    }

    /// The current video entry, if any
    var currentEntry: VideoHistoryEntry? {
        guard currentIndex >= 0, currentIndex < entries.count else { return nil }
        return entries[currentIndex]
    }

    /// The previous video entry (for transition animation)
    var previousEntry: VideoHistoryEntry? {
        guard currentIndex > 0 else { return nil }
        return entries[currentIndex - 1]
    }

    /// The next video entry in history (for transition animation)
    var nextEntry: VideoHistoryEntry? {
        guard currentIndex < entries.count - 1, currentIndex >= 0 else { return nil }
        return entries[currentIndex + 1]
    }

    // MARK: - Navigation

    /// Pushes a new video onto the history stack
    /// If we're not at the end of history, truncates forward history
    /// - Parameters:
    ///   - videoId: The video ID
    ///   - videoURL: The video URL
    ///   - capturedFrameFromPrevious: Optional frame snapshot from the previous video
    ///   - playbackTimeFromPrevious: Optional playback position from the previous video
    func push(
        videoId: String,
        videoURL: URL,
        capturedFrameFromPrevious: CGImage? = nil,
        playbackTimeFromPrevious: Double? = nil,
        playCount: Int = 0,
        totalViewTime: Int = 0
    ) {
        // Update the last frame and playback time of the current entry before pushing
        if currentIndex >= 0, currentIndex < entries.count {
            if let frame = capturedFrameFromPrevious {
                entries[currentIndex].lastFrame = frame
            }
            if let time = playbackTimeFromPrevious {
                entries[currentIndex].playbackTime = time
            }
        }

        // Truncate any forward history when pushing new entry
        if currentIndex < entries.count - 1 && currentIndex >= 0 {
            entries = Array(entries.prefix(currentIndex + 1))
        }

        // Create and add new entry
        let entry = VideoHistoryEntry(
            videoId: videoId,
            videoURL: videoURL,
            playCount: playCount,
            totalViewTime: totalViewTime
        )
        entries.append(entry)
        currentIndex = entries.count - 1

        // Trim history if it exceeds max size
        if entries.count > Self.maxHistorySize {
            let removeCount = entries.count - Self.maxHistorySize
            entries.removeFirst(removeCount)
            currentIndex = max(0, currentIndex - removeCount)
        }

        AppLogger.video.debug("Pushed video to history: \(videoId), index: \(self.currentIndex), total: \(self.entries.count)")
    }

    /// Updates the last frame and playback time of the current entry
    /// Call this before navigating away to capture the exit state
    func updateCurrentState(frame: CGImage?, playbackTime: Double) {
        guard currentIndex >= 0, currentIndex < entries.count else { return }
        entries[currentIndex].lastFrame = frame
        entries[currentIndex].playbackTime = playbackTime
    }

    /// Updates just the playback time of the current entry
    func updateCurrentPlaybackTime(_ time: Double) {
        guard currentIndex >= 0, currentIndex < entries.count else { return }
        entries[currentIndex].playbackTime = time
    }

    /// Navigate to the previous video in history
    /// - Returns: The previous video entry, or nil if at the beginning
    @discardableResult
    func goBack() -> VideoHistoryEntry? {
        guard canGoBack else { return nil }
        currentIndex -= 1
        AppLogger.video.debug("Navigated back in history to index: \(self.currentIndex)")
        return currentEntry
    }

    /// Navigate to the next video in history
    /// - Returns: The next video entry, or nil if at the end
    @discardableResult
    func goForward() -> VideoHistoryEntry? {
        guard canGoForward else { return nil }
        currentIndex += 1
        AppLogger.video.debug("Navigated forward in history to index: \(self.currentIndex)")
        return currentEntry
    }

    /// Clears all history
    func clear() {
        entries.removeAll()
        currentIndex = -1
        AppLogger.video.debug("Cleared video history")
    }

    /// Gets the frame for a specific direction (for swipe preview)
    func frameForDirection(_ direction: SwipeDirection) -> CGImage? {
        switch direction {
        case .back:
            return previousEntry?.lastFrame
        case .forward:
            return nextEntry?.lastFrame
        }
    }
}

/// Direction for swipe navigation
enum SwipeDirection {
    case back
    case forward
}

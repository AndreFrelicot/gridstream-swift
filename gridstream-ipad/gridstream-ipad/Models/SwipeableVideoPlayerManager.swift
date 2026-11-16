//
//  SwipeableVideoPlayerManager.swift
//  gridstream-ipad
//

import AVFoundation
import Foundation
import OSLog

/// Manages video player references for fluid swipe navigation between videos.
/// Uses SharedPlayerPool for the current player (shared with fullscreen mode)
/// and manages previous/next players locally for swipe transitions.
@Observable
final class SwipeableVideoPlayerManager {
    /// The tile index this manager is associated with
    private(set) var tileIndex: Int = -1

    /// Reference to the shared player pool
    private weak var playerPool: SharedPlayerPool?

    /// Reference to the tile history for navigation state
    private weak var tileHistory: TileVideoHistory?

    /// Reference to the global playback manager for player registration
    private weak var playbackManager: GlobalPlaybackManager?

    /// Callback used by active players to report playback statistics.
    @ObservationIgnored private var playbackStatsReporter: VideoPlayerState.PlaybackStatsReporter?

    /// Deferred seek / pause / preload work, at most one per player role.
    /// Every setup and swap cancels the pending ones first: after a swap a
    /// stale task would otherwise seek or pause a player that changed role
    /// (e.g. the "previous" player just promoted to current). Also cancelled
    /// on deinit (tile removed from the grid).
    private enum DeferredRole: Hashable {
        case current, previous, next, preload
    }
    @ObservationIgnored private var deferredTasks: [DeferredRole: Task<Void, Never>] = [:]

    /// The current video URL
    private(set) var currentURL: URL?

    // MARK: - Player Access (via Pool)

    /// The main player currently being displayed (from shared pool)
    var currentPlayer: VideoPlayerState {
        guard let pool = playerPool else {
            // Fallback: create a temporary player (shouldn't happen in normal flow)
            AppLogger.video.warning("SwipeableVideoPlayerManager: No pool configured, using temporary player")
            return VideoPlayerState()
        }
        return pool.currentPlayer(forTile: tileIndex)
    }

    /// Pre-loaded player for the previous video in history
    var previousPlayer: VideoPlayerState? {
        playerPool?.existingPreviousPlayer(forTile: tileIndex)
    }

    /// Pre-loaded player for the next video in history
    var nextPlayer: VideoPlayerState? {
        playerPool?.existingNextPlayer(forTile: tileIndex)
    }

    init() {
        // Configuration happens via configure()
    }

    deinit {
        // Cancel any pending delayed seeks / preload work so they don't fire
        // against deallocated services after the tile is gone.
        for task in deferredTasks.values {
            task.cancel()
        }
    }

    /// Replaces the pending deferred work for `role`.
    private func schedule(_ role: DeferredRole, _ body: @escaping @MainActor () async -> Void) {
        deferredTasks[role]?.cancel()
        deferredTasks[role] = Task { @MainActor in
            await body()
        }
    }

    private func cancelDeferredTasks() {
        for task in deferredTasks.values {
            task.cancel()
        }
        deferredTasks.removeAll()
    }

    /// Seeks `player` to `time` once its item is ready, then optionally
    /// pauses it. Skipped when cancelled or when the player was reloaded.
    private func scheduleSeek(_ role: DeferredRole, player: VideoPlayerState, to time: Double, pauseAfter: Bool) {
        schedule(role) {
            guard await player.waitUntilReadyToPlay() else { return }
            player.seek(to: time)
            if pauseAfter {
                player.pause()
            }
        }
    }

    // MARK: - Configuration

    /// Configure the manager with pool, tile index, history, and playback manager
    func configure(
        with pool: SharedPlayerPool,
        tileIndex: Int,
        history: TileVideoHistory,
        playbackManager: GlobalPlaybackManager,
        playbackStatsReporter: VideoPlayerState.PlaybackStatsReporter? = nil
    ) {
        self.playerPool = pool
        self.tileIndex = tileIndex
        self.tileHistory = history
        self.playbackManager = playbackManager
        self.playbackStatsReporter = playbackStatsReporter
        AppLogger.video.debug("SwipeableVideoPlayerManager configured for tile \(tileIndex)")
    }

    // MARK: - Player Setup

    /// Set up the current player with a video URL and optionally seek to a specific time
    /// Skips reload if the player already has the correct URL loaded
    /// - Parameter autoplay: When false the player is set up paused at `time`
    ///   (used for cold-start restore so we don't start playback automatically).
    func setupCurrentPlayer(url: URL, fileId: String? = nil, seekTo time: Double? = nil, autoplay: Bool = true) {
        cancelDeferredTasks()
        let player = currentPlayer
        player.configurePlaybackStatsReporter(playbackStatsReporter)

        // Skip reload if already loaded with correct URL
        if player.videoURL == url {
            currentURL = url
            player.setAudioSuppressed(false)
            AppLogger.video.debug("Skipping reload - player already has correct URL")

            // Still seek if a time was specified (e.g., restoring from fullscreen)
            if let seekTime = time, seekTime > 0 {
                player.seek(to: seekTime)
            }
            if !autoplay {
                player.pause()
            }
            return
        }

        currentURL = url
        player.setupPlayer(url: url, fileId: fileId, autoplay: autoplay)
        // Current player: audible unless the user muted this tile
        player.setAudioSuppressed(false)

        if let seekTime = time, seekTime > 0 {
            // Seek once the new item is ready
            scheduleSeek(.current, player: player, to: seekTime, pauseAfter: !autoplay)
        }

        // Pre-load adjacent videos
        preloadAdjacentVideos()
    }

    /// Pre-load the previous and next videos based on history
    /// Skips loading if the player already has the correct video loaded
    func preloadAdjacentVideos() {
        guard let history = tileHistory, let pool = playerPool else { return }

        // Pre-load previous video if available
        if let previousEntry = history.previousEntry {
            let prevPlayer = pool.existingPreviousPlayer(forTile: tileIndex)

            // Check if already loaded with correct URL
            if prevPlayer?.videoURL == previousEntry.videoURL {
                // Already loaded, just ensure it's paused and muted
                prevPlayer?.pause()
                prevPlayer?.setAudioSuppressed(true)
                AppLogger.video.debug("Previous video already loaded, skipping reload")
            } else {
                // Need to load
                let player = pool.previousPlayer(forTile: tileIndex)
                player.configurePlaybackStatsReporter(playbackStatsReporter)
                player.setupPlayer(url: previousEntry.videoURL, fileId: previousEntry.videoId, autoplay: false)
                player.setAudioSuppressed(true)
                player.pause()

                // Seek to saved position
                if previousEntry.playbackTime > 0 {
                    scheduleSeek(.previous, player: player, to: previousEntry.playbackTime, pauseAfter: true)
                }

                AppLogger.video.debug("Pre-loaded previous video: \(previousEntry.videoURL.lastPathComponent)")
            }
        } else {
            pool.setPreviousPlayer(nil, forTile: tileIndex)
        }

        // Pre-load next video if available
        if let nextEntry = history.nextEntry {
            let nxtPlayer = pool.existingNextPlayer(forTile: tileIndex)

            // Check if already loaded with correct URL
            if nxtPlayer?.videoURL == nextEntry.videoURL {
                // Already loaded, just ensure it's paused and muted
                nxtPlayer?.pause()
                nxtPlayer?.setAudioSuppressed(true)
                AppLogger.video.debug("Next video already loaded, skipping reload")
            } else {
                // Need to load
                let player = pool.nextPlayer(forTile: tileIndex)
                player.configurePlaybackStatsReporter(playbackStatsReporter)
                player.setupPlayer(url: nextEntry.videoURL, fileId: nextEntry.videoId, autoplay: false)
                player.setAudioSuppressed(true)
                player.pause()

                // Seek to saved position
                if nextEntry.playbackTime > 0 {
                    scheduleSeek(.next, player: player, to: nextEntry.playbackTime, pauseAfter: true)
                }

                AppLogger.video.debug("Pre-loaded next video: \(nextEntry.videoURL.lastPathComponent)")
            }
        } else {
            pool.setNextPlayer(nil, forTile: tileIndex)
        }
    }

    // MARK: - Navigation

    /// Navigate to the previous video, swapping players via the pool
    /// Returns the new current player's playback time to seek to
    func navigateBack() -> Double? {
        guard let history = tileHistory, let pool = playerPool else { return nil }
        guard let oldPrevious = previousPlayer else { return nil }

        // Players are about to change roles: drop work aimed at the old ones
        cancelDeferredTasks()

        // Capture reference to old current player before swap
        let oldCurrent = currentPlayer

        // First, pause and silence the old current player
        oldCurrent.pause()
        oldCurrent.setAudioSuppressed(true)

        // Unregister old current player from global playback (so it won't respond to Play All)
        playbackManager?.unregister(oldCurrent)

        // Swap players in the pool
        pool.swapForBackNavigation(tileIndex: tileIndex)

        // Update current URL
        currentURL = history.previousEntry?.videoURL

        // Carry the tile's mute over to the incoming player: mute belongs to the
        // tile, not to the player object being swapped in
        oldPrevious.setMuted(oldCurrent.isMuted)

        // Register the new current player (which was the previous)
        playbackManager?.register(oldPrevious)

        // Make the new current audible (unless muted) and start playing
        oldPrevious.setAudioSuppressed(false)
        oldPrevious.play()

        // Pre-load the new previous (after a small delay to prioritize current playback)
        schedule(.preload) { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            guard !Task.isCancelled else { return }
            self?.preloadAdjacentVideos()
        }

        AppLogger.video.debug("Navigated back, swapped players via pool")

        return history.previousEntry?.playbackTime
    }

    /// Navigate to the next video, swapping players via the pool
    /// Returns the new current player's playback time to seek to
    func navigateForward() -> Double? {
        guard let history = tileHistory, let pool = playerPool else { return nil }
        guard let oldNext = nextPlayer else { return nil }

        // Players are about to change roles: drop work aimed at the old ones
        cancelDeferredTasks()

        // Capture reference to old current player before swap
        let oldCurrent = currentPlayer

        // First, pause and silence the old current player
        oldCurrent.pause()
        oldCurrent.setAudioSuppressed(true)

        // Unregister old current player from global playback (so it won't respond to Play All)
        playbackManager?.unregister(oldCurrent)

        // Swap players in the pool
        pool.swapForForwardNavigation(tileIndex: tileIndex)

        // Update current URL
        currentURL = history.nextEntry?.videoURL

        // Carry the tile's mute over to the incoming player: mute belongs to the
        // tile, not to the player object being swapped in
        oldNext.setMuted(oldCurrent.isMuted)

        // Register the new current player (which was the next)
        playbackManager?.register(oldNext)

        // Make the new current audible (unless muted) and start playing
        oldNext.setAudioSuppressed(false)
        oldNext.play()

        // Pre-load the new next (after a small delay to prioritize current playback)
        schedule(.preload) { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            guard !Task.isCancelled else { return }
            self?.preloadAdjacentVideos()
        }

        AppLogger.video.debug("Navigated forward, swapped players via pool")

        return history.nextEntry?.playbackTime
    }

    // MARK: - Playback Control

    /// Pause and silence all players (current from pool, adjacent locally)
    func pauseAll() {
        currentPlayer.pause()
        currentPlayer.setAudioSuppressed(true)
        playerPool?.pauseAdjacentPlayers(forTile: tileIndex)
    }

    /// Get the player for a specific direction (for swipe preview)
    func playerForDirection(_ direction: SwipeDirection) -> VideoPlayerState? {
        switch direction {
        case .back:
            return previousPlayer
        case .forward:
            return nextPlayer
        }
    }

    // MARK: - Frame Capture

    /// Capture the current frame from the main player
    func captureCurrentFrame() async -> CGImage? {
        return await currentPlayer.captureCurrentFrame()
    }

    /// Get the current playback time
    var currentPlaybackTime: Double {
        return currentPlayer.currentTime
    }

    // MARK: - Cleanup

    /// Clean up adjacent players (current player remains in pool for fullscreen)
    func cleanupAdjacentPlayers() {
        playerPool?.pauseAdjacentPlayers(forTile: tileIndex)
        playerPool?.setPreviousPlayer(nil, forTile: tileIndex)
        playerPool?.setNextPlayer(nil, forTile: tileIndex)
    }
}

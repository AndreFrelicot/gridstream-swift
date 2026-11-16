//
//  SharedPlayerPool.swift
//  gridstream-ipad
//
//  Centralized pool for video players shared between grid and fullscreen modes.
//  This eliminates player recreation during mode transitions for seamless playback.
//

import Foundation
import OSLog

/// Manages a shared pool of VideoPlayerState instances keyed by tile index.
/// Both grid tiles and fullscreen mode reference the same players, ensuring:
/// - Seamless playback position preservation during transitions
/// - Reduced resource usage (no duplicate players)
/// - Fluid mode switching without video reload
@Observable
final class SharedPlayerPool {
    /// Pool of current players, keyed by tile index
    private var currentPlayers: [Int: VideoPlayerState] = [:]

    /// Pool of previous players for swipe navigation (not shared with fullscreen)
    private var previousPlayers: [Int: VideoPlayerState] = [:]

    /// Pool of next players for swipe navigation (not shared with fullscreen)
    private var nextPlayers: [Int: VideoPlayerState] = [:]

    /// Players leaving the pool must also leave the playback group, or Play
    /// All keeps driving them and a solo on a removed tile silences the rest.
    @ObservationIgnored private let playbackManager: GlobalPlaybackManager

    /// Called with the tile index when a tile's current player plays to the
    /// end, in grid, fullscreen and PiP alike. Adjacent (swipe) players that
    /// end are ignored.
    @ObservationIgnored var onTilePlaybackEnded: ((Int) -> Void)?

    init(playbackManager: GlobalPlaybackManager = .shared) {
        self.playbackManager = playbackManager
    }

    // MARK: - Current Player Management

    /// Gets or creates the current player for a tile.
    /// This player is shared between grid and fullscreen modes.
    func currentPlayer(forTile index: Int) -> VideoPlayerState {
        if let existing = currentPlayers[index] {
            return existing
        }

        let player = makePlayer()
        player.tileIndex = index  // Set tile index for stereo panning
        currentPlayers[index] = player
        AppLogger.video.debug("Created new current player for tile \(index)")
        return player
    }

    /// Checks if a current player exists for a tile
    func hasCurrentPlayer(forTile index: Int) -> Bool {
        return currentPlayers[index] != nil
    }

    // MARK: - Adjacent Player Management (for swipe navigation)

    /// Gets or creates the previous player for a tile (used for swipe-back)
    func previousPlayer(forTile index: Int) -> VideoPlayerState {
        if let existing = previousPlayers[index] {
            return existing
        }

        let player = makePlayer()
        // Set before the player loads anything: the audio tap picks up its pan
        // from the tile index when the item is created, and this player may
        // later be promoted to current by a swipe.
        player.tileIndex = index
        previousPlayers[index] = player
        return player
    }

    /// Gets the existing previous player if any
    func existingPreviousPlayer(forTile index: Int) -> VideoPlayerState? {
        return previousPlayers[index]
    }

    /// Sets the previous player for a tile
    func setPreviousPlayer(_ player: VideoPlayerState?, forTile index: Int) {
        previousPlayers[index] = player
    }

    /// Gets or creates the next player for a tile (used for swipe-forward)
    func nextPlayer(forTile index: Int) -> VideoPlayerState {
        if let existing = nextPlayers[index] {
            return existing
        }

        let player = makePlayer()
        player.tileIndex = index  // See previousPlayer(forTile:)
        nextPlayers[index] = player
        return player
    }

    /// Gets the existing next player if any
    func existingNextPlayer(forTile index: Int) -> VideoPlayerState? {
        return nextPlayers[index]
    }

    /// Sets the next player for a tile
    func setNextPlayer(_ player: VideoPlayerState?, forTile index: Int) {
        nextPlayers[index] = player
    }

    // MARK: - Navigation Support

    /// Swaps players during back navigation.
    /// Current becomes next, previous becomes current.
    func swapForBackNavigation(tileIndex: Int) {
        let oldCurrent = currentPlayers[tileIndex]
        let oldPrevious = previousPlayers[tileIndex]

        if let prev = oldPrevious {
            prev.tileIndex = tileIndex  // Update tile index for stereo panning
            currentPlayers[tileIndex] = prev
            nextPlayers[tileIndex] = oldCurrent
            previousPlayers[tileIndex] = nil
            AppLogger.video.debug("Swapped players for back navigation on tile \(tileIndex)")
        }
    }

    /// Swaps players during forward navigation.
    /// Current becomes previous, next becomes current.
    func swapForForwardNavigation(tileIndex: Int) {
        let oldCurrent = currentPlayers[tileIndex]
        let oldNext = nextPlayers[tileIndex]

        if let next = oldNext {
            next.tileIndex = tileIndex  // Update tile index for stereo panning
            currentPlayers[tileIndex] = next
            previousPlayers[tileIndex] = oldCurrent
            nextPlayers[tileIndex] = nil
            AppLogger.video.debug("Swapped players for forward navigation on tile \(tileIndex)")
        }
    }

    // MARK: - Cleanup

    /// Removes all players for a specific tile
    func removePlayers(forTile index: Int) {
        var releasedPlayerIDs: Set<UUID> = []
        for player in [currentPlayers[index], previousPlayers[index], nextPlayers[index]].compactMap({ $0 }) {
            guard releasedPlayerIDs.insert(player.id).inserted else { continue }
            release(player)
        }

        currentPlayers.removeValue(forKey: index)
        previousPlayers.removeValue(forKey: index)
        nextPlayers.removeValue(forKey: index)

        AppLogger.video.debug("Removed all players for tile \(index)")
    }

    /// Removes every pooled player and releases underlying AVPlayer resources once per instance.
    func removeAllPlayers() {
        var releasedPlayerIDs: Set<UUID> = []
        let players = Array(currentPlayers.values) + Array(previousPlayers.values) + Array(nextPlayers.values)
        for player in players {
            guard releasedPlayerIDs.insert(player.id).inserted else { continue }
            release(player)
        }

        currentPlayers.removeAll()
        previousPlayers.removeAll()
        nextPlayers.removeAll()

        AppLogger.video.debug("Removed all pooled players")
    }

    /// Pauses adjacent players for a tile (previous and next)
    func pauseAdjacentPlayers(forTile index: Int) {
        previousPlayers[index]?.pause()
        previousPlayers[index]?.setAudioSuppressed(true)
        nextPlayers[index]?.pause()
        nextPlayers[index]?.setAudioSuppressed(true)
    }

    /// Gets all current player tile indices
    var activeTileIndices: [Int] {
        Array(currentPlayers.keys).sorted()
    }

    /// Reindexes players when tiles are removed or reordered
    func reindexPlayers(newIndices: [Int: Int]) {
        var newCurrentPlayers: [Int: VideoPlayerState] = [:]
        var newPreviousPlayers: [Int: VideoPlayerState] = [:]
        var newNextPlayers: [Int: VideoPlayerState] = [:]
        var retainedPlayerIDs: Set<UUID> = []

        for (oldIndex, newIndex) in newIndices {
            if let player = currentPlayers[oldIndex] {
                player.tileIndex = newIndex  // Update tile index for stereo panning
                newCurrentPlayers[newIndex] = player
                retainedPlayerIDs.insert(player.id)
            }
            if let player = previousPlayers[oldIndex] {
                player.tileIndex = newIndex
                newPreviousPlayers[newIndex] = player
                retainedPlayerIDs.insert(player.id)
            }
            if let player = nextPlayers[oldIndex] {
                player.tileIndex = newIndex
                newNextPlayers[newIndex] = player
                retainedPlayerIDs.insert(player.id)
            }
        }

        let droppedPlayers = Array(currentPlayers.values) + Array(previousPlayers.values) + Array(nextPlayers.values)
        var releasedDroppedPlayerIDs: Set<UUID> = []
        for player in droppedPlayers where !retainedPlayerIDs.contains(player.id) {
            guard releasedDroppedPlayerIDs.insert(player.id).inserted else { continue }
            release(player)
        }

        currentPlayers = newCurrentPlayers
        previousPlayers = newPreviousPlayers
        nextPlayers = newNextPlayers

        AppLogger.video.debug("Reindexed players: \(newIndices)")
    }

    /// A new player whose end is reported for the tile it is current on at
    /// that moment: players change tile and role on swipes and reindexing.
    private func makePlayer() -> VideoPlayerState {
        let player = VideoPlayerState()
        player.onPlaybackEnded = { [weak self, weak player] in
            guard let self, let player,
                  let tileIndex = self.currentPlayers.first(where: { $0.value === player })?.key else { return }
            self.onTilePlaybackEnded?(tileIndex)
        }
        return player
    }

    /// Takes a player out of the playback group and frees its AVPlayer.
    private func release(_ player: VideoPlayerState) {
        playbackManager.unregister(player)
        player.releasePlayerResources()
    }
}

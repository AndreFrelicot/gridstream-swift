//
//  TileAudioStateManager.swift
//  gridstream-ipad
//

import Foundation
import OSLog

/// Stores per-tile audio state that persists across tile and fullscreen modes
struct TileAudioState {
    var isMuted: Bool = false
    var isSolo: Bool = false
    var isVolumeOverrideActive: Bool = false
    var overrideVolume: Float = 1.0
}

/// Centralized manager for tile audio state that persists across view transitions
@MainActor @Observable
final class TileAudioStateManager {
    static let shared = TileAudioStateManager()

    private var states: [Int: TileAudioState] = [:]
    private let logger = Logger(subsystem: "com.gridstream.ipad", category: "TileAudioStateManager")

    /// Hook called after every state mutation so the app can mirror the
    /// new value onto SwiftData. Set during app boot. Audio state is
    /// independent of the server, so persisting on every mutation costs
    /// little and survives cold restarts cleanly.
    @ObservationIgnored var persistenceBridge: ((Int, TileAudioState) -> Void)?

    /// Internal so tests can use an isolated instance; the app uses `shared`.
    init() {}

    // MARK: - State Access

    /// Gets the audio state for a tile, creating default state if not exists
    func state(for tileIndex: Int) -> TileAudioState {
        if let existing = states[tileIndex] {
            return existing
        }
        let newState = TileAudioState()
        states[tileIndex] = newState
        return newState
    }

    /// Hydrates the in-memory store with a state read from persistence.
    /// Does not fire the persistence bridge — this is a load, not a mutation.
    func hydrateState(_ state: TileAudioState, for tileIndex: Int) {
        states[tileIndex] = state
    }

    /// Updates mute state for a tile
    func setMuted(_ muted: Bool, for tileIndex: Int) {
        ensureState(for: tileIndex)
        states[tileIndex]?.isMuted = muted
        logger.debug("Tile \(tileIndex) muted: \(muted)")
        notifyPersistenceBridge(for: tileIndex)
    }

    /// Updates solo state for a tile. Solo is exclusive: soloing a tile
    /// clears the solo of every other tile, so at most one tile is ever solo.
    func setSolo(_ solo: Bool, for tileIndex: Int) {
        if solo {
            for (otherIndex, state) in states where otherIndex != tileIndex && state.isSolo {
                states[otherIndex]?.isSolo = false
                notifyPersistenceBridge(for: otherIndex)
            }
        }
        ensureState(for: tileIndex)
        states[tileIndex]?.isSolo = solo
        logger.debug("Tile \(tileIndex) solo: \(solo)")
        notifyPersistenceBridge(for: tileIndex)
    }

    /// Updates volume override state for a tile
    func setVolumeOverride(active: Bool, level: Float, for tileIndex: Int) {
        ensureState(for: tileIndex)
        states[tileIndex]?.isVolumeOverrideActive = active
        states[tileIndex]?.overrideVolume = level
        logger.debug("Tile \(tileIndex) volume override: active=\(active), level=\(level)")
        notifyPersistenceBridge(for: tileIndex)
    }

    /// Checks if a tile is muted
    func isMuted(for tileIndex: Int) -> Bool {
        states[tileIndex]?.isMuted ?? false
    }

    /// Checks if a tile is in solo mode
    func isSolo(for tileIndex: Int) -> Bool {
        states[tileIndex]?.isSolo ?? false
    }

    /// Checks if volume override is active for a tile
    func isVolumeOverrideActive(for tileIndex: Int) -> Bool {
        states[tileIndex]?.isVolumeOverrideActive ?? false
    }

    /// Gets the override volume level for a tile
    func overrideVolume(for tileIndex: Int) -> Float {
        states[tileIndex]?.overrideVolume ?? 1.0
    }

    // MARK: - Cleanup

    /// Clears audio state for a specific tile
    func clearState(for tileIndex: Int) {
        states.removeValue(forKey: tileIndex)
        logger.debug("Cleared audio state for tile \(tileIndex)")
    }

    /// Reindexes audio states when tiles are removed or reordered.
    /// States for omitted old indices are intentionally dropped.
    func reindexStates(newIndices: [Int: Int]) {
        var newStates: [Int: TileAudioState] = [:]
        for (oldIndex, newIndex) in newIndices {
            if let state = states[oldIndex] {
                newStates[newIndex] = state
            }
        }
        states = newStates
        logger.debug("Reindexed audio states")
    }

    /// Clears all audio states (useful when grid is reset)
    func clearAllStates() {
        states.removeAll()
        logger.debug("Cleared all audio states")
    }

    // MARK: - Private

    private func ensureState(for tileIndex: Int) {
        if states[tileIndex] == nil {
            states[tileIndex] = TileAudioState()
        }
    }

    private func notifyPersistenceBridge(for tileIndex: Int) {
        guard let bridge = persistenceBridge, let state = states[tileIndex] else { return }
        bridge(tileIndex, state)
    }
}

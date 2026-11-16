//
//  GlobalPlaybackManager.swift
//  gridstream-ipad
//

import Foundation
import OSLog

@Observable
final class GlobalPlaybackManager {
    static let shared = GlobalPlaybackManager()

    private(set) var activePlayers: [UUID: VideoPlayerState] = [:]
    private(set) var soloPlayerID: UUID? = nil

    // MARK: - SuperSolo State
    /// SuperSolo mode: temporarily solos the fullscreen video without affecting stored audio states
    private(set) var superSoloPlayerID: UUID? = nil

    var isSuperSoloActive: Bool {
        superSoloPlayerID != nil
    }

    var hasActivePlayers: Bool {
        !activePlayers.isEmpty
    }

    /// Per-tile audio state. Solo and mute belong to the tile, not to whichever
    /// player object happens to be showing its video right now.
    @ObservationIgnored private let audioStates: TileAudioStateManager

    /// Pass an isolated `TileAudioStateManager` in tests; the app uses `.shared`.
    init(audioStates: TileAudioStateManager? = nil) {
        self.audioStates = audioStates ?? .shared
    }

    func register(_ playerState: VideoPlayerState) {
        activePlayers[playerState.id] = playerState
        // Solo belongs to the tile: a player arriving on a soloed tile (swipe,
        // video change, return from fullscreen) takes the solo back.
        if let tileIndex = playerState.tileIndex, audioStates.isSolo(for: tileIndex) {
            soloPlayerID = playerState.id
        }
        // A player joining while a solo is running must be silenced like the rest
        applyAudioSuppression()
        AppLogger.video.debug("Registered player \(playerState.id.uuidString). Total active: \(self.activePlayers.count)")
    }

    func unregister(_ playerState: VideoPlayerState) {
        if soloPlayerID == playerState.id {
            // Only the runtime target goes; the tile keeps its solo and hands
            // it to the next player registered on it.
            soloPlayerID = nil
        }
        if superSoloPlayerID == playerState.id {
            // The fullscreen video was swapped out; the view re-points superSolo
            // at its replacement. Dropping the stale target here keeps the rest
            // of the group from staying suppressed for a player that is gone.
            superSoloPlayerID = nil
        }
        activePlayers.removeValue(forKey: playerState.id)
        // Leaving the group: never strand it silent on someone else's account
        playerState.setAudioSuppressed(false)
        applyAudioSuppression()
        AppLogger.video.debug("Unregistered player \(playerState.id.uuidString). Total active: \(self.activePlayers.count)")
    }

    func pauseAll() {
        for playerState in activePlayers.values {
            playerState.pause()
        }
        AppLogger.video.info("Paused all players (\(self.activePlayers.count) total)")
    }

    func playAll() {
        for playerState in activePlayers.values {
            playerState.play()
        }
        AppLogger.video.info("Resumed all players (\(self.activePlayers.count) total)")
    }

    // MARK: - Audio Suppression

    /// The only player allowed to be heard, if any. SuperSolo outranks solo.
    private var audiblePlayerID: UUID? {
        superSoloPlayerID ?? soloPlayerID
    }

    /// Recomputes suppression for every registered player from the current
    /// solo state. Suppression is a layer on top of the user's mute: soloing
    /// never unmutes a video the user muted, and leaving solo never gives
    /// sound back to one that was muted before.
    private func applyAudioSuppression() {
        let audibleID = audiblePlayerID
        for (id, player) in activePlayers {
            player.setAudioSuppressed(audibleID != nil && id != audibleID)
        }
    }

    // MARK: - Solo Mode

    func isSolo(_ playerID: UUID) -> Bool {
        soloPlayerID == playerID
    }

    func activateSolo(for playerState: VideoPlayerState) {
        guard soloPlayerID != playerState.id else { return }

        soloPlayerID = playerState.id
        applyAudioSuppression()
        AppLogger.video.info("Activated solo for player \(playerState.id.uuidString)")
    }

    /// Ends the solo only if `playerState` is the one soloed. Turning solo off
    /// on one tile must never cancel a solo that another tile has since taken.
    func deactivateSolo(for playerState: VideoPlayerState) {
        guard soloPlayerID == playerState.id else { return }

        soloPlayerID = nil
        applyAudioSuppression()
        AppLogger.video.info("Deactivated solo mode")
    }

    /// The solo control of a tile. Records the tile's solo (exclusive across
    /// tiles, persisted) and applies it to the player now showing the tile.
    func setSolo(_ isSolo: Bool, for playerState: VideoPlayerState) {
        if let tileIndex = playerState.tileIndex {
            audioStates.setSolo(isSolo, for: tileIndex)
        }
        if isSolo {
            activateSolo(for: playerState)
        } else {
            deactivateSolo(for: playerState)
        }
    }

    /// Long-press solo: silences every other video for real — their mute state
    /// changes, so it outlives this solo — and makes this one the solo target.
    /// Mutes go through the tile audio state so the other tiles' buttons and
    /// the persisted state show it, and a video change keeps it.
    func exclusiveSolo(for playerState: VideoPlayerState) {
        for (id, player) in activePlayers where id != playerState.id {
            if let tileIndex = player.tileIndex {
                audioStates.setMuted(true, for: tileIndex)
            }
            player.setMuted(true)
        }

        if let tileIndex = playerState.tileIndex {
            audioStates.setSolo(true, for: tileIndex)
        }
        soloPlayerID = playerState.id
        applyAudioSuppression()
        AppLogger.video.info("Activated exclusive solo for player \(playerState.id.uuidString)")
    }

    // MARK: - SuperSolo Mode

    /// Activates superSolo mode for fullscreen: temporarily silences every other
    /// player while the fullscreen one plays. Mute and volume states are left
    /// untouched, so deactivating restores exactly what the user had set.
    func activateSuperSolo(for playerState: VideoPlayerState) {
        guard superSoloPlayerID != playerState.id else { return }

        superSoloPlayerID = playerState.id
        applyAudioSuppression()
        AppLogger.video.info("Activated superSolo for player \(playerState.id.uuidString)")
    }

    /// Deactivates superSolo mode, falling back to whatever solo state was set
    func deactivateSuperSolo() {
        guard superSoloPlayerID != nil else { return }

        superSoloPlayerID = nil
        applyAudioSuppression()
        AppLogger.video.info("Deactivated superSolo mode - restored previous audio states")
    }

    /// Checks if the given player is currently in superSolo mode
    func isSuperSolo(_ playerID: UUID) -> Bool {
        superSoloPlayerID == playerID
    }
}

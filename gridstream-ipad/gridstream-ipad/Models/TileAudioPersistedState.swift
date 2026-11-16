//
//  TileAudioPersistedState.swift
//  gridstream-ipad
//

import Foundation
import SwiftData

/// Sidecar SwiftData model storing the per-tile audio state
/// (mute / solo / volume override) so the audio configuration survives
/// cold starts and OOM-driven process restarts.
@Model
final class TileAudioPersistedState {
    var id: UUID
    var tileIndex: Int
    var isMuted: Bool = false
    var isSolo: Bool = false
    var isVolumeOverrideActive: Bool = false
    var overrideVolume: Float = 1.0

    init(
        tileIndex: Int,
        isMuted: Bool = false,
        isSolo: Bool = false,
        isVolumeOverrideActive: Bool = false,
        overrideVolume: Float = 1.0
    ) {
        self.id = UUID()
        self.tileIndex = tileIndex
        self.isMuted = isMuted
        self.isSolo = isSolo
        self.isVolumeOverrideActive = isVolumeOverrideActive
        self.overrideVolume = overrideVolume
    }
}

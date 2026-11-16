//
//  TileLayout.swift
//  gridstream-ipad
//

import Foundation
import SwiftData
import CoreGraphics

@Model
final class TileLayout {
    var id: UUID
    var index: Int
    var widthRatio: Double
    var heightRatio: Double

    // MARK: - Content State (persisted for cold-start restore)
    /// Stable file ID of the video bound to this tile; nil when the tile has
    /// no assigned video. Optional/defaulted so SwiftData lightweight
    /// migration from V1 picks the default without data loss.
    var videoFileId: String?
    /// Last known playback position in seconds; stamped at `.background`.
    var playbackTime: Double = 0
    /// Smart List currently driving this tile, if any.
    var smartListId: UUID?
    /// Simple List currently driving this tile, if any.
    var simpleListId: UUID?

    @Relationship(deleteRule: .cascade) var framingState: TileFramingState?
    @Relationship(deleteRule: .cascade) var pipPosition: PiPPositionState?
    @Relationship(deleteRule: .cascade) var audioState: TileAudioPersistedState?

    static let minimumRatio: Double = 0.1
    static let maximumRatio: Double = 0.75

    init(index: Int, widthRatio: Double = 0.5, heightRatio: Double = 0.5) {
        self.id = UUID()
        self.index = index
        self.widthRatio = Self.clampRatio(widthRatio)
        self.heightRatio = Self.clampRatio(heightRatio)
        self.framingState = TileFramingState(index: index)
        self.pipPosition = nil
        self.audioState = nil
    }

    func updateWidthRatio(_ ratio: Double) {
        widthRatio = Self.clampRatio(ratio)
    }

    func updateHeightRatio(_ ratio: Double) {
        heightRatio = Self.clampRatio(ratio)
    }

    private static func clampRatio(_ ratio: Double) -> Double {
        min(maximumRatio, max(minimumRatio, ratio))
    }

    // MARK: - Framing State Convenience Methods

    /// Returns the current framing mode, defaulting to .fill if no state exists
    var currentFramingMode: FramingMode {
        framingState?.framingMode ?? .fill
    }

    /// Ensures framing state exists, creating it if necessary
    func ensureFramingState() {
        if framingState == nil {
            framingState = TileFramingState(index: index)
        }
    }

    // MARK: - PiP Position Convenience Methods

    /// Returns the current PiP position, defaulting to .zero if no position is saved
    var currentPiPPosition: CGPoint {
        pipPosition?.position ?? .zero
    }

    /// Ensures PiP position state exists, creating it if necessary
    func ensurePiPPosition() {
        if pipPosition == nil {
            pipPosition = PiPPositionState(tileIndex: index)
        }
    }

    /// Updates the PiP position, creating the state if necessary
    func updatePiPPosition(_ position: CGPoint) {
        ensurePiPPosition()
        pipPosition?.updatePosition(position)
    }

    // MARK: - PiP Scale Convenience Methods

    /// Returns the current PiP scale (width ratio), defaulting to 0.2 if no state
    var currentPiPScale: CGFloat {
        CGFloat(pipPosition?.scale ?? PiPPositionState.defaultScale)
    }

    /// Updates the PiP scale with snapping, creating the state if necessary
    func updatePiPScale(_ scale: CGFloat) {
        ensurePiPPosition()
        pipPosition?.updateScaleWithSnap(Double(scale))
    }

    // MARK: - PiP Rotation Convenience Methods

    /// Returns the current PiP rotation in radians, defaulting to 0 if no state
    var currentPiPRotation: CGFloat {
        CGFloat(pipPosition?.rotation ?? PiPPositionState.defaultRotation)
    }

    /// Updates the PiP rotation, creating the state if necessary
    func updatePiPRotation(_ rotation: CGFloat) {
        ensurePiPPosition()
        pipPosition?.updateRotation(Double(rotation))
    }
}

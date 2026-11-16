//
//  PiPLayoutEntry.swift
//  gridstream-ipad
//

import Foundation
import SwiftData

@Model
final class PiPLayoutEntry {
    var id: UUID
    var pipTileIndex: Int
    var fullscreenTileIndex: Int
    var positionX: Double
    var positionY: Double
    var scale: Double
    var rotation: Double

    // Scale constraints
    static let minimumScale: Double = 0.1
    static let maximumScale: Double = 0.4
    static let defaultScale: Double = 0.2
    static let snapScale: Double = 0.2
    static let snapThreshold: Double = 0.02

    init(id: UUID = UUID(), pipTileIndex: Int, fullscreenTileIndex: Int, positionX: Double, positionY: Double, scale: Double = defaultScale, rotation: Double = 0) {
        self.id = id
        self.pipTileIndex = pipTileIndex
        self.fullscreenTileIndex = fullscreenTileIndex
        self.positionX = positionX
        self.positionY = positionY
        self.scale = scale
        self.rotation = rotation
    }

    func updatePosition(_ position: CGPoint) {
        self.positionX = position.x
        self.positionY = position.y
    }

    func updateScale(_ scale: Double) {
        let clamped = max(Self.minimumScale, min(Self.maximumScale, scale))
        self.scale = clamped
    }

    func updateScaleWithSnap(_ scale: Double) {
        let clamped = max(Self.minimumScale, min(Self.maximumScale, scale))

        // Snap to defaultScale if close enough
        if abs(clamped - Self.snapScale) < Self.snapThreshold {
            self.scale = Self.snapScale
        } else {
            self.scale = clamped
        }
    }

    func updateRotation(_ rotation: Double) {
        self.rotation = rotation
    }
}

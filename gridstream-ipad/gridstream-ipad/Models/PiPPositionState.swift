//
//  PiPPositionState.swift
//  gridstream-ipad
//

import Foundation
import SwiftData
import CoreGraphics
import OSLog

@Model
final class PiPPositionState {
    var id: UUID
    var tileIndex: Int
    var positionX: Double
    var positionY: Double
    var scale: Double = 0.2  // Width ratio: 0.1 to 0.4, default 0.2
    var rotation: Double = 0.0  // Rotation in radians

    // MARK: - Default Values

    static let defaultPositionX: Double = 0.0
    static let defaultPositionY: Double = 0.0
    static let defaultScale: Double = 0.2
    static let defaultRotation: Double = 0.0

    // Scale constraints
    static let minimumScale: Double = 0.1
    static let maximumScale: Double = 0.4
    static let snapScale: Double = 0.2
    static let snapThreshold: Double = 0.02  // Snap when within 2% of snap point

    // MARK: - Initialization

    init(
        tileIndex: Int,
        positionX: Double = defaultPositionX,
        positionY: Double = defaultPositionY,
        scale: Double = defaultScale,
        rotation: Double = defaultRotation
    ) {
        self.id = UUID()
        self.tileIndex = tileIndex
        self.positionX = positionX
        self.positionY = positionY
        self.scale = Self.clampScale(scale)
        self.rotation = rotation
    }

    // MARK: - Computed Properties

    var position: CGPoint {
        get { CGPoint(x: positionX, y: positionY) }
        set {
            positionX = newValue.x
            positionY = newValue.y
        }
    }

    // MARK: - Methods

    /// Updates position from a CGPoint
    func updatePosition(_ point: CGPoint) {
        positionX = point.x
        positionY = point.y
    }

    /// Updates scale with clamping and snapping
    func updateScale(_ newScale: Double) {
        scale = Self.clampScale(newScale)
    }

    /// Updates scale with snapping at the snap point (20%)
    func updateScaleWithSnap(_ newScale: Double) {
        let clamped = Self.clampScale(newScale)
        // Snap to 20% if within threshold
        if abs(clamped - Self.snapScale) < Self.snapThreshold {
            scale = Self.snapScale
        } else {
            scale = clamped
        }
    }

    /// Updates rotation in radians
    func updateRotation(_ newRotation: Double) {
        rotation = newRotation
    }

    /// Resets scale and rotation to defaults
    func resetTransform() {
        scale = Self.defaultScale
        rotation = Self.defaultRotation
    }

    // MARK: - Private Helpers

    private static func clampScale(_ value: Double) -> Double {
        min(maximumScale, max(minimumScale, value))
    }
}

// MARK: - Bounds

/// Keeps a PiP on screen. A PiP is placed by the top-left corner of its
/// unrotated frame and turned about its center, so what stays visible depends
/// on the rotation: turned a quarter, the picture is narrower than its frame,
/// and a frame pushed 80% off a side edge left nothing on screen to grab.
enum PiPBounds {
    /// Share of the tile left on screen when it is pushed against an edge.
    static let minimumVisibleRatio: CGFloat = 0.2

    /// The top-left corner closest to `position` that keeps the tile, of
    /// `width` × `height` turned by `rotation` radians, on screen.
    static func clamp(_ position: CGPoint, width: CGFloat, height: CGFloat, rotation: CGFloat, screen: CGSize) -> CGPoint {
        guard width > 0, height > 0, screen.width > 0, screen.height > 0 else { return position }
        let angle = rotation.isFinite ? rotation : 0
        var center = CGPoint(x: position.x + width / 2, y: position.y + height / 2)
        if !center.x.isFinite || !center.y.isFinite {
            AppLogger.pip.error("PiP position was not finite (\(position.x), \(position.y)): centered")
            center = CGPoint(x: screen.width / 2, y: screen.height / 2)
        }

        // The rotated tile's bounding box keeps 20% on screen, as an unrotated
        // tile does.
        let cosine = abs(cos(angle))
        let sine = abs(sin(angle))
        let overhangX = (width * cosine + height * sine) * (0.5 - minimumVisibleRatio)
        let overhangY = (width * sine + height * cosine) * (0.5 - minimumVisibleRatio)
        center.x = min(max(center.x, -overhangX), screen.width + overhangX)
        center.y = min(max(center.y, -overhangY), screen.height + overhangY)

        // Tilted into a corner, the box's corner can be empty. Then the circle
        // inscribed in the tile keeps 40% of its radius on screen.
        let shortSide = min(width, height)
        guard !reachesIntoScreen(center: center, width: width, height: height, angle: angle, depth: shortSide * 0.15, screen: screen) else {
            return CGPoint(x: center.x - width / 2, y: center.y - height / 2)
        }
        let nearest = CGPoint(x: min(max(center.x, 0), screen.width), y: min(max(center.y, 0), screen.height))
        let dx = center.x - nearest.x
        let dy = center.y - nearest.y
        let distance = (dx * dx + dy * dy).squareRoot()
        let limit = shortSide / 2 * (1 - 2 * minimumVisibleRatio)
        if distance > limit {
            AppLogger.pip.debug("PiP turned \(angle) rad left the screen at its corner: pulled back")
            center = CGPoint(x: nearest.x + dx * limit / distance, y: nearest.y + dy * limit / distance)
        }
        return CGPoint(x: center.x - width / 2, y: center.y - height / 2)
    }

    /// Whether the center or a corner of the rotated tile lies at least
    /// `depth` inside the screen. SwiftUI turns a positive angle clockwise.
    private static func reachesIntoScreen(center: CGPoint, width: CGFloat, height: CGFloat, angle: CGFloat, depth: CGFloat, screen: CGSize) -> Bool {
        let inner = CGRect(x: depth, y: depth, width: screen.width - 2 * depth, height: screen.height - 2 * depth)
        guard !inner.contains(center) else { return true }
        let cosine = cos(angle)
        let sine = sin(angle)
        for (x, y) in [(-width / 2, -height / 2), (width / 2, -height / 2), (width / 2, height / 2), (-width / 2, height / 2)] {
            let corner = CGPoint(x: center.x + x * cosine - y * sine, y: center.y + x * sine + y * cosine)
            if inner.contains(corner) { return true }
        }
        return false
    }
}

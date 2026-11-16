//
//  TileFramingState.swift
//  gridstream-ipad
//

import Foundation
import SwiftData
import CoreGraphics

@Model
final class TileFramingState {
    var id: UUID
    var index: Int
    var framingModeRawValue: String
    var customZoomLevel: Double
    var customPanOffsetX: Double
    var customPanOffsetY: Double

    // MARK: - Default Values

    static let defaultZoomLevel: Double = 1.0
    static let defaultPanOffset: Double = 0.0

    // MARK: - Initialization

    init(
        index: Int,
        framingMode: FramingMode = .fill,
        customZoomLevel: Double = defaultZoomLevel,
        customPanOffsetX: Double = defaultPanOffset,
        customPanOffsetY: Double = defaultPanOffset
    ) {
        self.id = UUID()
        self.index = index
        self.framingModeRawValue = framingMode.rawValue
        self.customZoomLevel = customZoomLevel
        self.customPanOffsetX = customPanOffsetX
        self.customPanOffsetY = customPanOffsetY
    }

    // MARK: - Computed Properties

    var framingMode: FramingMode {
        get { FramingMode(rawValue: framingModeRawValue) ?? .fill }
        set { framingModeRawValue = newValue.rawValue }
    }

    var customPanOffset: CGPoint {
        get { CGPoint(x: customPanOffsetX, y: customPanOffsetY) }
        set {
            customPanOffsetX = newValue.x
            customPanOffsetY = newValue.y
        }
    }

    // MARK: - Methods

    /// Resets custom framing to default values (zoom 1.0, pan offset 0,0)
    func resetCustomFraming() {
        customZoomLevel = Self.defaultZoomLevel
        customPanOffsetX = Self.defaultPanOffset
        customPanOffsetY = Self.defaultPanOffset
    }

    /// Cycles to the next framing mode
    func cycleMode() {
        framingMode = framingMode.next
    }
}

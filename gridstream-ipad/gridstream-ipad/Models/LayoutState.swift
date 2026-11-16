//
//  LayoutState.swift
//  gridstream-ipad
//

import Foundation
import SwiftData

@Model
final class LayoutState {
    var id: UUID
    var orientationRawValue: String
    var presetIdentifier: String?
    @Relationship(deleteRule: .cascade) var tileLayouts: [TileLayout]
    @Relationship(deleteRule: .cascade) var pipLayouts: [PiPLayoutEntry] = []

    var orientation: LayoutOrientation {
        get { LayoutOrientation(rawValue: orientationRawValue) ?? .horizontal }
        set { orientationRawValue = newValue.rawValue }
    }

    init(
        orientation: LayoutOrientation = .horizontal,
        presetIdentifier: String? = nil,
        tileLayouts: [TileLayout] = []
    ) {
        self.id = UUID()
        self.orientationRawValue = orientation.rawValue
        self.presetIdentifier = presetIdentifier
        self.tileLayouts = tileLayouts
    }

    static func createDefault() -> LayoutState {
        LayoutState(
            orientation: .horizontal,
            presetIdentifier: nil,
            tileLayouts: [TileLayout(index: 0)]
        )
    }

    // MARK: - PiP Layout Entry Helpers

    func pipLayout(forPiP pipIndex: Int, whenFullscreen fullscreenIndex: Int) -> PiPLayoutEntry? {
        pipLayouts.first { $0.pipTileIndex == pipIndex && $0.fullscreenTileIndex == fullscreenIndex }
    }

    func getOrCreatePipLayout(forPiP pipIndex: Int, whenFullscreen fullscreenIndex: Int) -> PiPLayoutEntry {
        if let existing = pipLayout(forPiP: pipIndex, whenFullscreen: fullscreenIndex) {
            return existing
        }
        let newLayout = PiPLayoutEntry(pipTileIndex: pipIndex, fullscreenTileIndex: fullscreenIndex, positionX: 0, positionY: 0)
        pipLayouts.append(newLayout)
        return newLayout
    }

    func setPipLayout(forPiP pipIndex: Int, whenFullscreen fullscreenIndex: Int, position: CGPoint, scale: Double, rotation: Double) {
        let layout = getOrCreatePipLayout(forPiP: pipIndex, whenFullscreen: fullscreenIndex)
        layout.updatePosition(position)
        layout.updateScale(scale)
        layout.updateRotation(rotation)
    }

    func pipLayouts(forFullscreen fullscreenIndex: Int) -> [Int: PiPLayoutEntry] {
        Dictionary(
            pipLayouts
                .filter { $0.fullscreenTileIndex == fullscreenIndex && $0.pipTileIndex >= 0 }
                .map { ($0.pipTileIndex, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func removePipLayouts(forPiP pipIndex: Int) {
        pipLayouts.removeAll { $0.pipTileIndex == pipIndex }
    }

    func removePipLayouts(whenFullscreen fullscreenIndex: Int) {
        pipLayouts.removeAll { $0.fullscreenTileIndex == fullscreenIndex }
    }

    func reindexPipLayouts(fromIndex: Int) {
        // Decrement indices >= fromIndex
        for layout in pipLayouts {
            if layout.pipTileIndex >= fromIndex {
                layout.pipTileIndex -= 1
            }
            if layout.fullscreenTileIndex >= fromIndex {
                layout.fullscreenTileIndex -= 1
            }
        }
        pipLayouts.removeAll { $0.pipTileIndex < 0 || $0.fullscreenTileIndex < 0 || $0.pipTileIndex == $0.fullscreenTileIndex }
    }
}

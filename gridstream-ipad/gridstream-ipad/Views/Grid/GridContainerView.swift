//
//  GridContainerView.swift
//  gridstream-ipad
//

import SwiftUI

struct GridContainerView: View {
    @Bindable var gridState: GridState
    var onTileTapped: ((Int) -> Void)?
    var onChangeVideo: ((Int) -> Void)?
    var onSelectVideo: ((Int) -> Void)?
    var onRemoveTile: ((Int) -> Void)?
    var onRandomVideo: ((Int) -> Void)?
    var onNextVideo: ((Int) -> Void)?
    var onNavigateBack: ((Int) -> Void)?
    var onNavigateForward: ((Int) -> Void)?
    var onFullscreen: ((Int) -> Void)?
    var onQuickAddToList: ((Int) -> Void)?
    var onAssignSmartList: ((Int) -> Void)?
    var smartListNameForTile: ((Int) -> String?)?
    var smartListVideoCountForTile: ((Int) -> Int?)?
    var simpleListNameForTile: ((Int) -> String?)?
    var simpleListVideoCountForTile: ((Int) -> Int?)?

    @State private var tileFrames: [CGRect] = []

    var body: some View {
        GeometryReader { geometry in
            let frames = calculateTileFrames(availableSize: geometry.size)
            let dividers = calculateDividers(frames: frames, availableSize: geometry.size)

            ZStack(alignment: .topLeading) {
                // Tile layer with native drag and drop
                tilesLayer(frames: frames)

                // Divider overlay layer (only for asymmetric presets)
                if shouldShowDividers {
                    dividerOverlayLayer(dividers: dividers, containerSize: geometry.size)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onAppear {
                tileFrames = frames
            }
            .onChange(of: frames) { _, newFrames in
                tileFrames = newFrames
            }
        }
    }

    // MARK: - Frame Calculation

    private func calculateTileFrames(availableSize: CGSize) -> [CGRect] {
        guard let preset = gridState.activePreset, preset != .symmetric else {
            // Use symmetric layout calculation with orientation support
            let layout = GridLayout.calculate(
                for: gridState.currentConfiguration,
                availableSize: availableSize,
                orientation: gridState.orientation
            )
            return gridState.tiles.map { tile in
                layout.frame(forIndex: tile.index)
            }
        }

        // Use asymmetric layout calculation
        let frames = AsymmetricLayoutCalculator.calculateFrames(
            preset: preset,
            orientation: gridState.orientation,
            availableSize: availableSize,
            tileLayouts: gridState.tileRatios
        )

        // Ensure we have enough frames for all tiles
        guard frames.count >= gridState.tiles.count else {
            // Fallback to symmetric if asymmetric doesn't provide enough frames
            let layout = GridLayout.calculate(
                for: gridState.currentConfiguration,
                availableSize: availableSize,
                orientation: gridState.orientation
            )
            return gridState.tiles.map { tile in
                layout.frame(forIndex: tile.index)
            }
        }

        return frames
    }

    private func calculateDividers(frames: [CGRect], availableSize: CGSize) -> [DividerPosition] {
        guard let preset = gridState.activePreset, preset != .symmetric else {
            return []
        }

        return DividerCalculator.calculateDividers(
            from: frames,
            preset: preset,
            orientation: gridState.orientation,
            availableSize: availableSize
        )
    }

    private var shouldShowDividers: Bool {
        guard let preset = gridState.activePreset else { return false }
        return preset != .symmetric
    }

    // MARK: - Framing State Access

    private func framingState(for tileIndex: Int) -> TileFramingState? {
        let sortedLayouts = gridState.tileRatios
        guard tileIndex < sortedLayouts.count else { return nil }
        let layout = sortedLayouts[tileIndex]
        layout.ensureFramingState()
        return layout.framingState
    }

    // MARK: - Tiles Layer

    @ViewBuilder
    private func tilesLayer(frames: [CGRect]) -> some View {
        ForEach(gridState.tiles) { tile in
            let frame = tile.index < frames.count ? frames[tile.index] : .zero

            TileView(
                tile: tile,
                isSelected: gridState.selectedTileIndex == tile.index,
                onTap: {
                    onTileTapped?(tile.index)
                },
                onChangeVideo: {
                    onChangeVideo?(tile.index)
                },
                onSelectVideo: {
                    onSelectVideo?(tile.index)
                },
                // nil on the last tile, so it shows no remove button.
                onRemove: onRemoveTile.map { remove in { remove(tile.index) } },
                onRandomVideo: {
                    onRandomVideo?(tile.index)
                },
                onNextVideo: {
                    onNextVideo?(tile.index)
                },
                endAction: gridState.endAction(at: tile.index),
                onEndActionChange: { action in
                    gridState.setEndAction(action, at: tile.index)
                },
                onNavigateBack: {
                    onNavigateBack?(tile.index)
                },
                onNavigateForward: {
                    onNavigateForward?(tile.index)
                },
                onFullscreen: {
                    onFullscreen?(tile.index)
                },
                onQuickAddToList: {
                    onQuickAddToList?(tile.index)
                },
                onAssignSmartList: {
                    onAssignSmartList?(tile.index)
                },
                smartListName: smartListNameForTile?(tile.index),
                smartListVideoCount: smartListVideoCountForTile?(tile.index),
                simpleListName: simpleListNameForTile?(tile.index),
                simpleListVideoCount: simpleListVideoCountForTile?(tile.index),
                framingState: framingState(for: tile.index)
            )
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
        }
    }

    // MARK: - Divider Overlay Layer

    @ViewBuilder
    private func dividerOverlayLayer(dividers: [DividerPosition], containerSize: CGSize) -> some View {
        DividerOverlayView(
            dividers: dividers,
            containerSize: containerSize,
            onDividerDrag: { dividerIndex, delta in
                handleDividerDrag(dividerIndex: dividerIndex, delta: delta, dividers: dividers)
            }
        )
        .allowsHitTesting(true)
    }

    // MARK: - Divider Drag Handling

    private func handleDividerDrag(dividerIndex: Int, delta: CGFloat, dividers: [DividerPosition]) {
        guard dividerIndex < dividers.count else { return }

        let divider = dividers[dividerIndex]
        let affectedIndices = divider.affectedTileIndices

        guard !affectedIndices.isEmpty else { return }

        // Calculate ratio change based on divider axis and delta
        switch divider.axis {
        case .vertical:
            handleVerticalDividerDrag(delta: delta, affectedIndices: affectedIndices)
        case .horizontal:
            handleHorizontalDividerDrag(delta: delta, affectedIndices: affectedIndices)
        }
    }

    private func handleVerticalDividerDrag(delta: CGFloat, affectedIndices: [Int]) {
        // For vertical dividers, we adjust width ratios
        // Delta > 0 means moving right (left tiles get bigger)
        // Delta < 0 means moving left (left tiles get smaller)

        guard let preset = gridState.activePreset, preset != .symmetric else { return }

        // Find the primary tile index (first affected tile)
        guard let primaryIndex = affectedIndices.first else { return }

        // Calculate ratio change based on current container width
        // Approximate: 1% ratio change per 10 pixels of delta
        let ratioChange = delta / 1000.0

        let currentRatio = gridState.tileRatios.first { $0.index == primaryIndex }?.widthRatio ?? 0.5
        let newRatio = currentRatio + ratioChange

        gridState.updateTileRatio(at: primaryIndex, widthRatio: newRatio, heightRatio: nil)
    }

    private func handleHorizontalDividerDrag(delta: CGFloat, affectedIndices: [Int]) {
        // For horizontal dividers, we adjust height ratios
        // Delta > 0 means moving down (top tiles get bigger)
        // Delta < 0 means moving up (top tiles get smaller)

        guard let preset = gridState.activePreset, preset != .symmetric else { return }

        // Find the primary tile index (first affected tile)
        guard let primaryIndex = affectedIndices.first else { return }

        // Calculate ratio change based on current container height
        let ratioChange = delta / 1000.0

        let currentRatio = gridState.tileRatios.first { $0.index == primaryIndex }?.heightRatio ?? 0.5
        let newRatio = currentRatio + ratioChange

        gridState.updateTileRatio(at: primaryIndex, widthRatio: nil, heightRatio: newRatio)
    }
}

// MARK: - Previews

#Preview {
    let state = GridState()
    return GridContainerView(gridState: state)
        .environment(GlobalPlaybackManager.shared)
        .environment(VideoHistoryManager())
        .padding()
}

#Preview("Four Tiles") {
    let state = GridState()
    state.setTileCount(4)
    return GridContainerView(gridState: state)
        .environment(GlobalPlaybackManager.shared)
        .environment(VideoHistoryManager())
        .padding()
}

#Preview("Asymmetric 1+2") {
    let state = GridState()
    state.setTileCount(3)
    state.setPreset(.onePlusTwo)
    return GridContainerView(gridState: state)
        .environment(GlobalPlaybackManager.shared)
        .environment(VideoHistoryManager())
        .padding()
}

#Preview("Asymmetric 2+1") {
    let state = GridState()
    state.setTileCount(3)
    state.setPreset(.twoPlusOne)
    return GridContainerView(gridState: state)
        .environment(GlobalPlaybackManager.shared)
        .environment(VideoHistoryManager())
        .padding()
}

#Preview("Asymmetric 1+3") {
    let state = GridState()
    state.setTileCount(4)
    state.setPreset(.onePlusThree)
    return GridContainerView(gridState: state)
        .environment(GlobalPlaybackManager.shared)
        .environment(VideoHistoryManager())
        .padding()
}

#Preview("Asymmetric Vertical Orientation") {
    let state = GridState()
    state.setTileCount(3)
    state.setPreset(.onePlusTwo)
    state.setOrientation(.vertical)
    return GridContainerView(gridState: state)
        .environment(GlobalPlaybackManager.shared)
        .environment(VideoHistoryManager())
        .padding()
}

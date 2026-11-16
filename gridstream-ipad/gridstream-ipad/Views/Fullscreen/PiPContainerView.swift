//
//  PiPContainerView.swift
//  gridstream-ipad
//

import OSLog
import SwiftUI

/// Transform data for a PiP tile (position, scale, rotation)
struct PiPTransform {
    let position: CGPoint
    let scale: CGFloat
    let rotation: CGFloat
}

struct PiPContainerView: View {
    let tiles: [Tile]
    let fullscreenTileIndex: Int
    let tileLayouts: [TileLayout]
    let pipLayouts: [PiPLayoutEntry]
    let playerStates: [Int: VideoPlayerState]
    let serverURL: URL?
    let onSwapToFullscreen: (Int, PiPTransform) -> Void  // (tileIndex, transform)
    let onPositionChanged: (Int, CGPoint) -> Void
    let onScaleChanged: (Int, CGFloat) -> Void
    let onRotationChanged: (Int, CGFloat) -> Void
    var recalculatePanTrigger: Bool = false  // When this changes to true, recalculate all pan values
    var dismissProgress: CGFloat = 0          // 0 = normal, 1 = fully dismissed
    var dismissCorner: DiagonalCorner = .topRight  // direction to dismiss toward
    var isPiPLayoutMemoryEnabled: Bool = false
    var layoutResetTrigger: Int = 0  // Changes when the saved layout was reset: back to default places
    @State private var pipPositions: [Int: CGPoint] = [:]
    @State private var pipScales: [Int: CGFloat] = [:]
    @State private var pipRotations: [Int: CGFloat] = [:]
    @State private var currentScreenWidth: CGFloat = 0
    @State private var currentScreenHeight: CGFloat = 0

    // Two-finger long press swap state
    @State private var pendingSwapTileIndex: Int?
    @State private var pendingSwapTimestamp: Date?
    @State private var swapDismissTrigger = UUID()

    // MARK: - Constants

    private static let verticalSpacing: CGFloat = 16
    private static let topOffset: CGFloat = 60
    private static let horizontalPadding: CGFloat = 16
    private static let widthRatio: CGFloat = 0.2
    private static let aspectRatio: CGFloat = 16.0 / 9.0

    // Scale constraints (must match PiPTileView)
    private static let minimumScale: CGFloat = 0.1
    private static let maximumScale: CGFloat = 0.4

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height

            ForEach(pipTileIndices, id: \.self) { tileIndex in
                if let playerState = playerStates[tileIndex] {
                    let tile = tiles.first(where: { $0.index == tileIndex })
                    let tileScale = pipScales[tileIndex] ?? Self.widthRatio
                    let pipWidth = screenWidth * tileScale
                    let pipHeight = pipWidth / Self.aspectRatio

                    PiPTileView(
                        tileIndex: tileIndex,
                        videoId: tile?.videoId,
                        playerState: playerState,
                        serverURL: serverURL,
                        screenWidth: screenWidth,
                        screenHeight: screenHeight,
                        onTapToSwap: {
                            // Pass current transform (position, scale, rotation) so old fullscreen can take this spot seamlessly
                            let currentPosition = pipPositions[tileIndex] ?? defaultPosition(for: tileIndex, pipWidth: pipWidth, pipHeight: pipHeight, geometry: geometry)
                            let currentScale = pipScales[tileIndex] ?? Self.widthRatio
                            let currentRotation = pipRotations[tileIndex] ?? 0
                            let transform = PiPTransform(position: currentPosition, scale: currentScale, rotation: currentRotation)
                            onSwapToFullscreen(tileIndex, transform)
                        },
                        onPositionChanged: { newPosition in
                            onPositionChanged(tileIndex, newPosition)
                        },
                        onScaleChanged: { newScale in
                            pipScales[tileIndex] = newScale
                            onScaleChanged(tileIndex, newScale)
                        },
                        onRotationChanged: { newRotation in
                            pipRotations[tileIndex] = newRotation
                            onRotationChanged(tileIndex, newRotation)
                        },
                        onLongPress: { handlePiPLongPress(tileIndex: tileIndex) },
                        swapDismissTrigger: swapDismissTrigger,
                        framingState: tileLayouts.first(where: { $0.index == tileIndex })?.framingState,
                        position: positionBinding(for: tileIndex, pipWidth: pipWidth, pipHeight: pipHeight, geometry: geometry),
                        scale: scaleBinding(for: tileIndex),
                        rotation: rotationBinding(for: tileIndex)
                    )
                    .offset(dismissOffset(for: tileIndex, pipWidth: pipWidth, pipHeight: pipHeight, screenWidth: screenWidth, screenHeight: screenHeight, geometry: geometry))
                    .opacity(1.0 - Double(dismissProgress) * 0.7)
                }
            }
            .onAppear {
                currentScreenWidth = screenWidth
                currentScreenHeight = screenHeight
                // Clamp positions once we have screen dimensions
                reclampAllPositions(screenWidth: screenWidth, screenHeight: screenHeight)
            }
            .onChange(of: geometry.size) { _, newSize in
                currentScreenWidth = newSize.width
                currentScreenHeight = newSize.height
                // Re-clamp all positions when screen size changes (rotation, etc.)
                reclampAllPositions(screenWidth: newSize.width, screenHeight: newSize.height)
            }
        }
        .onAppear {
            initializePositions()
        }
        .onChange(of: fullscreenTileIndex) { oldIndex, newIndex in
            if isPiPLayoutMemoryEnabled {
                // Animate ALL PiPs to their new positions for the new fullscreen context
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    for tileIndex in pipTileIndices {
                        // Look for saved position for this context
                        if let savedLayout = pipLayouts.first(where: {
                            $0.pipTileIndex == tileIndex && $0.fullscreenTileIndex == newIndex
                        }) {
                            pipPositions[tileIndex] = CGPoint(x: savedLayout.positionX, y: savedLayout.positionY)
                            pipScales[tileIndex] = CGFloat(savedLayout.scale)
                            pipRotations[tileIndex] = CGFloat(savedLayout.rotation)
                        } else {
                            // No saved position for this context - use default
                            let tileScale = Self.widthRatio
                            let pipWidth = currentScreenWidth * tileScale
                            let pipHeight = pipWidth / Self.aspectRatio
                            pipPositions[tileIndex] = defaultPosition(for: tileIndex, pipWidth: pipWidth, pipHeight: pipHeight, screenWidth: currentScreenWidth)
                            pipScales[tileIndex] = tileScale
                            pipRotations[tileIndex] = 0
                        }
                    }
                }
            } else {
                // Old behavior: only load the old fullscreen tile's layout
                if let layout = tileLayouts.first(where: { $0.index == oldIndex }),
                   layout.pipPosition != nil {
                    var position = layout.currentPiPPosition
                    let scale = layout.currentPiPScale

                    // Clamp the position to ensure it's visible on screen
                    if position != .zero && currentScreenWidth > 0 && currentScreenHeight > 0 {
                        let pipWidth = currentScreenWidth * scale
                        let pipHeight = pipWidth / Self.aspectRatio
                        position = clampToBounds(position, pipWidth: pipWidth, pipHeight: pipHeight, rotation: layout.currentPiPRotation, screenWidth: currentScreenWidth, screenHeight: currentScreenHeight)
                        pipPositions[oldIndex] = position
                        // Persist the clamped position if it changed
                        if position != layout.currentPiPPosition {
                            onPositionChanged(oldIndex, position)
                        }
                    } else if position != .zero {
                        pipPositions[oldIndex] = position
                    }

                    pipScales[oldIndex] = scale
                    pipRotations[oldIndex] = layout.currentPiPRotation
                }
            }
        }
        .onChange(of: layoutResetTrigger) { _, _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                pipPositions = [:]
                pipScales = [:]
                pipRotations = [:]
            }
            if StereoPanState.shared.isEnabled {
                recalculateAllPanValues()
            }
        }
        .onChange(of: recalculatePanTrigger) { _, shouldRecalculate in
            if shouldRecalculate {
                recalculateAllPanValues()
            }
        }
    }

    // MARK: - Computed Properties

    private var effectiveFullscreenIndex: Int {
        isPiPLayoutMemoryEnabled ? fullscreenTileIndex : 0
    }

    private var pipTileIndices: [Int] {
        tiles.map { $0.index }.filter { $0 != fullscreenTileIndex }
    }

    // MARK: - Position Management

    private func positionBinding(for tileIndex: Int, pipWidth: CGFloat, pipHeight: CGFloat, geometry: GeometryProxy) -> Binding<CGPoint> {
        let screenWidth = geometry.size.width
        let screenHeight = geometry.size.height

        return Binding(
            get: {
                let rawPosition: CGPoint
                if let position = pipPositions[tileIndex] {
                    rawPosition = position
                } else {
                    rawPosition = defaultPosition(for: tileIndex, pipWidth: pipWidth, pipHeight: pipHeight, geometry: geometry)
                }
                // Always clamp to ensure the position is valid
                return clampToBounds(rawPosition, pipWidth: pipWidth, pipHeight: pipHeight, rotation: pipRotations[tileIndex] ?? 0, screenWidth: screenWidth, screenHeight: screenHeight)
            },
            set: { newPosition in
                // Clamp before storing to prevent invalid positions from being persisted
                let clamped = clampToBounds(newPosition, pipWidth: pipWidth, pipHeight: pipHeight, rotation: pipRotations[tileIndex] ?? 0, screenWidth: screenWidth, screenHeight: screenHeight)
                pipPositions[tileIndex] = clamped
            }
        )
    }

    private func scaleBinding(for tileIndex: Int) -> Binding<CGFloat> {
        Binding(
            get: {
                let rawScale = pipScales[tileIndex] ?? Self.widthRatio
                // Clamp to valid range to prevent 0, negative, or out-of-bounds scales
                return clampScale(rawScale)
            },
            set: { newScale in
                // Clamp before storing
                pipScales[tileIndex] = clampScale(newScale)
            }
        )
    }

    /// Clamps scale to valid range (10% - 40%)
    private func clampScale(_ value: CGFloat) -> CGFloat {
        min(Self.maximumScale, max(Self.minimumScale, value))
    }

    private func rotationBinding(for tileIndex: Int) -> Binding<CGFloat> {
        Binding(
            get: {
                let rotation = pipRotations[tileIndex] ?? 0
                return rotation.isFinite ? rotation : 0
            },
            set: { pipRotations[tileIndex] = $0 }
        )
    }

    private func initializePositions() {
        if isPiPLayoutMemoryEnabled {
            // Load positions specific to current fullscreen context
            let layoutEntries = pipLayouts.filter { $0.fullscreenTileIndex == effectiveFullscreenIndex }
            for entry in layoutEntries {
                pipPositions[entry.pipTileIndex] = CGPoint(x: entry.positionX, y: entry.positionY)
                pipScales[entry.pipTileIndex] = CGFloat(entry.scale)
                pipRotations[entry.pipTileIndex] = CGFloat(entry.rotation)
            }
        } else {
            // Load persisted positions, scales, and rotations from tile layouts (legacy system)
            for layout in tileLayouts {
                if layout.pipPosition != nil {
                    let position = layout.currentPiPPosition
                    if position != .zero {
                        pipPositions[layout.index] = position
                    }
                    pipScales[layout.index] = layout.currentPiPScale
                    pipRotations[layout.index] = layout.currentPiPRotation
                }
            }
        }
    }

    /// Initializes and clamps positions when screen dimensions are available
    private func initializeAndClampPositions(screenWidth: CGFloat, screenHeight: CGFloat) {
        initializePositions()
        reclampAllPositions(screenWidth: screenWidth, screenHeight: screenHeight)
    }

    /// Recalculates pan values for all PiP tiles based on their current positions.
    /// Called when stereo panning is enabled to initialize pan values.
    private func recalculateAllPanValues() {
        guard currentScreenWidth > 0 else { return }

        for tileIndex in pipTileIndices {
            let tileScale = pipScales[tileIndex] ?? Self.widthRatio
            let pipWidth = currentScreenWidth * tileScale
            let pipHeight = pipWidth / Self.aspectRatio

            let position = pipPositions[tileIndex] ?? defaultPosition(
                for: tileIndex,
                pipWidth: pipWidth,
                pipHeight: pipHeight,
                screenWidth: currentScreenWidth
            )

            // Calculate pan value: tile center relative to screen center
            let tileCenter = position.x + pipWidth / 2
            let screenCenter = currentScreenWidth / 2
            let normalizedPan = Float((tileCenter - screenCenter) / screenCenter)
            let clampedPan = max(-0.9, min(0.9, normalizedPan))

            StereoPanState.shared.setPan(clampedPan, for: tileIndex)
        }
    }

    private func defaultPosition(for tileIndex: Int, pipWidth: CGFloat, pipHeight: CGFloat, geometry: GeometryProxy) -> CGPoint {
        return defaultPosition(for: tileIndex, pipWidth: pipWidth, pipHeight: pipHeight, screenWidth: geometry.size.width)
    }

    private func defaultPosition(for tileIndex: Int, pipWidth: CGFloat, pipHeight: CGFloat, screenWidth: CGFloat) -> CGPoint {
        let pipIndices = pipTileIndices
        guard let pipPosition = pipIndices.firstIndex(of: tileIndex) else {
            return CGPoint(x: Self.horizontalPadding, y: Self.topOffset)
        }

        let leftCount = (pipIndices.count + 1) / 2
        let isLeftColumn = pipPosition < leftCount

        let columnIndex: Int
        if isLeftColumn {
            columnIndex = pipPosition
        } else {
            columnIndex = pipPosition - leftCount
        }

        let x: CGFloat
        if isLeftColumn {
            x = Self.horizontalPadding
        } else {
            x = screenWidth - pipWidth - Self.horizontalPadding
        }

        let y = Self.topOffset + CGFloat(columnIndex) * (pipHeight + Self.verticalSpacing)

        return CGPoint(x: x, y: y)
    }

    // MARK: - Dismiss Offset

    /// Calculates the offset needed to slide a PiP tile toward its nearest screen edge,
    /// leaving 20% of the tile visible on screen at full dismiss.
    /// Each tile independently finds the shortest path to the closest border.
    private func dismissOffset(for tileIndex: Int, pipWidth: CGFloat, pipHeight: CGFloat, screenWidth: CGFloat, screenHeight: CGFloat, geometry: GeometryProxy) -> CGSize {
        guard dismissProgress > 0 else { return .zero }

        let position = pipPositions[tileIndex] ?? defaultPosition(for: tileIndex, pipWidth: pipWidth, pipHeight: pipHeight, geometry: geometry)
        let tileCenter = CGPoint(x: position.x + pipWidth / 2, y: position.y + pipHeight / 2)

        // Distance from tile center to each edge
        let distToLeft = tileCenter.x
        let distToRight = screenWidth - tileCenter.x
        let distToTop = tileCenter.y
        let distToBottom = screenHeight - tileCenter.y

        let minDist = min(distToLeft, distToRight, distToTop, distToBottom)

        // Offset that pushes the tile to the nearest edge, keeping 20% visible
        let dx: CGFloat
        let dy: CGFloat

        if minDist == distToLeft {
            dx = -(position.x + pipWidth * 0.8)  // slide left
            dy = 0
        } else if minDist == distToRight {
            dx = screenWidth - position.x - pipWidth * 0.2  // slide right
            dy = 0
        } else if minDist == distToTop {
            dx = 0
            dy = -(position.y + pipHeight * 0.8)  // slide up
        } else {
            dx = 0
            dy = screenHeight - position.y - pipHeight * 0.2  // slide down
        }

        return CGSize(width: dx * dismissProgress, height: dy * dismissProgress)
    }

    // MARK: - Bounds Clamping

    /// Clamps a position so the PiP, as turned, stays visible on screen.
    /// This prevents PiPs loaded from persistence from being off-screen and unrecoverable.
    private func clampToBounds(_ position: CGPoint, pipWidth: CGFloat, pipHeight: CGFloat, rotation: CGFloat, screenWidth: CGFloat, screenHeight: CGFloat) -> CGPoint {
        PiPBounds.clamp(position, width: pipWidth, height: pipHeight, rotation: rotation, screen: CGSize(width: screenWidth, height: screenHeight))
    }

    /// Re-clamps all positions when screen size changes or positions are loaded from persistence
    private func reclampAllPositions(screenWidth: CGFloat, screenHeight: CGFloat) {
        for tileIndex in pipTileIndices {
            let tileScale = pipScales[tileIndex] ?? Self.widthRatio
            let pipWidth = screenWidth * tileScale
            let pipHeight = pipWidth / Self.aspectRatio

            if let existingPosition = pipPositions[tileIndex] {
                let clampedPosition = clampToBounds(existingPosition, pipWidth: pipWidth, pipHeight: pipHeight, rotation: pipRotations[tileIndex] ?? 0, screenWidth: screenWidth, screenHeight: screenHeight)
                if clampedPosition != existingPosition {
                    AppLogger.pip.notice("PiP \(tileIndex) brought back on screen: (\(existingPosition.x), \(existingPosition.y)) -> (\(clampedPosition.x), \(clampedPosition.y)), screen \(screenWidth)x\(screenHeight)")
                    pipPositions[tileIndex] = clampedPosition
                    onPositionChanged(tileIndex, clampedPosition)
                }
            }
        }
    }

    // MARK: - Two-Finger Long Press PiP Swap

    /// Handles a long press on a PiP tile. If two PiP tiles are long-pressed
    /// within a short time window, their transforms are swapped.
    private func handlePiPLongPress(tileIndex: Int) {
        let now = Date()

        if let pendingIndex = pendingSwapTileIndex,
           let timestamp = pendingSwapTimestamp,
           now.timeIntervalSince(timestamp) < 0.8,
           pendingIndex != tileIndex {
            // Two PiPs long-pressed within window — swap their transforms
            swapPiPTransforms(pendingIndex, tileIndex)
            pendingSwapTileIndex = nil
            pendingSwapTimestamp = nil
        } else {
            // First long press — wait for a potential second
            pendingSwapTileIndex = tileIndex
            pendingSwapTimestamp = now

            // Clear pending after timeout (normal long press behavior proceeds)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if pendingSwapTileIndex == tileIndex {
                    pendingSwapTileIndex = nil
                    pendingSwapTimestamp = nil
                }
            }
        }
    }

    /// Swaps position, scale, and rotation between two PiP tiles with animation.
    private func swapPiPTransforms(_ indexA: Int, _ indexB: Int) {
        let defaultScaleA = Self.widthRatio
        let defaultScaleB = Self.widthRatio

        let posA = pipPositions[indexA] ?? defaultPosition(for: indexA, pipWidth: currentScreenWidth * defaultScaleA, pipHeight: currentScreenWidth * defaultScaleA / Self.aspectRatio, screenWidth: currentScreenWidth)
        let posB = pipPositions[indexB] ?? defaultPosition(for: indexB, pipWidth: currentScreenWidth * defaultScaleB, pipHeight: currentScreenWidth * defaultScaleB / Self.aspectRatio, screenWidth: currentScreenWidth)
        let scaleA = pipScales[indexA] ?? Self.widthRatio
        let scaleB = pipScales[indexB] ?? Self.widthRatio
        let rotA = pipRotations[indexA] ?? 0
        let rotB = pipRotations[indexB] ?? 0

        // Dismiss any open control panels
        swapDismissTrigger = UUID()

        // Animate the swap
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            pipPositions[indexA] = posB
            pipPositions[indexB] = posA
            pipScales[indexA] = scaleB
            pipScales[indexB] = scaleA
            pipRotations[indexA] = rotB
            pipRotations[indexB] = rotA
        }

        // Persist the swapped values
        onPositionChanged(indexA, posB)
        onPositionChanged(indexB, posA)
        onScaleChanged(indexA, scaleB)
        onScaleChanged(indexB, scaleA)
        onRotationChanged(indexA, rotB)
        onRotationChanged(indexB, rotA)

        // Update stereo pan values for new positions
        if StereoPanState.shared.isEnabled {
            let pipWidthA = currentScreenWidth * scaleB  // A now has B's scale
            let tileCenterA = posB.x + pipWidthA / 2
            let pipWidthB = currentScreenWidth * scaleA  // B now has A's scale
            let tileCenterB = posA.x + pipWidthB / 2
            let screenCenter = currentScreenWidth / 2

            let panA = max(-0.9, min(0.9, Float((tileCenterA - screenCenter) / screenCenter)))
            let panB = max(-0.9, min(0.9, Float((tileCenterB - screenCenter) / screenCenter)))
            StereoPanState.shared.setPan(panA, for: indexA)
            StereoPanState.shared.setPan(panB, for: indexB)
        }
    }
}

#Preview {
    let tiles = [
        Tile(index: 0, videoURL: URL(string: "http://localhost:8080/api/v1/videos/1/stream")),
        Tile(index: 1, videoURL: URL(string: "http://localhost:8080/api/v1/videos/2/stream")),
        Tile(index: 2, videoURL: URL(string: "http://localhost:8080/api/v1/videos/3/stream")),
        Tile(index: 3, videoURL: URL(string: "http://localhost:8080/api/v1/videos/4/stream"))
    ]

    ZStack {
        Color.black

        PiPContainerView(
            tiles: tiles,
            fullscreenTileIndex: 0,
            tileLayouts: [],
            pipLayouts: [],
            playerStates: [1: VideoPlayerState(), 2: VideoPlayerState(), 3: VideoPlayerState()],
            serverURL: nil,
            onSwapToFullscreen: { _, _ in },  // (index, transform)
            onPositionChanged: { _, _ in },
            onScaleChanged: { _, _ in },
            onRotationChanged: { _, _ in }
        )
    }
    .ignoresSafeArea()
}

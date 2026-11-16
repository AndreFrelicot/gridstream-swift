//
//  PiPTileView.swift
//  gridstream-ipad
//

import SwiftUI
import OSLog

struct PiPTileView: View {
    private enum ControlPanelPlacement: CaseIterable {
        case left
        case right
        case top
        case bottom
    }

    let tileIndex: Int
    let videoId: String?
    let playerState: VideoPlayerState
    let serverURL: URL?
    let screenWidth: CGFloat
    let screenHeight: CGFloat
    let onTapToSwap: () -> Void
    let onPositionChanged: (CGPoint) -> Void
    let onScaleChanged: (CGFloat) -> Void
    let onRotationChanged: (CGFloat) -> Void
    var onLongPress: (() -> Void)?
    var swapDismissTrigger: UUID = UUID()
    var framingState: TileFramingState?

    @Binding var position: CGPoint
    @Binding var scale: CGFloat  // Width ratio: 0.1 to 0.4
    @Binding var rotation: CGFloat  // Rotation in radians

    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero

    // Gesture state for pinch and rotation
    @State private var isPinching = false
    @State private var pinchScale: CGFloat = 1.0
    @State private var pinchCenterOffset: CGSize = .zero  // Offset to keep center fixed during pinch
    @State private var isRotating = false
    @State private var rotationAngle: Angle = .zero

    // Long press to show control panel
    @State private var showControlPanel = false
    @State private var controlPanelSize = CGSize(width: 120, height: 220)

    // Audio state (synced from TileAudioStateManager)
    // Mute and solo are read from the tile's shared audio state
    private var isMuted: Bool { audioStateManager.isMuted(for: tileIndex) }
    private var isSolo: Bool { audioStateManager.isSolo(for: tileIndex) }
    @State private var overrideVolume: Float = 1.0

    private var currentFramingMode: FramingMode {
        framingState?.framingMode ?? .fill
    }

    private var currentZoomLevel: CGFloat {
        CGFloat(framingState?.customZoomLevel ?? 1.0)
    }

    private var currentPanOffset: CGPoint {
        framingState?.customPanOffset ?? .zero
    }

    private let audioStateManager = TileAudioStateManager.shared

    // MARK: - Constants

    private static let aspectRatio: CGFloat = 16.0 / 9.0
    private static let cornerRadius: CGFloat = 8
    private static let shadowRadius: CGFloat = 4
    private static let dragScale: CGFloat = 1.05
    private static let normalScale: CGFloat = 1.0

    // Scale constraints
    private static let minimumScale: CGFloat = 0.1
    private static let maximumScale: CGFloat = 0.4
    private static let defaultScale: CGFloat = 0.2

    private static let controlPanelSpacing: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            // Use the bound scale, adjusted by current pinch gesture
            let currentScale = clampScale(scale * pinchScale)
            let pipWidth = geometry.size.width * currentScale
            let pipHeight = pipWidth / Self.aspectRatio

            pipContent(width: pipWidth, height: pipHeight)
                .rotationEffect(Angle(radians: rotation) + rotationAngle)
                .position(
                    x: position.x + pipWidth / 2 + dragOffset.width + pinchCenterOffset.width,
                    y: position.y + pipHeight / 2 + dragOffset.height + pinchCenterOffset.height
                )
                .gesture(combinedGesture)
        }
        .onAppear {
            loadAudioState()
        }
        .onChange(of: showControlPanel) { _, isShowing in
            if isShowing {
                loadAudioState()  // Refresh audio state when panel opens
            }
        }
        .onChange(of: swapDismissTrigger) { _, _ in
            // Dismiss control panel when a PiP swap occurs
            if showControlPanel {
                withAnimation(.easeOut(duration: 0.2)) {
                    showControlPanel = false
                }
            }
        }
    }

    // MARK: - PiP Content

    private func pipContent(width: CGFloat, height: CGFloat) -> some View {
        videoSurface(width: width, height: height)
            .overlay {
                if showControlPanel {
                    centeredPlaybackButton
                }
            }
            .overlay(alignment: .topLeading) {
                if showControlPanel {
                    controlPanel
                        .fixedSize()
                        .background(
                            GeometryReader { geometry in
                                Color.clear
                                    .onAppear {
                                        updateControlPanelSize(geometry.size)
                                    }
                                    .onChange(of: geometry.size) { _, newSize in
                                        updateControlPanelSize(newSize)
                                    }
                            }
                        )
                        .offset(controlPanelOffset(pipWidth: width, pipHeight: height))
                }
            }
    }

    private func videoSurface(width: CGFloat, height: CGFloat) -> some View {
        VideoPlayerView(
                playerState: playerState,
                framingMode: currentFramingMode,
                customScale: currentZoomLevel,
                customOffset: currentPanOffset
            )
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
            .shadow(radius: Self.shadowRadius)
            .scaleEffect(isDragging ? Self.dragScale : Self.normalScale)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
            .contentShape(Rectangle())
            .onTapGesture {
                if showControlPanel {
                    // Dismiss control panel on tap
                    withAnimation(.easeOut(duration: 0.2)) {
                        showControlPanel = false
                    }
                } else {
                    onTapToSwap()
                }
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                onLongPress?()
                withAnimation(.easeOut(duration: 0.2)) {
                    showControlPanel = true
                }
            }
    }

    // MARK: - Control Panel

    private var controlPanel: some View {
        VStack(spacing: 8) {
            // Reuse existing AudioControlPopoverContent for audio controls
            AudioControlPopoverContent(
                volume: $overrideVolume,
                isMuted: .constant(isMuted),
                isSolo: .constant(isSolo),
                onVolumeChanged: handleVolumeChange,
                onMuteToggle: handleMuteToggle,
                onSoloToggle: handleSoloToggle,
                onSoloLongPress: handleExclusiveSolo,
                onDismiss: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showControlPanel = false
                    }
                }
            )

            // Reset buttons row (only show if needed)
            if rotation != 0 || abs(scale - Self.defaultScale) > 0.01 {
                resetButtonsRow
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private var centeredPlaybackButton: some View {
        Button(action: handlePlaybackToggle) {
            Image(systemName: playerState.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(.black.opacity(0.55))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playerState.isPlaying ? "Pause PiP video" : "Play PiP video")
    }

    private func controlPanelOffset(pipWidth: CGFloat, pipHeight: CGFloat) -> CGSize {
        let placement = preferredControlPanelPlacement(pipWidth: pipWidth, pipHeight: pipHeight)
        let offset: CGSize

        switch placement {
        case .left:
            offset = CGSize(
                width: -controlPanelSize.width - Self.controlPanelSpacing,
                height: clampedVerticalOffset(for: pipHeight)
            )
        case .right:
            offset = CGSize(
                width: pipWidth + Self.controlPanelSpacing,
                height: clampedVerticalOffset(for: pipHeight)
            )
        case .top:
            offset = CGSize(
                width: clampedHorizontalOffset(for: pipWidth),
                height: -controlPanelSize.height - Self.controlPanelSpacing
            )
        case .bottom:
            offset = CGSize(
                width: clampedHorizontalOffset(for: pipWidth),
                height: pipHeight + Self.controlPanelSpacing
            )
        }

        return offset
    }

    private func preferredControlPanelPlacement(pipWidth: CGFloat, pipHeight: CGFloat) -> ControlPanelPlacement {
        let placements: [ControlPanelPlacement] = [.left, .right, .top, .bottom]
        let fittingPlacement = placements.first {
            fitsControlPanel($0, pipWidth: pipWidth, pipHeight: pipHeight)
        }

        if let fittingPlacement {
            return fittingPlacement
        }

        return placements.max(by: {
            availableSpace(for: $0, pipWidth: pipWidth, pipHeight: pipHeight)
                < availableSpace(for: $1, pipWidth: pipWidth, pipHeight: pipHeight)
        }) ?? .right
    }

    private func fitsControlPanel(_ placement: ControlPanelPlacement, pipWidth: CGFloat, pipHeight: CGFloat) -> Bool {
        switch placement {
        case .left:
            return position.x >= controlPanelSize.width + Self.controlPanelSpacing
        case .right:
            return screenWidth - (position.x + pipWidth) >= controlPanelSize.width + Self.controlPanelSpacing
        case .top:
            return position.y >= controlPanelSize.height + Self.controlPanelSpacing
        case .bottom:
            return screenHeight - (position.y + pipHeight) >= controlPanelSize.height + Self.controlPanelSpacing
        }
    }

    private func availableSpace(for placement: ControlPanelPlacement, pipWidth: CGFloat, pipHeight: CGFloat) -> CGFloat {
        switch placement {
        case .left:
            return position.x
        case .right:
            return screenWidth - (position.x + pipWidth)
        case .top:
            return position.y
        case .bottom:
            return screenHeight - (position.y + pipHeight)
        }
    }

    private func clampedVerticalOffset(for pipHeight: CGFloat) -> CGFloat {
        let centeredOffset = (pipHeight - controlPanelSize.height) / 2
        let minOffset = -position.y
        let maxOffset = screenHeight - position.y - controlPanelSize.height
        return min(max(centeredOffset, minOffset), maxOffset)
    }

    private func clampedHorizontalOffset(for pipWidth: CGFloat) -> CGFloat {
        let centeredOffset = (pipWidth - controlPanelSize.width) / 2
        let minOffset = -position.x
        let maxOffset = screenWidth - position.x - controlPanelSize.width
        return min(max(centeredOffset, minOffset), maxOffset)
    }

    private func updateControlPanelSize(_ newSize: CGSize) {
        guard newSize.width > 0, newSize.height > 0, controlPanelSize != newSize else { return }
        controlPanelSize = newSize
    }

    // MARK: - Reset Buttons Row

    private var resetButtonsRow: some View {
        HStack(spacing: 8) {
            // Reset Rotation button (only show if rotated)
            if rotation != 0 {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        rotation = 0
                    }
                    onRotationChanged(0)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "rotate.left")
                            .font(.system(size: 12, weight: .medium))
                        Text("Rotation")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.9))
                    .clipShape(Capsule())
                }
            }

            // Reset Scale button (only show if not at default)
            if abs(scale - Self.defaultScale) > 0.01 {
                Button {
                    let pipWidth = screenWidth * Self.defaultScale
                    let pipHeight = pipWidth / Self.aspectRatio
                    let clampedPosition = clampToBounds(position, pipWidth: pipWidth, pipHeight: pipHeight)

                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        scale = Self.defaultScale
                        if clampedPosition != position {
                            position = clampedPosition
                            onPositionChanged(clampedPosition)
                        }
                    }
                    onScaleChanged(Self.defaultScale)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .medium))
                        Text("Size")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.9))
                    .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Audio Handlers

    private func loadAudioState() {
        let state = audioStateManager.state(for: tileIndex)
        overrideVolume = state.isVolumeOverrideActive ? state.overrideVolume : 1.0
    }

    private func handleVolumeChange(_ newVolume: Float) {
        audioStateManager.setVolumeOverride(active: true, level: newVolume, for: tileIndex)
        playerState.setVolume(newVolume)
    }

    private func handleMuteToggle() {
        let muted = !isMuted
        audioStateManager.setMuted(muted, for: tileIndex)

        playerState.setMuted(muted)
    }

    private func handleSoloToggle() {
        GlobalPlaybackManager.shared.setSolo(!isSolo, for: playerState)
    }

    private func handleExclusiveSolo() {
        GlobalPlaybackManager.shared.exclusiveSolo(for: playerState)
    }

    private func handlePlaybackToggle() {
        if playerState.isPlaying {
            playerState.pause()
        } else {
            playerState.play()
        }
    }

    // MARK: - Combined Gesture

    private var combinedGesture: some Gesture {
        // Combine drag, magnification (pinch), and rotation gestures
        dragGesture
            .simultaneously(with: magnificationGesture)
            .simultaneously(with: rotationGesture)
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isDragging = true

                // Clamp the visual position during drag to prevent going off-screen
                var clampedOffset = value.translation
                if screenWidth > 0 && screenHeight > 0 {
                    let pipWidth = screenWidth * scale
                    let pipHeight = pipWidth / Self.aspectRatio
                    let visualPosition = CGPoint(
                        x: position.x + value.translation.width,
                        y: position.y + value.translation.height
                    )
                    let clampedPosition = clampToBounds(visualPosition, pipWidth: pipWidth, pipHeight: pipHeight)
                    clampedOffset = CGSize(
                        width: clampedPosition.x - position.x,
                        height: clampedPosition.y - position.y
                    )
                }
                dragOffset = clampedOffset

                // Update pan value in real-time during drag
                let currentPosition = CGPoint(
                    x: position.x + clampedOffset.width,
                    y: position.y + clampedOffset.height
                )
                updatePanValue(forPosition: currentPosition)
            }
            .onEnded { value in
                // Guard against invalid screen dimensions
                guard screenWidth > 0, screenHeight > 0 else {
                    isDragging = false
                    dragOffset = .zero
                    return
                }

                // Calculate PiP dimensions for bounds clamping
                let pipWidth = screenWidth * scale
                let pipHeight = pipWidth / Self.aspectRatio

                // Calculate new position
                var newPosition = CGPoint(
                    x: position.x + value.translation.width,
                    y: position.y + value.translation.height
                )

                // Clamp to keep at least 20% visible
                newPosition = clampToBounds(newPosition, pipWidth: pipWidth, pipHeight: pipHeight)

                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isDragging = false
                    position = newPosition
                    dragOffset = .zero
                }

                onPositionChanged(newPosition)
                logTransform("drag ended", position: newPosition, scale: scale, rotation: liveRotation)

                // Calculate and update pan value for stereo panning
                updatePanValue(forPosition: newPosition)
            }
    }

    // MARK: - Magnification (Pinch) Gesture

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                isPinching = true
                // Clamp the pinch scale to prevent going out of bounds during gesture
                let clampedValue = clampScale(scale * value) / scale
                pinchScale = clampedValue

                // Calculate offset to keep visual center fixed during pinch
                // Original pipWidth = screenWidth * scale, new pipWidth = screenWidth * scale * clampedValue
                // The difference in half-width is what we need to offset
                let originalPipWidth = screenWidth * scale
                let originalPipHeight = originalPipWidth / Self.aspectRatio
                let newPipWidth = screenWidth * scale * clampedValue
                let newPipHeight = newPipWidth / Self.aspectRatio

                var desiredOffset = CGSize(
                    width: (originalPipWidth - newPipWidth) / 2,
                    height: (originalPipHeight - newPipHeight) / 2
                )

                // Clamp the visual position during pinch to prevent going off-screen
                if screenWidth > 0 && screenHeight > 0 {
                    let visualPosition = CGPoint(
                        x: position.x + desiredOffset.width,
                        y: position.y + desiredOffset.height
                    )
                    let clampedVisualPosition = clampToBounds(
                        visualPosition,
                        pipWidth: newPipWidth,
                        pipHeight: newPipHeight
                    )
                    desiredOffset = CGSize(
                        width: clampedVisualPosition.x - position.x,
                        height: clampedVisualPosition.y - position.y
                    )
                }

                pinchCenterOffset = desiredOffset
            }
            .onEnded { value in
                // Guard against invalid screen dimensions
                guard screenWidth > 0, screenHeight > 0 else {
                    isPinching = false
                    pinchScale = 1.0
                    pinchCenterOffset = .zero
                    return
                }

                // Calculate new scale (clamped to valid range, no snapping)
                let newScale = clampScale(scale * value)

                // Calculate the final position adjustment based on scale change
                // This shifts the top-left corner so the center stays in place
                let originalPipWidth = screenWidth * scale
                let originalPipHeight = originalPipWidth / Self.aspectRatio
                let newPipWidth = screenWidth * newScale
                let newPipHeight = newPipWidth / Self.aspectRatio

                // First, ensure the starting position is valid (clamp it)
                let clampedStartPosition = clampToBounds(position, pipWidth: originalPipWidth, pipHeight: originalPipHeight)

                // Calculate new position from the clamped starting position
                var newPosition = CGPoint(
                    x: clampedStartPosition.x + (originalPipWidth - newPipWidth) / 2,
                    y: clampedStartPosition.y + (originalPipHeight - newPipHeight) / 2
                )

                // Clamp the final position to keep at least 20% visible
                newPosition = clampToBounds(newPosition, pipWidth: newPipWidth, pipHeight: newPipHeight)

                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isPinching = false
                    pinchScale = 1.0
                    pinchCenterOffset = .zero
                    scale = newScale
                    position = newPosition
                }

                onPositionChanged(newPosition)
                onScaleChanged(newScale)
                logTransform("pinch ended", position: newPosition, scale: newScale, rotation: liveRotation)
            }
    }

    // MARK: - Rotation Gesture

    private var rotationGesture: some Gesture {
        RotationGesture()
            .onChanged { angle in
                isRotating = true
                rotationAngle = angle
            }
            .onEnded { angle in
                let newRotation = rotation + angle.radians
                // Turned, the picture covers another part of its frame: keep
                // it on screen.
                let pipWidth = screenWidth * scale
                let newPosition = clampToBounds(position, pipWidth: pipWidth, pipHeight: pipWidth / Self.aspectRatio, rotation: newRotation)
                let moved = newPosition != position

                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isRotating = false
                    rotationAngle = .zero
                    rotation = newRotation
                    if moved {
                        position = newPosition
                    }
                }

                onRotationChanged(newRotation)
                if moved {
                    onPositionChanged(newPosition)
                }
                logTransform("rotation ended", position: newPosition, scale: scale, rotation: newRotation)
            }
    }

    // MARK: - Scale Helpers

    /// Clamps scale to valid range (10% - 40%)
    private func clampScale(_ value: CGFloat) -> CGFloat {
        min(Self.maximumScale, max(Self.minimumScale, value))
    }

    // MARK: - Bounds Clamping

    /// The rotation shown right now, a rotation gesture included.
    private var liveRotation: CGFloat {
        rotation + rotationAngle.radians
    }

    /// Clamps position so the PiP, as turned, stays visible on screen and can
    /// be grabbed again.
    private func clampToBounds(_ position: CGPoint, pipWidth: CGFloat, pipHeight: CGFloat, rotation: CGFloat? = nil) -> CGPoint {
        PiPBounds.clamp(
            position,
            width: pipWidth,
            height: pipHeight,
            rotation: rotation ?? liveRotation,
            screen: CGSize(width: screenWidth, height: screenHeight)
        )
    }

    /// One line per finished gesture, to retrace how a PiP reached a place.
    private func logTransform(_ event: String, position: CGPoint, scale: CGFloat, rotation: CGFloat) {
        AppLogger.pip.info("PiP \(tileIndex) \(event, privacy: .public): position=(\(position.x), \(position.y)) scale=\(scale) rotation=\(rotation) screen=\(screenWidth)x\(screenHeight)")
    }

    // MARK: - Stereo Panning

    /// Calculates and updates the pan value based on tile position relative to screen center.
    /// Pan ranges from -1.0 (full left) to 1.0 (full right), clamped to -0.9 to 0.9.
    private func updatePanValue(forPosition position: CGPoint) {
        let pipWidth = screenWidth * scale
        let tileCenter = position.x + pipWidth / 2
        let screenCenter = screenWidth / 2

        // Calculate normalized pan value (-1.0 to 1.0)
        let normalizedPan = Float((tileCenter - screenCenter) / screenCenter)

        // Clamp to -0.9 to 0.9 to avoid complete silence on one channel
        let clampedPan = max(-0.9, min(0.9, normalizedPan))

        StereoPanState.shared.setPan(clampedPan, for: tileIndex)
    }
}

#Preview {
    ZStack {
        Color.gray

        PiPTileView(
            tileIndex: 0,
            videoId: nil,
            playerState: VideoPlayerState(),
            serverURL: nil,
            screenWidth: 1024,
            screenHeight: 768,
            onTapToSwap: {},
            onPositionChanged: { _ in },
            onScaleChanged: { _ in },
            onRotationChanged: { _ in },
            position: .constant(CGPoint(x: 16, y: 60)),
            scale: .constant(0.2),
            rotation: .constant(0)
        )
    }
    .ignoresSafeArea()
}

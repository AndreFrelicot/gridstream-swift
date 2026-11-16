//
//  CustomSeekSlider.swift
//  gridstream-ipad
//
//  A custom seek slider using DragGesture for 100% reliable scrubbing callbacks.
//  This bypasses SwiftUI's Slider's unreliable onEditingChanged behavior.
//

import SwiftUI

struct CustomSeekSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var thumbColor: Color = .white
    var cachedRanges: [ClosedRange<Double>] = []
    var timeRanges: [(range: ClosedRange<Double>, color: Color)] = []
    /// When true, ToI segments show static dashes
    var isToIMode: Bool = false
    /// Capture marker positions (timestamps) — yellow diamonds on the track
    var captureMarkerPositions: [Double] = []
    /// Pending range being defined — shows animated marching ants
    var pendingRange: ClosedRange<Double>? = nil
    /// Editing range — the matching ToI segment animates with marching ants
    var editingRange: ClosedRange<Double>? = nil
    let onScrubStart: () -> Void
    let onScrubbing: (Double) -> Void
    let onScrubEnd: (Double, ScrubLevel) -> Void
    /// Optional callback for scrub level state changes (level, yOffset, anchorValue)
    var onScrubLevelChanged: ((ScrubLevel, CGFloat, Double) -> Void)? = nil
    /// Frame duration in seconds (1/fps), used for frame-by-frame scrubbing
    var frameDuration: Double = 1.0 / 24.0

    @State private var isDragging = false
    @State private var visualProgress: CGFloat?
    @State private var marchingAntsPhase: CGFloat = 0

    // Multi-level scrubbing state
    @State private var dragStartY: CGFloat = 0
    @State private var scrubLevel: ScrubLevel = .normal
    @State private var precisionAnchorValue: Double = 0
    @State private var precisionAnchorX: CGFloat = 0

    private let trackHeight: CGFloat = 6
    private let thumbSize: CGFloat = 16
    private let hitAreaHeight: CGFloat = 44

    // Level thresholds (deltaY is negative when moving up)
    private let precisionActivationThreshold: CGFloat = -50    // 50pt up → precision
    private let precisionDeactivationThreshold: CGFloat = -20  // hysteresis to exit precision
    private let frameByFrameActivationThreshold: CGFloat = -120 // 120pt up → frame-by-frame
    private let frameByFrameDeactivationThreshold: CGFloat = -80 // hysteresis to drop to precision
    private let precisionFactor: Double = 10.0                  // 1/10th range
    private let framePixelRatio: Double = 4.0                   // pixels per frame in frame-by-frame mode

    private var valueProgress: CGFloat {
        guard range.upperBound > range.lowerBound else { return 0 }
        let progress = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
        return max(0, min(1, progress))
    }

    private var currentProgress: CGFloat {
        visualProgress ?? valueProgress
    }

    /// Whether the marching ants animation should run
    private var shouldAnimate: Bool {
        pendingRange != nil || editingRange != nil
    }

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = geometry.size.width
            let fillWidth = currentProgress * trackWidth

            // Use ZStack for precise layering and positioning
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: trackHeight)

                // Filled portion (elapsed time)
                Capsule()
                    .fill(Color.white)
                    .frame(width: fillWidth, height: trackHeight)

                // Cached segments overlay (orange) - rendered on top of both background and filled
                ForEach(Array(cachedRanges.enumerated()), id: \.offset) { _, cachedRange in
                    let rangeSpan = range.upperBound - range.lowerBound
                    // Clamp cached range to slider's range to handle duration mismatches
                    let clampedLower = max(cachedRange.lowerBound, range.lowerBound)
                    let clampedUpper = min(cachedRange.upperBound, range.upperBound)
                    let startProgress = rangeSpan > 0 ? (clampedLower - range.lowerBound) / rangeSpan : 0
                    let endProgress = rangeSpan > 0 ? (clampedUpper - range.lowerBound) / rangeSpan : 0
                    let startX = CGFloat(max(0, min(1, startProgress))) * trackWidth
                    let segmentWidth = CGFloat(max(0, min(1, endProgress - startProgress))) * trackWidth

                    Capsule()
                        .fill(Color.orange.opacity(0.7))
                        .frame(width: max(segmentWidth, 3), height: trackHeight)
                        .offset(x: startX)
                }

                // Time-of-interest range segments (colored per range)
                ForEach(Array(timeRanges.enumerated()), id: \.offset) { _, toiRange in
                    let rangeSpan = range.upperBound - range.lowerBound
                    let clampedLower = max(toiRange.range.lowerBound, range.lowerBound)
                    let clampedUpper = min(toiRange.range.upperBound, range.upperBound)
                    let startProgress = rangeSpan > 0 ? (clampedLower - range.lowerBound) / rangeSpan : 0
                    let endProgress = rangeSpan > 0 ? (clampedUpper - range.lowerBound) / rangeSpan : 0
                    let startX = CGFloat(max(0, min(1, startProgress))) * trackWidth
                    let segmentWidth = CGFloat(max(0, min(1, endProgress - startProgress))) * trackWidth

                    Capsule()
                        .fill(toiRange.color)
                        .frame(width: max(segmentWidth, 3), height: trackHeight)
                        .overlay {
                            if isToIMode {
                                // Static dashes on committed ranges
                                Capsule()
                                    .strokeBorder(style: StrokeStyle(
                                        lineWidth: 1.5,
                                        dash: [4, 3]
                                    ))
                                    .foregroundStyle(.black)
                                    .frame(height: trackHeight)
                            }
                        }
                        .offset(x: startX)
                }

                // Pending range preview (animated marching ants)
                if let pending = pendingRange {
                    let rangeSpan = range.upperBound - range.lowerBound
                    let clampedLower = max(pending.lowerBound, range.lowerBound)
                    let clampedUpper = min(pending.upperBound, range.upperBound)
                    let startProgress = rangeSpan > 0 ? (clampedLower - range.lowerBound) / rangeSpan : 0
                    let endProgress = rangeSpan > 0 ? (clampedUpper - range.lowerBound) / rangeSpan : 0
                    let startX = CGFloat(max(0, min(1, startProgress))) * trackWidth
                    let segmentWidth = CGFloat(max(0, min(1, endProgress - startProgress))) * trackWidth

                    Capsule()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: max(segmentWidth, 3), height: trackHeight)
                        .overlay {
                            Capsule()
                                .strokeBorder(style: StrokeStyle(
                                    lineWidth: 1.5,
                                    dash: [4, 3],
                                    dashPhase: marchingAntsPhase
                                ))
                                .foregroundStyle(.black)
                                .frame(height: trackHeight)
                        }
                        .offset(x: startX)
                }

                // Editing range overlay (white marching ants, extends with playhead)
                if let editing = editingRange {
                    let rangeSpan = range.upperBound - range.lowerBound
                    let clampedLower = max(editing.lowerBound, range.lowerBound)
                    let clampedUpper = min(editing.upperBound, range.upperBound)
                    let startProgress = rangeSpan > 0 ? (clampedLower - range.lowerBound) / rangeSpan : 0
                    let endProgress = rangeSpan > 0 ? (clampedUpper - range.lowerBound) / rangeSpan : 0
                    let startX = CGFloat(max(0, min(1, startProgress))) * trackWidth
                    let segmentWidth = CGFloat(max(0, min(1, endProgress - startProgress))) * trackWidth

                    Capsule()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: max(segmentWidth, 3), height: trackHeight)
                        .overlay {
                            Capsule()
                                .strokeBorder(style: StrokeStyle(
                                    lineWidth: 1.5,
                                    dash: [4, 3],
                                    dashPhase: marchingAntsPhase
                                ))
                                .foregroundStyle(.white)
                                .frame(height: trackHeight)
                        }
                        .offset(x: startX)
                }

                // Capture markers (yellow diamonds on the track)
                ForEach(Array(captureMarkerPositions.enumerated()), id: \.offset) { _, time in
                    let rangeSpan = range.upperBound - range.lowerBound
                    let progress = rangeSpan > 0 ? (time - range.lowerBound) / rangeSpan : 0
                    let xPos = CGFloat(max(0, min(1, progress))) * trackWidth

                    Diamond()
                        .fill(Color.yellow)
                        .frame(width: 6, height: 6)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                        .position(x: xPos, y: geometry.size.height / 2)
                }

                // Thumb (downward-pointing triangle with tip touching the track)
                Triangle()
                    .fill(thumbColor)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .scaleEffect(isDragging ? 1.3 : 1.0)
                    .animation(.easeOut(duration: 0.15), value: isDragging)
                    .animation(.easeInOut(duration: 0.3), value: thumbColor)
                    // Position so the tip (bottom of triangle) touches the top of the track
                    .position(x: fillWidth, y: geometry.size.height / 2 - trackHeight / 2 - thumbSize / 2)
            }
            .contentShape(Rectangle()) // Ensure the whole area is draggable
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { gestureValue in
                            if !isDragging {
                                isDragging = true
                                dragStartY = gestureValue.location.y
                                onScrubStart()
                            }

                            let deltaY = gestureValue.location.y - dragStartY

                            // Detect level transitions (ordered from deepest to shallowest)
                            updateScrubLevel(deltaY: deltaY, gestureX: gestureValue.location.x, trackWidth: trackWidth)

                            // Compute value based on current level
                            switch scrubLevel {
                            case .normal:
                                let progress = max(0, min(1, gestureValue.location.x / trackWidth))
                                visualProgress = progress
                                let newValue = range.lowerBound + Double(progress) * (range.upperBound - range.lowerBound)
                                onScrubbing(newValue)

                            case .precision:
                                let deltaX = gestureValue.location.x - precisionAnchorX
                                let normalizedDelta = Double(deltaX / trackWidth)
                                let rangeSpan = range.upperBound - range.lowerBound
                                let precisionRange = rangeSpan / precisionFactor
                                let newValue = max(range.lowerBound, min(range.upperBound,
                                    precisionAnchorValue + normalizedDelta * precisionRange))
                                let progress = (newValue - range.lowerBound) / (range.upperBound - range.lowerBound)
                                visualProgress = CGFloat(progress)
                                onScrubbing(newValue)

                            case .frameByFrame:
                                let deltaX = gestureValue.location.x - precisionAnchorX
                                // 4 pixels = one frame
                                let newValue = max(range.lowerBound, min(range.upperBound,
                                    precisionAnchorValue + Double(deltaX) / framePixelRatio * frameDuration))
                                let rangeSpan = range.upperBound - range.lowerBound
                                let progress = rangeSpan > 0 ? (newValue - range.lowerBound) / rangeSpan : 0
                                visualProgress = CGFloat(progress)
                                onScrubbing(newValue)
                            }

                            // Always notify level changes when scrubbing in non-normal mode
                            onScrubLevelChanged?(scrubLevel, deltaY, precisionAnchorValue)
                        }
                        .onEnded { gestureValue in
                            let finalValue: Double
                            let finalScrubLevel = scrubLevel
                            switch scrubLevel {
                            case .normal:
                                let progress = max(0, min(1, gestureValue.location.x / trackWidth))
                                finalValue = range.lowerBound + Double(progress) * (range.upperBound - range.lowerBound)

                            case .precision:
                                let deltaX = gestureValue.location.x - precisionAnchorX
                                let normalizedDelta = Double(deltaX / trackWidth)
                                let rangeSpan = range.upperBound - range.lowerBound
                                let precisionRange = rangeSpan / precisionFactor
                                finalValue = max(range.lowerBound, min(range.upperBound,
                                    precisionAnchorValue + normalizedDelta * precisionRange))

                            case .frameByFrame:
                                let deltaX = gestureValue.location.x - precisionAnchorX
                                finalValue = max(range.lowerBound, min(range.upperBound,
                                    precisionAnchorValue + Double(deltaX) / framePixelRatio * frameDuration))
                            }

                            value = finalValue
                            visualProgress = nil
                            isDragging = false
                            scrubLevel = .normal
                            onScrubLevelChanged?(.normal, 0, 0)
                            onScrubEnd(finalValue, finalScrubLevel)
                        }
                )
        }
        .frame(height: hitAreaHeight)
        .onChange(of: shouldAnimate) { _, animate in
            if animate {
                marchingAntsPhase = 0
                withAnimation(.linear(duration: 0.6).repeatForever(autoreverses: false)) {
                    marchingAntsPhase = 7 // dash + gap = 4 + 3
                }
            } else {
                withAnimation(.default) {
                    marchingAntsPhase = 0
                }
            }
        }
        .onAppear {
            if shouldAnimate {
                withAnimation(.linear(duration: 0.6).repeatForever(autoreverses: false)) {
                    marchingAntsPhase = 7
                }
            }
        }
    }

    // MARK: - Level Detection

    private func updateScrubLevel(deltaY: CGFloat, gestureX: CGFloat, trackWidth: CGFloat) {
        let previousLevel = scrubLevel

        if deltaY < frameByFrameActivationThreshold && scrubLevel != .frameByFrame {
            // Enter frame-by-frame from any lower level
            scrubLevel = .frameByFrame
            setAnchor(gestureX: gestureX, trackWidth: trackWidth)
        } else if deltaY < precisionActivationThreshold && scrubLevel == .normal {
            // Enter precision from normal
            scrubLevel = .precision
            setAnchor(gestureX: gestureX, trackWidth: trackWidth)
        } else if deltaY > precisionDeactivationThreshold && scrubLevel != .normal {
            // Exit to normal from any elevated level
            scrubLevel = .normal
        } else if deltaY > frameByFrameDeactivationThreshold && scrubLevel == .frameByFrame {
            // Drop from frame-by-frame to precision
            scrubLevel = .precision
            // Re-anchor at current computed value
            let deltaX = gestureX - precisionAnchorX
            let currentValue = precisionAnchorValue + Double(deltaX) / framePixelRatio * frameDuration
            precisionAnchorValue = max(range.lowerBound, min(range.upperBound, currentValue))
            precisionAnchorX = gestureX
        }

        if previousLevel != scrubLevel {
            onScrubLevelChanged?(scrubLevel, deltaY, precisionAnchorValue)
        }
    }

    private func setAnchor(gestureX: CGFloat, trackWidth: CGFloat) {
        let currentProgress = max(0, min(1, gestureX / trackWidth))
        precisionAnchorValue = range.lowerBound + Double(currentProgress) * (range.upperBound - range.lowerBound)
        precisionAnchorX = gestureX
    }
}

// MARK: - Diamond Shape

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))   // top
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) // right
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)) // bottom
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY)) // left
            path.closeSubpath()
        }
    }
}

// MARK: - Triangle Shape

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))   // tip (bottom center)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY)) // top-left
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY)) // top-right
            path.closeSubpath()
        }
    }
}

// MARK: - Preview

#Preview("Custom Seek Slider") {
    struct PreviewWrapper: View {
        @State private var value: Double = 30
        @State private var isScrubbing = false

        var body: some View {
            VStack(spacing: 20) {
                Text("Value: \(Int(value))")
                    .foregroundStyle(.white)

                Text(isScrubbing ? "Scrubbing..." : "Idle")
                    .foregroundStyle(isScrubbing ? .yellow : .gray)

                CustomSeekSlider(
                    value: $value,
                    range: 0...100,
                    onScrubStart: {
                        isScrubbing = true
                    },
                    onScrubbing: { _ in },
                    onScrubEnd: { _, _ in
                        isScrubbing = false
                    }
                )
                .frame(width: 300)
            }
            .padding()
            .background(Color.black.opacity(0.8))
        }
    }

    return PreviewWrapper()
}

//
//  ScrubPreviewFloatingView.swift
//  gridstream-ipad
//

import SwiftUI

/// A floating scrub preview that positions itself absolutely in the coordinate space.
/// Designed to be rendered at the top level of a ZStack to avoid clipping.
struct ScrubPreviewFloatingView: View {

    // MARK: - Constants

    /// Preview thumbnail width in points
    static let previewWidth: CGFloat = 320

    /// Preview thumbnail height in points
    static let previewHeight: CGFloat = 180

    /// Vertical gap between preview bottom and thumb position
    private static let verticalGap: CGFloat = 60

    /// Corner radius for preview styling
    private static let cornerRadius: CGFloat = 8

    /// Shadow radius for depth effect
    private static let shadowRadius: CGFloat = 4

    /// Shadow opacity
    private static let shadowOpacity: Double = 0.3

    /// Border width
    private static let borderWidth: CGFloat = 0.5

    // MARK: - Properties

    /// The preview image to display, or nil for placeholder
    let previewImage: CGImage?

    /// Center X position of the slider thumb in the coordinate space
    let centerX: CGFloat

    /// Center Y position of the slider thumb in the coordinate space
    let centerY: CGFloat

    /// Current scrub level (normal, precision, or frameByFrame)
    var scrubLevel: ScrubLevel = .normal

    /// Current scrub time in seconds (for timecode display)
    var currentTime: Double = 0

    /// Video frame rate (for frame-accurate timecode)
    var frameRate: Double = 24.0

    // MARK: - Computed Style

    private var borderColor: Color {
        switch scrubLevel {
        case .normal: Color.secondary
        case .precision: Color.accentColor
        case .frameByFrame: Color.yellow
        }
    }

    private var badgeText: String? {
        switch scrubLevel {
        case .normal: nil
        case .precision: "1/10x"
        case .frameByFrame: "1f"
        }
    }

    private var badgeColor: Color {
        switch scrubLevel {
        case .normal: Color.clear
        case .precision: Color.accentColor
        case .frameByFrame: Color.yellow
        }
    }

    // MARK: - Body

    var body: some View {
        previewContent
            .frame(width: Self.previewWidth, height: Self.previewHeight)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .stroke(
                        borderColor,
                        lineWidth: scrubLevel != .normal ? 1.5 : Self.borderWidth
                    )
            )
            .overlay(alignment: .bottom) {
                if let badge = badgeText {
                    Text(badge)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(badgeColor.opacity(0.85))
                        .clipShape(Capsule())
                        .padding(.bottom, 6)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .overlay(alignment: .top) {
                Text(formatTimecode(currentTime))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.7))
                    .clipShape(Capsule())
                    .padding(.top, 6)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.2), value: scrubLevel)
            .shadow(
                color: Color.black.opacity(Self.shadowOpacity),
                radius: Self.shadowRadius
            )
            .position(
                x: centerX,
                y: centerY - Self.previewHeight / 2 - Self.verticalGap
            )
    }

    // MARK: - Timecode Formatting

    private func formatTimecode(_ time: Double) -> String {
        let clamped = max(0, time)
        let totalSeconds = Int(clamped)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let fractional = clamped - Double(totalSeconds)
        let frame = Int(fractional * frameRate)

        if hours > 0 {
            return String(format: "%d:%02d:%02d:%02d", hours, minutes, seconds, frame)
        }
        return String(format: "%d:%02d:%02d", minutes, seconds, frame)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var previewContent: some View {
        if let cgImage = previewImage {
            Image(decorative: cgImage, scale: 1.0, orientation: .up)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.5))
        }
    }
}

// MARK: - Previews

#Preview("Floating Preview") {
    ZStack {
        Color.black.opacity(0.3)

        // Simulated transport controls
        VStack {
            Spacer()
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .frame(height: 60)
                .padding()
        }

        // Floating preview
        ScrubPreviewFloatingView(
            previewImage: nil,
            centerX: 200,
            centerY: 350
        )
    }
    .frame(width: 400, height: 400)
}

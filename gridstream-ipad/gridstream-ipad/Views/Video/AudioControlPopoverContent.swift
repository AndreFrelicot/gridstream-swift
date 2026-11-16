//
//  AudioControlPopoverContent.swift
//  gridstream-ipad
//
//  Popover content for unified audio control with volume slider, mute, and solo buttons.
//

import SwiftUI

struct AudioControlPopoverContent: View {
    @Binding var volume: Float
    @Binding var isMuted: Bool
    @Binding var isSolo: Bool
    let onVolumeChanged: (Float) -> Void
    let onMuteToggle: () -> Void
    let onSoloToggle: () -> Void
    let onSoloLongPress: () -> Void
    var onDismiss: (() -> Void)? = nil

    private static let sliderHeight: CGFloat = 140
    private static let sliderWidth: CGFloat = 80
    private static let subButtonSize: CGFloat = 36
    private static let activeColor = Color.red
    private static let volumeColor = Color.orange
    private static let inactiveColor = Color.white.opacity(0.8)

    var body: some View {
        VStack(spacing: 12) {
            // Dismiss button at top
            if onDismiss != nil {
                HStack {
                    Spacer()
                    Button(action: { onDismiss?() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }

            volumeSlider
            Divider()
                .background(Color.white.opacity(0.3))
            controlButtons
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Volume Slider

    private var volumeSlider: some View {
        VStack(spacing: 6) {
            Text("\(Int(volume * 100))%")
                .font(.caption.monospacedDigit().bold())
                .foregroundColor(.white)

            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.3))

                    RoundedRectangle(cornerRadius: 6)
                        .fill(Self.volumeColor)
                        .frame(height: geometry.size.height * CGFloat(volume))
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let newVolume = Float(1 - (value.location.y / geometry.size.height))
                            let clampedVolume = max(0, min(1, newVolume))
                            volume = clampedVolume
                            onVolumeChanged(clampedVolume)
                        }
                )
            }
            .frame(width: 24, height: Self.sliderHeight - 30)

            Image(systemName: "speaker.slash.fill")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(width: Self.sliderWidth, height: Self.sliderHeight)
    }

    // MARK: - Control Buttons

    private var controlButtons: some View {
        HStack(spacing: 12) {
            muteButton
            soloButton
        }
    }

    private var muteButton: some View {
        Button(action: onMuteToggle) {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.slash")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isMuted ? .white : Self.inactiveColor)
                .frame(width: Self.subButtonSize, height: Self.subButtonSize)
                .background(isMuted ? Self.activeColor : Color.white.opacity(0.15))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMuted ? "Unmute" : "Mute")
    }

    private var soloButton: some View {
        Button(action: onSoloToggle) {
            Image(systemName: "headphones")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isSolo ? .white : Self.inactiveColor)
                .frame(width: Self.subButtonSize, height: Self.subButtonSize)
                .background(isSolo ? Self.activeColor : Color.white.opacity(0.15))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 1.5)
                .onEnded { _ in
                    onSoloLongPress()
                }
        )
        .accessibilityLabel(isSolo ? "Disable solo" : "Solo")
        .accessibilityHint("Long press for exclusive solo")
    }
}

#Preview("Default") {
    ZStack {
        Color.black
        AudioControlPopoverContent(
            volume: .constant(0.7),
            isMuted: .constant(false),
            isSolo: .constant(false),
            onVolumeChanged: { _ in },
            onMuteToggle: {},
            onSoloToggle: {},
            onSoloLongPress: {}
        )
    }
}

#Preview("Muted") {
    ZStack {
        Color.black
        AudioControlPopoverContent(
            volume: .constant(0.5),
            isMuted: .constant(true),
            isSolo: .constant(false),
            onVolumeChanged: { _ in },
            onMuteToggle: {},
            onSoloToggle: {},
            onSoloLongPress: {}
        )
    }
}

#Preview("Solo Active") {
    ZStack {
        Color.black
        AudioControlPopoverContent(
            volume: .constant(0.8),
            isMuted: .constant(false),
            isSolo: .constant(true),
            onVolumeChanged: { _ in },
            onMuteToggle: {},
            onSoloToggle: {},
            onSoloLongPress: {}
        )
    }
}

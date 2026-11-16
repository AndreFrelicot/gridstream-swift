//
//  AudioControlButton.swift
//  gridstream-ipad
//
//  Unified audio control button with popover containing volume slider, mute, and solo.
//  Replaces separate MuteButton and VolumeOverrideButton for cleaner UX.
//

import SwiftUI

struct AudioControlButton: View {
    @Binding var volume: Float
    @Binding var isMuted: Bool
    @Binding var isSolo: Bool
    let onVolumeChanged: (Float) -> Void
    let onMuteToggle: () -> Void
    let onSoloToggle: () -> Void
    let onSoloLongPress: () -> Void
    var onPopoverOpen: (() -> Void)? = nil
    var onPopoverClose: (() -> Void)? = nil
    var isCompact: Bool = false

    @State private var showPopover = false

    private var buttonSize: CGFloat { isCompact ? 32 : 44 }
    private var iconSize: CGFloat { isCompact ? 16 : 20 }
    private static let activeColor = Color.orange
    private static let mutedColor = Color.red
    private static let inactiveColor = Color.white.opacity(0.8)

    var body: some View {
        Button(action: {
            showPopover.toggle()
        }) {
            Image(systemName: iconName)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: buttonSize, height: buttonSize)
                .background(backgroundColor)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(showPopover ? Self.activeColor : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            AudioControlPopoverContent(
                volume: $volume,
                isMuted: $isMuted,
                isSolo: $isSolo,
                onVolumeChanged: onVolumeChanged,
                onMuteToggle: onMuteToggle,
                onSoloToggle: onSoloToggle,
                onSoloLongPress: onSoloLongPress,
                onDismiss: {
                    showPopover = false
                }
            )
            .presentationCompactAdaptation(.popover)
        }
        .onChange(of: showPopover) { _, isOpen in
            // Handle popover state changes (including dismiss by tapping outside)
            if isOpen {
                onPopoverOpen?()
            } else {
                onPopoverClose?()
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Tap to open audio controls")
    }

    private var iconName: String {
        if isMuted {
            return "speaker.slash.fill"
        }
        if volume == 0 {
            return "speaker.slash.fill"
        } else if volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }

    private var iconColor: Color {
        if isMuted {
            return .white
        }
        if isSolo {
            return Self.mutedColor
        }
        return Self.inactiveColor
    }

    private var backgroundColor: Color {
        if isMuted {
            return Self.mutedColor
        }
        if isSolo {
            return Self.mutedColor.opacity(0.3)
        }
        return Color.clear
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if isMuted {
            parts.append(String(localized: "Muted"))
        } else {
            parts.append(String(localized: "Volume \(Int(volume * 100))%"))
        }
        if isSolo {
            parts.append(String(localized: "Solo active"))
        }
        return parts.joined(separator: ", ")
    }
}

#Preview("Default") {
    ZStack {
        Color.gray
        AudioControlButton(
            volume: .constant(0.7),
            isMuted: .constant(false),
            isSolo: .constant(false),
            onVolumeChanged: { _ in },
            onMuteToggle: {},
            onSoloToggle: {},
            onSoloLongPress: {}
        )
    }
    .frame(width: 100, height: 100)
}

#Preview("Muted") {
    ZStack {
        Color.gray
        AudioControlButton(
            volume: .constant(0.5),
            isMuted: .constant(true),
            isSolo: .constant(false),
            onVolumeChanged: { _ in },
            onMuteToggle: {},
            onSoloToggle: {},
            onSoloLongPress: {}
        )
    }
    .frame(width: 100, height: 100)
}

#Preview("Solo Active") {
    ZStack {
        Color.gray
        AudioControlButton(
            volume: .constant(0.8),
            isMuted: .constant(false),
            isSolo: .constant(true),
            onVolumeChanged: { _ in },
            onMuteToggle: {},
            onSoloToggle: {},
            onSoloLongPress: {}
        )
    }
    .frame(width: 100, height: 100)
}

#Preview("All States") {
    ZStack {
        Color.black
        HStack(spacing: 20) {
            VStack(spacing: 8) {
                AudioControlButton(
                    volume: .constant(0.7),
                    isMuted: .constant(false),
                    isSolo: .constant(false),
                    onVolumeChanged: { _ in },
                    onMuteToggle: {},
                    onSoloToggle: {},
                    onSoloLongPress: {}
                )
                Text("Normal")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            VStack(spacing: 8) {
                AudioControlButton(
                    volume: .constant(0.5),
                    isMuted: .constant(true),
                    isSolo: .constant(false),
                    onVolumeChanged: { _ in },
                    onMuteToggle: {},
                    onSoloToggle: {},
                    onSoloLongPress: {}
                )
                Text("Muted")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            VStack(spacing: 8) {
                AudioControlButton(
                    volume: .constant(0.8),
                    isMuted: .constant(false),
                    isSolo: .constant(true),
                    onVolumeChanged: { _ in },
                    onMuteToggle: {},
                    onSoloToggle: {},
                    onSoloLongPress: {}
                )
                Text("Solo")
                    .font(.caption)
                    .foregroundColor(.white)
            }
        }
    }
    .frame(width: 300, height: 150)
}

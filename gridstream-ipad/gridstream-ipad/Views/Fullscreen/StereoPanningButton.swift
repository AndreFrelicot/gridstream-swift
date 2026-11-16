//
//  StereoPanningButton.swift
//  gridstream-ipad
//
//  A toggle button for Stereo Panning mode in fullscreen.
//  When enabled, PiP tiles' audio pans left/right based on their screen position.
//  The fullscreen video always remains centered (no panning).
//

import SwiftUI

struct StereoPanningButton: View {
    @Binding var isActive: Bool
    let onToggle: () -> Void

    private let buttonSize: CGFloat = 44
    private let iconSize: CGFloat = 18

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: isActive ? "speaker.wave.2.circle.fill" : "speaker.wave.2.circle")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(isActive ? .black : .white)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    Circle()
                        .fill(isActive ? Color.cyan : Color.black.opacity(0.5))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "Stereo panning active" : "Stereo panning")
        .accessibilityHint(isActive
            ? "Tap to disable stereo panning"
            : "Tap to enable stereo panning based on PiP tile positions")
    }
}

#Preview("Inactive") {
    ZStack {
        Color.black

        StereoPanningButton(isActive: .constant(false), onToggle: {})
    }
    .frame(width: 100, height: 100)
}

#Preview("Active") {
    ZStack {
        Color.black

        StereoPanningButton(isActive: .constant(true), onToggle: {})
    }
    .frame(width: 100, height: 100)
}

#Preview("In Context") {
    ZStack {
        Color.gray

        VStack {
            Text("Fullscreen Video Content")
                .foregroundStyle(.white)
        }

        VStack {
            HStack {
                VStack(spacing: 12) {
                    Spacer()
                    StereoPanningButton(isActive: .constant(false), onToggle: {})
                    StereoPanningButton(isActive: .constant(true), onToggle: {})
                    Spacer()
                }
                .padding(.leading, 20)
                Spacer()
            }
        }
    }
    .frame(width: 400, height: 300)
}

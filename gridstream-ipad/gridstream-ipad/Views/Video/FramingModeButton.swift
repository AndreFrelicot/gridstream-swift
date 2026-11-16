//
//  FramingModeButton.swift
//  gridstream-ipad
//

import SwiftUI

struct FramingModeButton: View {
    let currentMode: FramingMode
    let onModeChange: (FramingMode) -> Void
    var onLongPress: (() -> Void)?
    var isCompact: Bool = false

    private var buttonSize: CGFloat { isCompact ? 32 : 44 }
    private var iconSize: CGFloat { isCompact ? 14 : 18 }

    private var isFillMode: Bool {
        currentMode == .fill
    }

    private var nextMode: FramingMode {
        isFillMode ? .fit : .fill
    }

    var body: some View {
        Image(systemName: isFillMode ? "arrow.up.left.and.arrow.down.right" : "arrow.down.forward.and.arrow.up.backward")
            .font(.system(size: iconSize, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: buttonSize, height: buttonSize)
            .background(
                Circle()
                    .fill(Color.black.opacity(0.5))
            )
            .contentShape(Circle())
            .onTapGesture {
                onModeChange(nextMode)
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                onLongPress?()
            }
            .accessibilityLabel(isFillMode ? "Fill mode" : "Fit mode")
            .accessibilityHint(isFillMode ? "Tap to show full video with letterboxing. Long press to apply to all tiles." : "Tap to fill the tile. Long press to apply to all tiles.")
    }
}

#Preview {
    ZStack {
        Color.gray

        VStack {
            Text("Video Content")
                .foregroundStyle(.white)
        }

        VStack {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    FramingModeButton(currentMode: .fill, onModeChange: { _ in })
                    FramingModeButton(currentMode: .fit, onModeChange: { _ in })
                    FramingModeButton(currentMode: .custom, onModeChange: { _ in })
                }
                .padding()
            }
            Spacer()
        }
    }
    .frame(width: 400, height: 300)
}

#Preview("Dark Background") {
    ZStack {
        Color.black

        VStack(spacing: 16) {
            FramingModeButton(currentMode: .fill, onModeChange: { _ in })
            FramingModeButton(currentMode: .fit, onModeChange: { _ in })
            FramingModeButton(currentMode: .custom, onModeChange: { _ in })
        }
    }
    .frame(width: 200, height: 250)
}

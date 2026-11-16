//
//  FullscreenButton.swift
//  gridstream-ipad
//

import SwiftUI

struct FullscreenButton: View {
    let onFullscreen: () -> Void
    var isCompact: Bool = false

    private var buttonSize: CGFloat { isCompact ? 32 : 44 }
    private var iconSize: CGFloat { isCompact ? 14 : 18 }

    var body: some View {
        Button(action: onFullscreen) {
            Image(systemName: "square.arrowtriangle.4.outward")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.5))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Enter fullscreen")
        .accessibilityHint("Displays this video in fullscreen with other tiles as picture-in-picture")
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
                FullscreenButton(onFullscreen: {})
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

        FullscreenButton(onFullscreen: {})
    }
    .frame(width: 100, height: 100)
}

#Preview("Light Background") {
    ZStack {
        Color.white

        FullscreenButton(onFullscreen: {})
    }
    .frame(width: 100, height: 100)
}

//
//  ExitFullscreenButton.swift
//  gridstream-ipad
//

import SwiftUI

struct ExitFullscreenButton: View {
    let onExitFullscreen: () -> Void

    var body: some View {
        Button(action: onExitFullscreen) {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Exit fullscreen")
        .accessibilityHint("Returns to grid layout with all tiles visible")
    }
}

#Preview {
    ZStack {
        Color.gray

        VStack {
            Text("Fullscreen Video Content")
                .foregroundStyle(.white)
        }

        VStack {
            HStack {
                Spacer()
                ExitFullscreenButton(onExitFullscreen: {})
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

        ExitFullscreenButton(onExitFullscreen: {})
    }
    .frame(width: 100, height: 100)
}

#Preview("Light Background") {
    ZStack {
        Color.white

        ExitFullscreenButton(onExitFullscreen: {})
    }
    .frame(width: 100, height: 100)
}

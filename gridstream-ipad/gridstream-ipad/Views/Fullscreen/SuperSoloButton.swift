//
//  SuperSoloButton.swift
//  gridstream-ipad
//
//  A toggle button for SuperSolo mode in fullscreen.
//  SuperSolo temporarily solos the fullscreen video while preserving
//  the original mute/solo states, which are restored when deactivated.
//

import SwiftUI

struct SuperSoloButton: View {
    @Binding var isActive: Bool
    let onToggle: () -> Void

    private let buttonSize: CGFloat = 44
    private let iconSize: CGFloat = 18

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: isActive ? "headphones.circle.fill" : "headphones.circle")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(isActive ? .black : .white)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    Circle()
                        .fill(isActive ? Color.yellow : Color.black.opacity(0.5))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "SuperSolo active" : "SuperSolo")
        .accessibilityHint(isActive
            ? "Tap to deactivate SuperSolo and restore previous audio states"
            : "Tap to solo only this video while in fullscreen")
    }
}

#Preview("Inactive") {
    ZStack {
        Color.black

        SuperSoloButton(isActive: .constant(false), onToggle: {})
    }
    .frame(width: 100, height: 100)
}

#Preview("Active") {
    ZStack {
        Color.black

        SuperSoloButton(isActive: .constant(true), onToggle: {})
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
                    SuperSoloButton(isActive: .constant(false), onToggle: {})
                    SuperSoloButton(isActive: .constant(true), onToggle: {})
                    Spacer()
                }
                .padding(.leading, 20)
                Spacer()
            }
        }
    }
    .frame(width: 400, height: 300)
}

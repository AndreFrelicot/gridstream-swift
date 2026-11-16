//
//  RandomVideoButton.swift
//  gridstream-ipad
//

import SwiftUI

struct RandomVideoButton: View {
    let onRandomVideo: () -> Void
    var isCompact: Bool = false

    private var buttonSize: CGFloat { isCompact ? 32 : 44 }
    private var iconSize: CGFloat { isCompact ? 14 : 18 }

    var body: some View {
        Button(action: onRandomVideo) {
            Image(systemName: "shuffle")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.5))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Random video")
        .accessibilityHint("Loads a random video from the library")
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
                HStack(spacing: 8) {
                    RandomVideoButton(onRandomVideo: {})
                    ChangeVideoButton(onChangeVideo: {})
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

        RandomVideoButton(onRandomVideo: {})
    }
    .frame(width: 100, height: 100)
}

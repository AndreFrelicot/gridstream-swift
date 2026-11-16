//
//  ChangeVideoButton.swift
//  gridstream-ipad
//

import SwiftUI

struct ChangeVideoButton: View {
    let onChangeVideo: () -> Void
    var isCompact: Bool = false

    private var buttonSize: CGFloat { isCompact ? 32 : 44 }
    private var iconSize: CGFloat { isCompact ? 14 : 18 }

    var body: some View {
        Button(action: onChangeVideo) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.5))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change video")
        .accessibilityHint("Opens video picker to select a different video for this tile")
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
                ChangeVideoButton(onChangeVideo: {})
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

        ChangeVideoButton(onChangeVideo: {})
    }
    .frame(width: 100, height: 100)
}

#Preview("Light Background") {
    ZStack {
        Color.white

        ChangeVideoButton(onChangeVideo: {})
    }
    .frame(width: 100, height: 100)
}

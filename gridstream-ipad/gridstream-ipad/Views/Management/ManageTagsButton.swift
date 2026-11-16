//
//  ManageTagsButton.swift
//  gridstream-ipad
//

import SwiftUI

/// Button that opens the Tag/Smart List management sheet.
/// Styled consistently with other tile control buttons.
struct ManageTagsButton: View {
    let onManageTags: () -> Void
    var isCompact: Bool = false

    private var buttonSize: CGFloat { isCompact ? 32 : 44 }
    private var iconSize: CGFloat { isCompact ? 14 : 18 }

    var body: some View {
        Button(action: onManageTags) {
            Image(systemName: "tag")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.5))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Manage tags")
        .accessibilityHint("Opens tag and smart list management")
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
                ManageTagsButton(onManageTags: {})
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

        ManageTagsButton(onManageTags: {})
    }
    .frame(width: 100, height: 100)
}

//
//  QuickAddToListButton.swift
//  gridstream-ipad
//

import SwiftUI

struct QuickAddToListButton: View {
    let onQuickAdd: () -> Void
    var isCompact: Bool = false

    private var buttonSize: CGFloat { isCompact ? 32 : 44 }
    private var iconSize: CGFloat { isCompact ? 14 : 18 }

    var body: some View {
        Button(action: onQuickAdd) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.5))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add to list")
        .accessibilityHint("Opens picker to add this video to a Simple List")
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
                QuickAddToListButton(onQuickAdd: {})
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

        QuickAddToListButton(onQuickAdd: {})
    }
    .frame(width: 100, height: 100)
}

#Preview("Light Background") {
    ZStack {
        Color.white

        QuickAddToListButton(onQuickAdd: {})
    }
    .frame(width: 100, height: 100)
}

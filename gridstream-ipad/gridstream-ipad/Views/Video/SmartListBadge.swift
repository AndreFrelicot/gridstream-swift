//
//  SmartListBadge.swift
//  gridstream-ipad
//

import SwiftUI

struct SmartListBadge: View {
    let name: String
    var videoCount: Int?
    var isSmartList: Bool = true

    private var displayText: Text {
        if let count = videoCount {
            return Text("\(name) (\(count))")
        }
        return Text(name)
    }

    private var iconName: String {
        isSmartList ? "list.bullet.rectangle" : "rectangle.stack"
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .medium))

            displayText
                .font(.caption2)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial.opacity(0.9))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
    }
}

#Preview {
    ZStack {
        Color.gray
        VStack(spacing: 20) {
            SmartListBadge(name: "Favorites", videoCount: 42, isSmartList: true)
            SmartListBadge(name: "Recently Added", videoCount: 128, isSmartList: true)
            SmartListBadge(name: "Watch Later", videoCount: 15, isSmartList: false)
            SmartListBadge(name: "My Playlist", isSmartList: false)
        }
    }
}

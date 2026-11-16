//
//  PlaceholderTileView.swift
//  gridstream-ipad
//

import SwiftUI

/// An empty tile: the app's mark, then buttons to fill it with a random
/// video, one from the library or a playlist. Its remove button sits in the
/// corner. Smaller tiles drop the title, then the mark, then the labels.
struct PlaceholderTileView: View {
    let tileNumber: Int
    var smartListName: String?
    var smartListVideoCount: Int?
    var simpleListName: String?
    var simpleListVideoCount: Int?
    var onSelectVideo: (() -> Void)?
    var onRandomVideo: (() -> Void)?
    var onRemove: (() -> Void)?
    var onAssignSmartList: (() -> Void)?

    var body: some View {
        ZStack {
            background

            ViewThatFits {
                content(iconSize: 72, showsTitle: true, labels: true)
                content(iconSize: 52, showsTitle: false, labels: true)
                content(iconSize: 40, showsTitle: false, labels: false)
                content(iconSize: nil, showsTitle: false, labels: false)
            }
            .padding(14)
        }
        .overlay(alignment: .topTrailing) {
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.12), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove Tile")
                .padding(4)
            }
        }
    }

    /// Near-black, warmed by a glow of the brand orange behind the mark.
    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.13), Color(white: 0.07)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Brand.orange.opacity(0.28), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 260
            )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func content(iconSize: CGFloat?, showsTitle: Bool, labels: Bool) -> some View {
        VStack(spacing: 14) {
            if let name = smartListName {
                SmartListBadge(name: name, videoCount: smartListVideoCount, isSmartList: true)
            } else if let name = simpleListName {
                SmartListBadge(name: name, videoCount: simpleListVideoCount, isSmartList: false)
            }

            if let iconSize {
                BrandIcon(size: iconSize)
                    .shadow(color: Brand.orange.opacity(0.45), radius: iconSize * 0.3)
            }

            if showsTitle {
                Text("Choose a video")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
            }

            HStack(spacing: 10) {
                if let onRandomVideo {
                    Button(action: onRandomVideo) {
                        tileLabel("Random", systemImage: "shuffle", labels: labels)
                    }
                    .buttonStyle(TileButtonStyle(prominent: true))
                }

                if let onSelectVideo {
                    Button(action: onSelectVideo) {
                        tileLabel("Library", systemImage: "rectangle.stack", labels: labels)
                    }
                    .buttonStyle(TileButtonStyle())
                }

                if let onAssignSmartList {
                    Button(action: onAssignSmartList) {
                        tileLabel("Playlist", systemImage: "list.bullet", labels: labels)
                    }
                    .buttonStyle(TileButtonStyle())
                }
            }
            .fixedSize()
        }
    }

    @ViewBuilder
    private func tileLabel(_ title: LocalizedStringKey, systemImage: String, labels: Bool) -> some View {
        if labels {
            Label(title, systemImage: systemImage)
        } else {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
    }
}

/// The empty tile's capsule buttons: the brand gradient for the main one,
/// translucent white for the others.
private struct TileButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minWidth: 44, minHeight: 40)
            .background {
                if prominent {
                    Capsule().fill(Brand.gradient)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                } else {
                    Capsule().fill(.white.opacity(0.14))
                }
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

#Preview {
    PlaceholderTileView(
        tileNumber: 0,
        onSelectVideo: {},
        onRandomVideo: {},
        onRemove: {},
        onAssignSmartList: {}
    )
    .frame(width: 400, height: 200)
    .padding()
}

#Preview("With Smart List") {
    PlaceholderTileView(
        tileNumber: 0,
        smartListName: "Favorites",
        onSelectVideo: {},
        onRandomVideo: {},
        onRemove: {},
        onAssignSmartList: {}
    )
    .frame(width: 400, height: 250)
    .padding()
}

#Preview("Multiple Tiles") {
    HStack(spacing: 8) {
        PlaceholderTileView(
            tileNumber: 0,
            smartListName: "Action",
            onSelectVideo: {},
            onRandomVideo: {},
            onRemove: {},
            onAssignSmartList: {}
        )
        PlaceholderTileView(
            tileNumber: 1,
            onSelectVideo: {},
            onRandomVideo: {},
            onRemove: {},
            onAssignSmartList: {}
        )
    }
    .frame(height: 200)
    .padding()
}

#Preview("Single Tile - No Remove") {
    PlaceholderTileView(
        tileNumber: 0,
        onSelectVideo: {},
        onRandomVideo: {},
        onAssignSmartList: {}
    )
    .frame(width: 400, height: 200)
    .padding()
}

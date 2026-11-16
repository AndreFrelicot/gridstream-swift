//
//  TileView.swift
//  gridstream-ipad
//

import SwiftUI

struct TileView: View {
    let tile: Tile
    let isSelected: Bool
    let onTap: () -> Void
    var onChangeVideo: (() -> Void)?
    var onSelectVideo: (() -> Void)?
    var onRemove: (() -> Void)?
    var onRandomVideo: (() -> Void)?
    var onNextVideo: (() -> Void)?
    var endAction: TileEndAction = .stop
    var onEndActionChange: ((TileEndAction) -> Void)?
    var onNavigateBack: (() -> Void)?
    var onNavigateForward: (() -> Void)?
    var onFullscreen: (() -> Void)?
    var onQuickAddToList: (() -> Void)?
    var onAssignSmartList: (() -> Void)?
    var smartListName: String?
    var smartListVideoCount: Int?
    var simpleListName: String?
    var simpleListVideoCount: Int?
    var framingState: TileFramingState?

    var body: some View {
        tileContent
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(selectionOverlay)
            .contentShape(Rectangle())
    }

    // MARK: - Selection Overlay

    @ViewBuilder
    private var selectionOverlay: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.accentColor, lineWidth: isSelected ? 3 : 0)
    }

    // MARK: - Tile Content

    @ViewBuilder
    private var tileContent: some View {
        if let videoURL = tile.videoURL {
            VideoTileView(
                videoURL: videoURL,
                tileIndex: tile.index,
                isSelected: isSelected,
                onTap: onTap,
                videoId: tile.videoId,
                initialPlayCount: tile.playCount,
                initialViewTime: tile.totalViewTime,
                onChangeVideo: onChangeVideo,
                onRandomVideo: onRandomVideo,
                onNavigateBack: onNavigateBack,
                onNavigateForward: onNavigateForward,
                onFullscreen: onFullscreen,
                onQuickAddToList: onQuickAddToList,
                attachedSmartListName: smartListName,
                attachedSimpleListName: simpleListName,
                attachedSimpleListVideoCount: simpleListVideoCount,
                framingState: framingState,
                onNextVideo: onNextVideo,
                endAction: endAction,
                onEndActionChange: onEndActionChange
            )
        } else {
            PlaceholderTileView(
                tileNumber: tile.index,
                smartListName: smartListName,
                smartListVideoCount: smartListVideoCount,
                simpleListName: simpleListName,
                simpleListVideoCount: simpleListVideoCount,
                onSelectVideo: onSelectVideo,
                onRandomVideo: onRandomVideo,
                onRemove: onRemove,
                onAssignSmartList: onAssignSmartList
            )
            .onTapGesture {
                onTap()
            }
        }
    }
}

// MARK: - Previews

#Preview("Unselected - No Video") {
    TileView(
        tile: Tile(index: 0),
        isSelected: false,
        onTap: {},
        onSelectVideo: {},
        onRemove: {},
        onRandomVideo: {}
    )
    .environment(GlobalPlaybackManager.shared)
    .environment(VideoHistoryManager())
    .frame(width: 300, height: 200)
    .padding()
}

#Preview("Selected - No Video") {
    TileView(
        tile: Tile(index: 1),
        isSelected: true,
        onTap: {},
        onSelectVideo: {},
        onRemove: {},
        onRandomVideo: {}
    )
    .environment(GlobalPlaybackManager.shared)
    .environment(VideoHistoryManager())
    .frame(width: 300, height: 200)
    .padding()
}

#Preview("With Video URL") {
    TileView(
        tile: Tile(
            index: 0,
            videoURL: URL(string: "http://localhost:8080/api/v1/videos/test/stream")
        ),
        isSelected: false,
        onTap: {},
        onChangeVideo: {},
        onRandomVideo: {},
        onFullscreen: {}
    )
    .environment(GlobalPlaybackManager.shared)
    .environment(VideoHistoryManager())
    .frame(width: 400, height: 300)
    .padding()
}

#Preview("Selected - With Video URL") {
    TileView(
        tile: Tile(
            index: 1,
            videoURL: URL(string: "http://localhost:8080/api/v1/videos/test/stream")
        ),
        isSelected: true,
        onTap: {},
        onChangeVideo: {},
        onRandomVideo: {},
        onFullscreen: {}
    )
    .environment(GlobalPlaybackManager.shared)
    .environment(VideoHistoryManager())
    .frame(width: 400, height: 300)
    .padding()
}

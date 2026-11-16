//
//  OverlayContainerView.swift
//  gridstream-ipad
//

import GridStreamAPI
import SwiftUI

struct OverlayContainerView: View {
    let gridState: GridState
    let overlayState: OverlayState
    let connectionStatus: ConnectionStatus
    let showsForgetDeviceButton: Bool
    let onAddTile: () -> Void
    let onRemoveTile: () -> Void
    let onSelectVideo: () -> Void
    let onRandomAll: () -> Void
    let onForgetDevice: () -> Void
    var smartLists: [SmartListInfo] = []
    var simpleLists: [SimpleListDTO] = []
    /// Height of the status bar area. The grid ignores the safe area, so the
    /// overlay reads zero insets itself.
    var topSafeAreaInset: CGFloat = 0

    @Environment(GlobalPlaybackManager.self) private var playbackManager

    var body: some View {
        GeometryReader { proxy in
            // Only the part of the status bar over the grid: letterboxed, the
            // grid can start below it.
            let topInset = max(0, topSafeAreaInset - proxy.frame(in: .global).minY)
            ZStack(alignment: .top) {
                revealHandle
                    .padding(.top, topInset)

                topBar
                    .padding(.horizontal, 12)
                    .padding(.top, topInset + 6)
                    .offset(y: overlayState.isVisible ? 0 : -(topInset + 90))
                    .opacity(overlayState.isVisible ? 1 : 0)
                    .allowsHitTesting(overlayState.isVisible)
                    .accessibilityHidden(!overlayState.isVisible)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.spring(duration: 0.4, bounce: 0.2), value: overlayState.isVisible)
        }
    }

    /// A small orange grip left at the top while the bar is hidden: tap it
    /// or pull it down to bring the bar back.
    private var revealHandle: some View {
        Button {
            overlayState.show()
        } label: {
            Capsule()
                .fill(Brand.gradient)
                .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                .frame(width: 56, height: 7)
                .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                .frame(width: 160, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 8).onEnded { value in
                if value.translation.height > 8 { overlayState.show() }
            }
        )
        .accessibilityLabel("Show Controls")
        .opacity(overlayState.isVisible ? 0 : 1)
        .allowsHitTesting(!overlayState.isVisible)
        .accessibilityHidden(overlayState.isVisible)
    }

    /// The widest layout that fits: labelled buttons, then icons with the
    /// server name, then icons only.
    private var topBar: some View {
        ViewThatFits(in: .horizontal) {
            barContent(labels: true, serverDetail: true)
            barContent(labels: false, serverDetail: true)
            barContent(labels: false, serverDetail: false)
        }
        .padding(8)
        .background(TopBarBackground())
        // Any touch on the bar keeps it up; a swipe up puts it away.
        .simultaneousGesture(TapGesture().onEnded { overlayState.resetTimer() })
        .gesture(
            DragGesture(minimumDistance: 12).onEnded { value in
                if value.translation.height < -12 { overlayState.hide() }
            }
        )
    }

    private func barContent(labels: Bool, serverDetail: Bool) -> some View {
        HStack(spacing: 10) {
            ServerMenu(
                status: connectionStatus,
                compact: !serverDetail,
                onForgetDevice: showsForgetDeviceButton ? onForgetDevice : nil,
                onMenuOpen: {
                    overlayState.show()
                    overlayState.suspendAutoHide()
                },
                onMenuClose: { overlayState.resumeAutoHide() }
            )

            Spacer(minLength: 6)

            tileControls(labels: labels)

            Spacer(minLength: 6)

            if playbackManager.hasActivePlayers {
                GlobalPlaybackControls(
                    onPauseAll: { playbackManager.pauseAll() },
                    onPlayAll: { playbackManager.playAll() }
                )
            }

            OrientationToggle(gridState: gridState)

            GridIconMenu(
                gridState: gridState,
                onMenuOpen: { overlayState.suspendAutoHide() },
                onMenuClose: { overlayState.resumeAutoHide() }
            )
            .buttonStyle(TopBarButtonStyle())
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func tileControls(labels: Bool) -> some View {
        HStack(spacing: 10) {
            AddRemoveControlsView(
                tileCount: gridState.tileCount,
                canAdd: gridState.canAddTile,
                canRemove: gridState.canRemoveTile,
                onAdd: onAddTile,
                onRemove: onRemoveTile
            )

            Button(action: onSelectVideo) {
                Label("Library", systemImage: "rectangle.stack")
            }
            .buttonStyle(TopBarButtonStyle(prominent: true))
            .labelStyle(BarLabelStyle(showsTitle: labels))
            .accessibilityLabel("Open Content Library")

            Button(action: onRandomAll) {
                Label("Shuffle All", systemImage: "shuffle")
            }
            .buttonStyle(TopBarButtonStyle())
            .labelStyle(BarLabelStyle(showsTitle: labels))
            .accessibilityLabel("Load random videos on all tiles")

            PresetRecallMenu(
                gridState: gridState,
                smartLists: smartLists,
                simpleLists: simpleLists,
                onApplied: {
                    overlayState.resetTimer()
                },
                onMenuOpen: { overlayState.suspendAutoHide() },
                onMenuClose: { overlayState.resumeAutoHide() }
            )
            .buttonStyle(TopBarButtonStyle())
        }
    }
}

/// Title and icon, or the icon alone when the bar is narrow.
private struct BarLabelStyle: LabelStyle {
    let showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            if showsTitle {
                configuration.title
            }
        }
    }
}

#Preview {
    @Previewable @State var gridState = GridState()
    @Previewable @State var overlayState = OverlayState()

    OverlayContainerView(
        gridState: gridState,
        overlayState: overlayState,
        connectionStatus: .searching,
        showsForgetDeviceButton: false,
        onAddTile: {},
        onRemoveTile: {},
        onSelectVideo: {},
        onRandomAll: {},
        onForgetDevice: {}
    )
    .environment(GlobalPlaybackManager.shared)
    .environment(gridState)
    .environment(ServerDiscoveryService())
    .environment(DemoController())
    .onAppear { overlayState.show() }
}

#Preview("With Multiple Tiles") {
    @Previewable @State var gridState = GridState()
    @Previewable @State var overlayState = OverlayState()

    OverlayContainerView(
        gridState: gridState,
        overlayState: overlayState,
        connectionStatus: .found(serverName: "GridStream"),
        showsForgetDeviceButton: true,
        onAddTile: {},
        onRemoveTile: {},
        onSelectVideo: {},
        onRandomAll: {},
        onForgetDevice: {}
    )
    .environment(GlobalPlaybackManager.shared)
    .environment(gridState)
    .environment(ServerDiscoveryService())
    .environment(DemoController())
    .onAppear {
        gridState.setTileCount(4)
        gridState.selectTile(at: 1)
        overlayState.show()
    }
}

#Preview("With Active Players") {
    @Previewable @State var gridState = GridState()
    @Previewable @State var overlayState = OverlayState()

    OverlayContainerView(
        gridState: gridState,
        overlayState: overlayState,
        connectionStatus: .found(serverName: "GridStream"),
        showsForgetDeviceButton: true,
        onAddTile: {},
        onRemoveTile: {},
        onSelectVideo: {},
        onRandomAll: {},
        onForgetDevice: {}
    )
    .environment(GlobalPlaybackManager.shared)
    .environment(gridState)
    .environment(ServerDiscoveryService())
    .environment(DemoController())
    .onAppear {
        gridState.setTileCount(4)
        let playerState = VideoPlayerState()
        GlobalPlaybackManager.shared.register(playerState)
        overlayState.show()
    }
}

#Preview("With Vertical Orientation") {
    @Previewable @State var gridState = GridState()
    @Previewable @State var overlayState = OverlayState()

    OverlayContainerView(
        gridState: gridState,
        overlayState: overlayState,
        connectionStatus: .found(serverName: "GridStream"),
        showsForgetDeviceButton: true,
        onAddTile: {},
        onRemoveTile: {},
        onSelectVideo: {},
        onRandomAll: {},
        onForgetDevice: {}
    )
    .environment(GlobalPlaybackManager.shared)
    .environment(gridState)
    .environment(ServerDiscoveryService())
    .environment(DemoController())
    .onAppear {
        gridState.setTileCount(4)
        gridState.setOrientation(.vertical)
        overlayState.show()
    }
}

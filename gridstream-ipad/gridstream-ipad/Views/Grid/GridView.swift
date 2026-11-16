//
//  GridView.swift
//  gridstream-ipad
//

import GridStreamAPI
import SwiftUI
import os

struct SimpleListPickerItem: Identifiable {
    let id: String
    var videoId: String { id }
}

struct GridView: View {
    @Environment(GridState.self) private var gridState
    @Environment(ServerDiscoveryService.self) private var discoveryService
    @Environment(ServerSessionManager.self) private var sessionManager
    @Environment(VideoHistoryManager.self) private var historyManager
    @Environment(GlobalPlaybackManager.self) private var playbackManager
    @Environment(SharedPlayerPool.self) private var playerPool
    @Environment(DemoController.self) private var demoController
    @State private var overlayState = OverlayState()
    @State private var hasConfiguredFirstVideo = false
    /// Read outside `.ignoresSafeArea()`: views inside it see zero insets.
    @State private var topSafeAreaInset: CGFloat = 0
    @State private var showContentLibrary = false
    @State private var pickerTargetTileIndex: Int?
    @State private var cachedSmartLists: [SmartListInfo] = []
    @State private var cachedSimpleLists: [SimpleListDTO] = []
    @State private var cachedSmartListVideoCounts: [UUID: Int] = [:]
    @State private var contentLibraryInitialTab: UnifiedContentTab = .content
    @State private var videoIdForSimpleList: SimpleListPickerItem?
    private let tileSmartListService = TileSmartListService()
    private let smartListService = SmartListService()
    private let simpleListService = SimpleListService()
    private let contentLibraryService = ContentLibraryService()

    private var smartListIdForTargetTile: UUID? {
        guard let index = pickerTargetTileIndex,
              index < gridState.tiles.count else { return nil }
        return gridState.tiles[index].smartListId
    }

    var body: some View {
        ZStack {
            if gridState.isFullscreenMode {
                // Fullscreen mode view
                FullscreenModeView(
                    tiles: gridState.tiles,
                    fullscreenTileIndex: gridState.fullscreenTileIndex ?? 0,
                    tileLayouts: gridState.tileRatios,
                    pipLayouts: gridState.layoutState.pipLayouts,
                    onExitFullscreen: {
                        handleExitFullscreen()
                    },
                    onSwapFullscreen: { pipIndex, transform in
                        handleSwapFullscreen(toPipIndex: pipIndex, pipTransform: transform)
                    },
                    onPiPPositionChanged: { tileIndex, position in
                        handlePiPPositionChanged(tileIndex: tileIndex, position: position)
                    },
                    onPiPScaleChanged: { tileIndex, scale in
                        handlePiPScaleChanged(tileIndex: tileIndex, scale: scale)
                    },
                    onPiPRotationChanged: { tileIndex, rotation in
                        handlePiPRotationChanged(tileIndex: tileIndex, rotation: rotation)
                    },
                    onQuickAddToList: { tileIndex in
                        handleQuickAddToList(at: tileIndex)
                    },
                    onRandomVideo: { tileIndex in
                        handleRandomVideo(at: tileIndex)
                    },
                    onNextVideo: { tileIndex in
                        handleNextVideo(at: tileIndex)
                    },
                    onVideoSelected: { tileIndex, video in
                        assignVideoToTile(video, at: tileIndex)
                    },
                    topSafeAreaInset: topSafeAreaInset
                )
            } else {
                // Grid mode view
                gridModeContent
            }
        }
        .ignoresSafeArea()
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topSafeAreaInset = $0 }
        .fullScreenCover(isPresented: $showContentLibrary) {
            UnifiedContentLibraryView(
                isPresented: $showContentLibrary,
                serverURL: discoveryService.activeServerURL,
                initialTab: contentLibraryInitialTab,
                targetTileIndex: pickerTargetTileIndex,
                onVideoSelected: { video in
                    assignVideoToTargetTile(video)
                },
                onApplySmartListToTileAt: { smartListId, tileIndex in
                    applySmartList(smartListId, toTileAt: tileIndex)
                },
                onApplySimpleListToTileAt: { simpleListId, tileIndex in
                    applySimpleList(simpleListId, toTileAt: tileIndex)
                },
                tiles: gridState.tiles,
                activePreset: gridState.activePreset,
                orientation: gridState.orientation,
                initialSmartListId: smartListIdForTargetTile
            )
        }
        .sheet(item: $videoIdForSimpleList) { item in
            SimpleListPickerSheet(
                videoIds: [item.videoId],
                serverURL: discoveryService.activeServerURL,
                onDismiss: {
                    videoIdForSimpleList = nil
                },
                onSuccess: { _ in
                    videoIdForSimpleList = nil
                }
            )
        }
        .onChange(of: discoveryService.activeServer) { _, server in
            configureFirstVideoIfNeeded(server: server)
        }
        // A re-login issues a new token; the old one in the tiles' stream
        // URLs may be revoked, so rebuild them.
        .onChange(of: sessionManager.tokenRevision) { _, _ in
            if let serverURL = discoveryService.activeServerURL {
                gridState.refreshStreamURLs(serverURL: serverURL)
            }
        }
        .onChange(of: showContentLibrary) { _, isShowing in
            if !isShowing, sessionManager.isAuthorized,
               let serverURL = discoveryService.activeServerURL {
                refreshLists(serverURL: serverURL)
            }
        }
        .onAppear {
            configureFirstVideoIfNeeded(server: discoveryService.activeServer)
            playerPool.onTilePlaybackEnded = { index in
                handlePlaybackEnded(at: index)
            }
        }
        // (Re)load lists for the active server once a session exists — and
        // again after a re-login — instead of firing unauthenticated requests.
        .task(id: listsReloadKey) {
            guard sessionManager.isAuthorized,
                  let serverURL = discoveryService.activeServerURL else { return }
            refreshLists(serverURL: serverURL)
        }
        // A demo just opened: start with clips on every tile.
        .task(id: demoFillKey) {
            guard demoController.pendingDemoFill,
                  discoveryService.isDemoActive,
                  sessionManager.isAuthorized,
                  let serverURL = discoveryService.activeServerURL else { return }
            await fillTilesForDemo(serverURL: serverURL)
        }
    }

    private var demoFillKey: String {
        "\(demoController.pendingDemoFill)|\(discoveryService.isDemoActive)|\(sessionManager.isAuthorized)"
    }

    /// Loads a different demo clip on each tile.
    private func fillTilesForDemo(serverURL: URL) async {
        do {
            let videos = try await VideoAPIService().fetchVideos(from: serverURL).shuffled()
            // Cleared only now: it is part of this task's id, so clearing it
            // earlier would cancel the fetch.
            demoController.pendingDemoFill = false
            guard !videos.isEmpty else { return }
            for index in gridState.tiles.indices {
                applyVideo(videos[index % videos.count], at: index, serverURL: serverURL, source: "demo start")
            }
        } catch {
            AppLogger.video.error("Failed to fill the grid for the demo: \(error.localizedDescription)")
        }
    }

    // MARK: - Lists Loading

    private var listsReloadKey: String {
        "\(discoveryService.activeServerURL?.absoluteString ?? "")|\(sessionManager.isAuthorized)"
    }

    private func refreshLists(serverURL: URL) {
        Task { @MainActor in
            do {
                cachedSmartLists = try await smartListService.fetchSmartLists(from: serverURL)
                AppLogger.video.info("Loaded \(cachedSmartLists.count) Smart Lists for random video filtering")
            } catch {
                AppLogger.video.error("Failed to load Smart Lists: \(error.localizedDescription)")
            }

            do {
                cachedSimpleLists = try await simpleListService.fetchSimpleLists(from: serverURL)
                AppLogger.video.info("Loaded \(cachedSimpleLists.count) Simple Lists for tile badges")
            } catch {
                AppLogger.video.debug("Simple Lists not available: \(error.localizedDescription)")
            }

            // Load video counts for any smart lists already applied to tiles
            await loadSmartListVideoCountsForTiles()
        }
    }

    private func loadSmartListVideoCountsForTiles() async {
        guard let serverURL = discoveryService.activeServerURL else { return }

        for tile in gridState.tiles {
            if let smartListId = tile.smartListId {
                await fetchSmartListVideoCount(smartListId: smartListId, serverURL: serverURL)
            }
        }
    }

    private func fetchSmartListVideoCount(smartListId: UUID) async {
        guard let serverURL = discoveryService.activeServerURL else { return }
        await fetchSmartListVideoCount(smartListId: smartListId, serverURL: serverURL)
    }

    private func fetchSmartListVideoCount(smartListId: UUID, serverURL: URL) async {
        do {
            let result = try await tileSmartListService.fetchVideosForTile(
                tileIndex: 0, // Index doesn't matter for count
                smartListId: smartListId,
                smartLists: cachedSmartLists,
                serverURL: serverURL
            )
            await MainActor.run {
                cachedSmartListVideoCounts[smartListId] = result.total
            }
            AppLogger.video.debug("Cached smart list \(smartListId) video count: \(result.total)")
        } catch {
            AppLogger.video.error("Failed to fetch smart list video count: \(error.localizedDescription)")
        }
    }

    // MARK: - Grid Mode Content

    private var gridModeContent: some View {
        ZStack {
            GridContainerView(
                gridState: gridState,
                onTileTapped: { index in
                    handleTileTap(at: index)
                },
                onChangeVideo: { index in
                    handleChangeVideo(at: index)
                },
                onSelectVideo: { index in
                    handleSelectVideo(at: index)
                },
                onRemoveTile: gridState.tileCount > 1 ? { index in
                    handleRemoveTile(at: index)
                } : nil,
                onRandomVideo: { index in
                    handleRandomVideo(at: index)
                },
                onNextVideo: { index in
                    handleNextVideo(at: index)
                },
                onNavigateBack: { index in
                    handleNavigateBack(at: index)
                },
                onNavigateForward: { index in
                    handleNavigateForward(at: index)
                },
                onFullscreen: { index in
                    handleEnterFullscreen(at: index)
                },
                onQuickAddToList: { index in
                    handleQuickAddToList(at: index)
                },
                onAssignSmartList: { index in
                    handleAssignSmartList(at: index)
                },
                smartListNameForTile: { index in
                    smartListName(forTileAt: index)
                },
                smartListVideoCountForTile: { index in
                    smartListVideoCount(forTileAt: index)
                },
                simpleListNameForTile: { index in
                    simpleListName(forTileAt: index)
                },
                simpleListVideoCountForTile: { index in
                    simpleListVideoCount(forTileAt: index)
                }
            )

            // Kept alive while hidden, and hides itself: removing it would
            // also close a menu or dialog opened from it, dropping the
            // user's choice.
            OverlayContainerView(
                gridState: gridState,
                overlayState: overlayState,
                connectionStatus: discoveryService.connectionStatus,
                showsForgetDeviceButton: sessionManager.authEnabled && sessionManager.state == .authenticated,
                onAddTile: {
                    gridState.addTile()
                    overlayState.resetTimer()
                },
                onRemoveTile: {
                    removeSelectedTileAndSidecarState()
                    overlayState.resetTimer()
                },
                onSelectVideo: {
                    showContentLibraryForSelectedTile()
                },
                onRandomAll: {
                    handleRandomAllTiles()
                    overlayState.resetTimer()
                },
                onForgetDevice: {
                    Task {
                        await sessionManager.logout()
                    }
                },
                smartLists: cachedSmartLists,
                simpleLists: cachedSimpleLists,
                topSafeAreaInset: topSafeAreaInset
            )
        }
        // Shown on arrival so the controls and their grip are found.
        .onAppear { overlayState.show() }
    }

    // MARK: - Fullscreen Mode Handlers

    private func handleEnterFullscreen(at index: Int) {
        withAnimation(.easeInOut(duration: 0.3)) {
            gridState.enterFullscreen(tileIndex: index)
        }
    }

    private func handleExitFullscreen() {
        withAnimation(.easeInOut(duration: 0.3)) {
            gridState.exitFullscreen()
        }
        // Playback state is preserved via shared player pool - no need to restart
    }

    private func handleSwapFullscreen(toPipIndex: Int, pipTransform: PiPTransform) {
        // Reset pan for the tile becoming fullscreen so audio is centered
        StereoPanState.shared.clearPan(for: toPipIndex)
        gridState.swapFullscreen(toPipIndex: toPipIndex, tappedPiPTransform: pipTransform)
    }

    private func handlePiPPositionChanged(tileIndex: Int, position: CGPoint) {
        // Update the tile layout's PiP position and persist the change
        gridState.updatePiPPosition(at: tileIndex, position: position)
    }

    private func handlePiPScaleChanged(tileIndex: Int, scale: CGFloat) {
        // Update the tile layout's PiP scale and persist the change
        gridState.updatePiPScale(at: tileIndex, scale: scale)
    }

    private func handlePiPRotationChanged(tileIndex: Int, rotation: CGFloat) {
        // Update the tile layout's PiP rotation and persist the change
        gridState.updatePiPRotation(at: tileIndex, rotation: rotation)
    }

    // MARK: - Grid Mode Handlers

    private func handleTileTap(at index: Int) {
        gridState.selectTile(at: index)
        overlayState.show()
    }

    private func showContentLibraryForSelectedTile() {
        // Use selected tile, or default to first tile if none selected
        pickerTargetTileIndex = gridState.selectedTileIndex ?? 0
        contentLibraryInitialTab = .content
        showContentLibrary = true
    }

    private func handleChangeVideo(at index: Int) {
        // Change video triggers the Content Library for the specified tile
        gridState.selectTile(at: index)
        pickerTargetTileIndex = index
        contentLibraryInitialTab = .content
        showContentLibrary = true
    }

    private func handleSelectVideo(at index: Int) {
        gridState.selectTile(at: index)
        pickerTargetTileIndex = index
        contentLibraryInitialTab = .content
        showContentLibrary = true
    }

    private func handleRemoveTile(at index: Int) {
        gridState.selectTile(at: index)
        removeSelectedTileAndSidecarState()
    }

    private func removeSelectedTileAndSidecarState() {
        GridSidecarStateCoordinator.removeSelectedTile(
            gridState: gridState,
            playerPool: playerPool,
            historyManager: historyManager
        )
    }

    private func handleAssignSmartList(at index: Int) {
        gridState.selectTile(at: index)
        pickerTargetTileIndex = index
        contentLibraryInitialTab = .smartLists
        showContentLibrary = true
    }

    private func handleQuickAddToList(at index: Int) {
        guard index >= 0, index < gridState.tiles.count,
              let videoId = gridState.tiles[index].videoId else {
            AppLogger.video.warning("Cannot quick add to list: no video at tile \(index)")
            return
        }

        videoIdForSimpleList = SimpleListPickerItem(id: videoId)
    }

    private func smartListName(forTileAt index: Int) -> String? {
        guard index >= 0, index < gridState.tiles.count,
              let smartListId = gridState.tiles[index].smartListId else {
            return nil
        }
        return cachedSmartLists.first { $0.id == smartListId }?.name
    }

    private func simpleListName(forTileAt index: Int) -> String? {
        guard index >= 0, index < gridState.tiles.count,
              let simpleListId = gridState.tiles[index].simpleListId else {
            return nil
        }
        return cachedSimpleLists.first { $0.id == simpleListId }?.name
    }

    private func simpleListVideoCount(forTileAt index: Int) -> Int? {
        guard index >= 0, index < gridState.tiles.count,
              let simpleListId = gridState.tiles[index].simpleListId else {
            return nil
        }
        return cachedSimpleLists.first { $0.id == simpleListId }?.videoCount
    }

    private func smartListVideoCount(forTileAt index: Int) -> Int? {
        guard index >= 0, index < gridState.tiles.count,
              let smartListId = gridState.tiles[index].smartListId else {
            return nil
        }
        return cachedSmartListVideoCounts[smartListId]
    }

    private func assignVideoToTargetTile(_ video: VideoItem) {
        guard let targetIndex = pickerTargetTileIndex else {
            AppLogger.video.warning("Cannot assign video: missing target tile")
            return
        }
        assignVideoToTile(video, at: targetIndex)
    }

    private func assignVideoToTile(_ video: VideoItem, at targetIndex: Int) {
        guard let serverURL = discoveryService.activeServerURL else {
            AppLogger.video.warning("Cannot assign video: missing server URL")
            return
        }

        guard let streamURL = VideoURLBuilder.buildStreamURL(from: serverURL, videoId: video.fileId) else {
            AppLogger.video.error("Failed to build stream URL for video: \(video.fileId)")
            return
        }

        // Push to history before setting video
        AppLogger.video.info("Assigning video: \(video.filename), playCount: \(video.playCount), viewTime: \(video.totalViewTime)")
        historyManager.history(forTile: targetIndex).push(
            videoId: video.fileId,
            videoURL: streamURL,
            playCount: video.playCount,
            totalViewTime: video.totalViewTime
        )
        gridState.setVideoURL(streamURL, videoId: video.fileId, playCount: video.playCount, totalViewTime: video.totalViewTime, at: targetIndex)
        AppLogger.video.info("Assigned video '\(video.filename)' to tile \(targetIndex) via Content Library")
    }

    private func applySmartList(_ smartListId: UUID, toTileAt targetIndex: Int) {
        guard targetIndex >= 0, targetIndex < gridState.tiles.count else {
            AppLogger.video.warning("Cannot apply Smart List: tile \(targetIndex) does not exist")
            return
        }

        gridState.setSmartList(smartListId, at: targetIndex)
        AppLogger.video.info("Applied Smart List \(smartListId.uuidString) to tile \(targetIndex)")

        // Fetch video count for the smart list
        Task {
            await fetchSmartListVideoCount(smartListId: smartListId)
        }
    }

    private func applySimpleList(_ simpleListId: UUID, toTileAt targetIndex: Int) {
        guard targetIndex >= 0, targetIndex < gridState.tiles.count else {
            AppLogger.video.warning("Cannot apply Simple List: tile \(targetIndex) does not exist")
            return
        }

        gridState.setSimpleList(simpleListId, at: targetIndex)
        AppLogger.video.info("Applied Simple List \(simpleListId.uuidString) to tile \(targetIndex)")
    }

    private func configureFirstVideoIfNeeded(server: DiscoveredServer?) {
        guard !hasConfiguredFirstVideo,
              server?.url != nil,
              gridState.shouldBootstrapDefaultTileLayout else {
            return
        }

        hasConfiguredFirstVideo = true

        // Set up 4 empty placeholder tiles - user will select videos via Content Library
        GridSidecarStateCoordinator.setTileCount(
            4,
            gridState: gridState,
            playerPool: playerPool,
            historyManager: historyManager
        )
        AppLogger.video.info("Initialized 4 empty tiles - use Content Library to select videos")
    }

    // MARK: - Random Video Handling

    private func handleRandomVideo(at index: Int) {
        guard let serverURL = discoveryService.activeServerURL else {
            AppLogger.video.warning("Cannot load random video: no server URL")
            return
        }

        let currentVideoId = gridState.tiles[index].videoId
        let smartListId = gridState.tiles[index].smartListId
        let simpleListId = gridState.tiles[index].simpleListId

        if let smartListId = smartListId {
            Task { @MainActor in
                await handleRandomVideoFromSmartList(
                    at: index,
                    smartListId: smartListId,
                    currentVideoId: currentVideoId,
                    serverURL: serverURL
                )
            }
        } else if let simpleListId = simpleListId {
            Task { @MainActor in
                await handleRandomVideoFromSimpleList(
                    at: index,
                    simpleListId: simpleListId,
                    currentVideoId: currentVideoId,
                    serverURL: serverURL
                )
            }
        } else {
            handleRandomVideoFromFullCatalog(
                at: index,
                currentVideoId: currentVideoId,
                serverURL: serverURL
            )
        }
    }

    private func handleRandomVideoFromSmartList(
        at index: Int,
        smartListId: UUID,
        currentVideoId: String?,
        serverURL: URL
    ) async {
        do {
            guard let randomVideo = try await tileSmartListService.pickRandomVideoForSmartList(
                smartListId: smartListId,
                smartLists: cachedSmartLists,
                serverURL: serverURL
            ) else {
                AppLogger.video.warning("No videos in Smart List, falling back to full catalog")
                handleRandomVideoFromFullCatalog(at: index, currentVideoId: currentVideoId, serverURL: serverURL)
                return
            }

            if randomVideo.fileId == currentVideoId {
                AppLogger.video.debug("Smart List returned same video, attempting another pick")
                if let secondAttempt = try await tileSmartListService.pickRandomVideoForSmartList(
                    smartListId: smartListId,
                    smartLists: cachedSmartLists,
                    serverURL: serverURL
                ), secondAttempt.fileId != currentVideoId {
                    applyVideo(secondAttempt, at: index, serverURL: serverURL, source: "random from Smart List")
                    return
                }
            }

            applyVideo(randomVideo, at: index, serverURL: serverURL, source: "random from Smart List")
        } catch {
            AppLogger.video.error("Failed to fetch random video from Smart List: \(error.localizedDescription)")
            handleRandomVideoFromFullCatalog(at: index, currentVideoId: currentVideoId, serverURL: serverURL)
        }
    }

    private func handleRandomVideoFromSimpleList(
        at index: Int,
        simpleListId: UUID,
        currentVideoId: String?,
        serverURL: URL
    ) async {
        // Pick a random video ID from the simple list
        guard var randomVideoId = simpleListService.pickRandomVideoFromSimpleList(
            simpleListId: simpleListId,
            simpleLists: cachedSimpleLists
        ) else {
            AppLogger.video.warning("No videos in Simple List, falling back to full catalog")
            handleRandomVideoFromFullCatalog(at: index, currentVideoId: currentVideoId, serverURL: serverURL)
            return
        }

        // Try to avoid picking the same video
        if randomVideoId == currentVideoId {
            if let secondAttempt = simpleListService.pickRandomVideoFromSimpleList(
                simpleListId: simpleListId,
                simpleLists: cachedSimpleLists
            ), secondAttempt != currentVideoId {
                randomVideoId = secondAttempt
            }
        }

        if let video = try? await contentLibraryService.fetchVideoInfo(forFileId: randomVideoId, serverURL: serverURL) {
            applyVideo(video, at: index, serverURL: serverURL, source: "random from Simple List")
            return
        }

        guard let streamURL = VideoURLBuilder.buildStreamURL(from: serverURL, videoId: randomVideoId) else {
            AppLogger.video.error("Failed to build stream URL for random video from Simple List")
            return
        }

        historyManager.history(forTile: index).push(videoId: randomVideoId, videoURL: streamURL)
        gridState.setVideoURL(streamURL, videoId: randomVideoId, playCount: 0, totalViewTime: 0, at: index)
        AppLogger.video.info("Loaded random video from Simple List at tile \(index)")
    }

    private func handleRandomVideoFromFullCatalog(
        at index: Int,
        currentVideoId: String?,
        serverURL: URL
    ) {
        guard let randomVideo = historyManager.randomVideo(excluding: currentVideoId) else {
            AppLogger.video.warning("Cannot load random video: no videos available")
            return
        }

        applyVideo(randomVideo, at: index, serverURL: serverURL, source: "random from full catalog")
    }

    private func applyVideo(_ video: VideoItem, at index: Int, serverURL: URL, source: String) {
        guard let streamURL = VideoURLBuilder.buildStreamURL(from: serverURL, videoId: video.fileId) else {
            AppLogger.video.error("Failed to build stream URL for random video")
            return
        }

        historyManager.history(forTile: index).push(
            videoId: video.fileId,
            videoURL: streamURL,
            playCount: video.playCount,
            totalViewTime: video.totalViewTime
        )
        gridState.setVideoURL(streamURL, videoId: video.fileId, playCount: video.playCount, totalViewTime: video.totalViewTime, at: index)

        AppLogger.video.info("Loaded video '\(video.filename)' (\(source)) at tile \(index)")
    }

    private func handleRandomAllTiles() {
        for index in 0..<gridState.tiles.count {
            handleRandomVideo(at: index)
        }
        AppLogger.video.info("Loaded random videos on all \(gridState.tiles.count) tiles")
    }

    // MARK: - End of Video

    /// Applies the tile's end action once its video has played to the end.
    private func handlePlaybackEnded(at index: Int) {
        guard index < gridState.tiles.count else { return }
        switch gridState.endAction(at: index) {
        case .stop:
            break
        case .loop:
            playerPool.currentPlayer(forTile: index).play()
        case .next:
            handleNextVideo(at: index)
        case .shuffle:
            handleRandomVideo(at: index)
        }
    }

    /// Loads the video after the current one, in the order of the tile's
    /// Smart List, of its Simple List, or else of the library.
    private func handleNextVideo(at index: Int) {
        guard index < gridState.tiles.count,
              let serverURL = discoveryService.activeServerURL else {
            AppLogger.video.warning("Cannot load next video: no server URL")
            return
        }

        let tile = gridState.tiles[index]
        Task { @MainActor in
            if let smartListId = tile.smartListId,
               let smartList = cachedSmartLists.first(where: { $0.id == smartListId }) {
                do {
                    let result = try await contentLibraryService.fetchVideosWithSmartListCriteria(
                        from: serverURL,
                        criteria: smartList.criteria,
                        limit: 10_000
                    )
                    applyNextVideo(after: tile.videoId, in: result.videos, at: index, serverURL: serverURL, source: "next in Smart List")
                } catch {
                    AppLogger.video.error("Failed to fetch Smart List for next video: \(error.localizedDescription)")
                }
            } else if let simpleListId = tile.simpleListId,
                      let simpleList = cachedSimpleLists.first(where: { $0.id == simpleListId }) {
                guard let nextId = TileEndAction.nextVideoId(after: tile.videoId, in: simpleList.videoIds) else { return }
                if let video = try? await contentLibraryService.fetchVideoInfo(forFileId: nextId, serverURL: serverURL) {
                    applyVideo(video, at: index, serverURL: serverURL, source: "next in Simple List")
                }
            } else {
                applyNextVideo(after: tile.videoId, in: historyManager.availableVideos, at: index, serverURL: serverURL, source: "next in library")
            }
        }
    }

    private func applyNextVideo(after currentVideoId: String?, in videos: [VideoItem], at index: Int, serverURL: URL, source: String) {
        guard let nextId = TileEndAction.nextVideoId(after: currentVideoId, in: videos.map(\.fileId)),
              let video = videos.first(where: { $0.fileId == nextId }) else {
            AppLogger.video.info("No next video for tile \(index) (\(source))")
            return
        }
        applyVideo(video, at: index, serverURL: serverURL, source: source)
    }

    // MARK: - History Navigation

    private func handleNavigateBack(at index: Int) {
        let history = historyManager.history(forTile: index)

        guard let previousEntry = history.goBack() else {
            AppLogger.video.warning("Cannot navigate back: no previous video in history")
            return
        }

        gridState.setVideoURL(
            refreshedStreamURL(previousEntry.videoURL, videoId: previousEntry.videoId),
            videoId: previousEntry.videoId,
            playCount: previousEntry.playCount,
            totalViewTime: previousEntry.totalViewTime,
            at: index
        )
        AppLogger.video.info("Navigated back to video '\(previousEntry.videoId)' at tile \(index)")
    }

    private func handleNavigateForward(at index: Int) {
        let history = historyManager.history(forTile: index)

        guard let nextEntry = history.goForward() else {
            AppLogger.video.warning("Cannot navigate forward: no next video in history")
            return
        }

        gridState.setVideoURL(
            refreshedStreamURL(nextEntry.videoURL, videoId: nextEntry.videoId),
            videoId: nextEntry.videoId,
            playCount: nextEntry.playCount,
            totalViewTime: nextEntry.totalViewTime,
            at: index
        )
        AppLogger.video.info("Navigated forward to video '\(nextEntry.videoId)' at tile \(index)")
    }

    /// History entries keep the stream URL they were created with, including
    /// the session token of that time. Rebuild it so a re-login doesn't
    /// leave history pointing at a revoked token.
    private func refreshedStreamURL(_ url: URL, videoId: String) -> URL {
        guard let serverURL = VideoURLBuilder.serverBaseURL(of: url),
              let fresh = VideoURLBuilder.buildStreamURL(from: serverURL, videoId: videoId) else {
            return url
        }
        return fresh
    }
}

#Preview {
    let gridState = GridState()
    let discoveryService = ServerDiscoveryService()
    return GridView()
        .environment(gridState)
        .environment(discoveryService)
        .environment(ServerSessionManager.shared)
        .environment(GlobalPlaybackManager.shared)
        .environment(VideoHistoryManager())
        .environment(SharedPlayerPool())
        .environment(DemoController())
}

#Preview("With Multiple Tiles") {
    let gridState = GridState()
    gridState.setTileCount(4)
    let discoveryService = ServerDiscoveryService()
    return GridView()
        .environment(gridState)
        .environment(discoveryService)
        .environment(ServerSessionManager.shared)
        .environment(GlobalPlaybackManager.shared)
        .environment(VideoHistoryManager())
        .environment(SharedPlayerPool())
        .environment(DemoController())
}

#Preview("Fullscreen Mode") {
    let gridState = GridState()
    gridState.setTileCount(4)
    gridState.enterFullscreen(tileIndex: 0)
    let discoveryService = ServerDiscoveryService()
    return GridView()
        .environment(gridState)
        .environment(discoveryService)
        .environment(ServerSessionManager.shared)
        .environment(GlobalPlaybackManager.shared)
        .environment(VideoHistoryManager())
        .environment(SharedPlayerPool())
        .environment(DemoController())
}

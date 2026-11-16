//
//  VideoTileView.swift
//  gridstream-ipad
//

import AVFoundation
import GridStreamAPI
import OSLog
import SwiftUI

struct VideoTileView: View {
    let videoURL: URL
    let tileIndex: Int
    var isSelected: Bool = false
    let onTap: () -> Void
    var videoId: String?
    var initialPlayCount: Int = 0
    var initialViewTime: Int = 0
    var onChangeVideo: (() -> Void)?
    var onRandomVideo: (() -> Void)?
    var onNavigateBack: (() -> Void)?
    var onNavigateForward: (() -> Void)?
    var onFullscreen: (() -> Void)?
    var onQuickAddToList: (() -> Void)?
    var attachedSmartListName: String?
    var attachedSimpleListName: String?
    var attachedSimpleListVideoCount: Int?
    var framingState: TileFramingState?
    var onNextVideo: (() -> Void)?
    var endAction: TileEndAction = .stop
    var onEndActionChange: ((TileEndAction) -> Void)?

    // MARK: - Volume Constants
    private static let selectedVolume: Float = 1.0
    private static let unselectedVolume: Float = 0.3

    @Environment(GlobalPlaybackManager.self) private var playbackManager
    @Environment(VideoHistoryManager.self) private var historyManager
    @Environment(SharedPlayerPool.self) private var playerPool
    @Environment(GridState.self) private var gridState
    @Environment(ServerSessionManager.self) private var sessionManager
    @State private var playerManager = SwipeableVideoPlayerManager()

    /// This tile's current player, looked up with the view's own index. The
    /// view survives when an earlier tile is removed (ForEach is keyed by tile
    /// id) while the pool is reindexed, so a remembered index would point at
    /// another tile's player, or create an empty one.
    private var currentPlayer: VideoPlayerState { playerPool.currentPlayer(forTile: tileIndex) }
    private var playerTime: VideoPlayerState.Reading<Double> {
        VideoPlayerState.Reading(playerID: currentPlayer.id, value: currentPlayer.currentTime)
    }
    private var playerSeek: VideoPlayerState.Reading<VideoPlayerState.SeekMarker> {
        VideoPlayerState.Reading(playerID: currentPlayer.id, value: currentPlayer.lastSeek)
    }
    @State private var controlsState = VideoControlsState()
    @State private var scrubPreviewState: ScrubPreviewState?
    @State private var showScrubPreview = false

    /// Server metadata for the shown video (rating, tags, time ranges,
    /// annotations, list badges) and its stale-response guards.
    @State private var tile: TileController
    private var annotationManager: AnnotationManager { tile.annotationManager }

    // Shared audio state manager for persistence across tile/fullscreen modes
    private var audioStateManager: TileAudioStateManager { TileAudioStateManager.shared }

    // Volume override state (synced with shared manager)
    @State private var isVolumeOverrideActive = false
    @State private var overrideVolume: Float = 1.0

    // Mute and solo belong to the tile and live in the shared audio state
    // manager: reading them from there keeps this tile's buttons in step with
    // changes made elsewhere (another tile's exclusive solo, fullscreen, PiP).
    private var isMuted: Bool { audioStateManager.isMuted(for: tileIndex) }
    private var isSolo: Bool { audioStateManager.isSolo(for: tileIndex) }

    // Swipe navigation state
    @State private var swipeOffset: CGFloat = 0
    @State private var isSwipeActive = false
    @State private var swipeDirection: SwipeDirection?

    // Framing gesture state
    @State private var gestureScale: CGFloat = 1.0
    @State private var gestureOffset: CGPoint = .zero
    @State private var baseScale: CGFloat = 1.0
    @State private var baseOffset: CGPoint = .zero

    // Content library state
    @State private var showingContentLibrary = false

    // Time of Interest mode
    @State private var isToIMode: Bool = false

    /// Minimum swipe distance to trigger navigation
    private let swipeThreshold: CGFloat = 100

    /// Coordinate space name for positioning the scrub preview
    private let coordinateSpaceName = "videoTile"

    /// Reports playback stats for the tile's player
    private let contentLibraryService = ContentLibraryService()

    private var tileHistory: TileVideoHistory {
        historyManager.history(forTile: tileIndex)
    }

    // MARK: - Server URL

    private var serverURL: URL? {
        // Extract server URL from video URL
        guard let host = videoURL.host, let scheme = videoURL.scheme else { return nil }
        let port = videoURL.port.map { ":\($0)" } ?? ""
        return URL(string: "\(scheme)://\(host)\(port)")
    }

    private var metadataReloadKey: MetadataReloadKey {
        MetadataReloadKey(
            serverURL: serverURL,
            authorizedTokenRevision: sessionManager.isAuthorized ? sessionManager.tokenRevision : nil
        )
    }

    // MARK: - Time Range Computed Properties

    private var timeRangeColoredIntervals: [(range: ClosedRange<Double>, color: Color)] {
        tile.timeRanges.enumerated().map { index, info in
            (range: info.startTime...info.endTime,
             color: TimeRangeEditorView.rangeColors[index % TimeRangeEditorView.rangeColors.count])
        }
    }

    private var editingToIRange: ClosedRange<Double>? {
        guard let id = tile.editingToIRangeId,
              let range = tile.timeRanges.first(where: { $0.id == id }) else { return nil }
        return range.startTime...range.endTime
    }

    // MARK: - Attached List

    private var currentSmartListId: UUID? {
        guard tileIndex < gridState.tiles.count else { return nil }
        return gridState.tiles[tileIndex].smartListId
    }

    private var currentSimpleListId: UUID? {
        guard tileIndex < gridState.tiles.count else { return nil }
        return gridState.tiles[tileIndex].simpleListId
    }

    /// Computed smart list name from gridState and loaded smart lists
    private var computedSmartListName: String? {
        guard let smartListId = currentSmartListId else { return nil }
        return tile.smartLists.first { $0.id == smartListId }?.name
    }

    /// Computed simple list name from gridState and loaded simple lists
    private var computedSimpleListName: String? {
        guard let simpleListId = currentSimpleListId else { return nil }
        return tile.simpleLists.first { $0.id == simpleListId }?.name
    }

    /// Computed simple list video count from gridState and loaded simple lists
    private var computedSimpleListVideoCount: Int? {
        guard let simpleListId = currentSimpleListId else { return nil }
        return tile.simpleLists.first { $0.id == simpleListId }?.videoCount
    }

    // MARK: - List Membership (chips)

    private var membershipSmartLists: [SmartListInfo] { tile.memberSmartLists(of: videoId) }
    private var membershipSimpleLists: [SimpleListDTO] { tile.memberSimpleLists(of: videoId) }

    /// Current video filename from the history manager's available videos
    private var currentVideoFilename: String? {
        guard let id = videoId else { return nil }
        return historyManager.availableVideos.first { $0.fileId == id }?.filename
    }

    /// Current video source name from the history manager's available videos
    private var currentVideoSourceName: String? {
        guard let id = videoId else { return nil }
        return historyManager.availableVideos.first { $0.fileId == id }?.sourceDirectoryName
    }

    // MARK: - Computed Framing Properties

    private var currentFramingMode: FramingMode {
        framingState?.framingMode ?? .fill
    }

    private var currentZoomLevel: CGFloat {
        CGFloat(framingState?.customZoomLevel ?? 1.0)
    }

    private var currentPanOffset: CGPoint {
        framingState?.customPanOffset ?? .zero
    }

    private var annotationTextSheetBinding: Binding<Bool> {
        Binding(
            get: { annotationManager.isTextInputVisible },
            set: { annotationManager.setTextInputVisible($0) }
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main video content with swipe offset
                videoContentLayer
                    .offset(x: swipeOffset)

                // Adjacent video layer (for fluid swipe)
                if isSwipeActive, let direction = swipeDirection {
                    adjacentVideoLayer(direction: direction, geometry: geometry)
                }

                // Controls overlay (not affected by swipe)
                if controlsState.isVisible && currentPlayer.error == nil && !isSwipeActive {
                    controlsOverlayLayer(geometry: geometry)
                }

                // Floating scrub preview
                if showScrubPreview, let previewState = scrubPreviewState {
                    ScrubPreviewFloatingView(
                        previewImage: previewState.previewImage,
                        centerX: previewState.thumbCenterX,
                        centerY: previewState.thumbCenterY,
                        scrubLevel: previewState.scrubLevel,
                        currentTime: previewState.rulerCurrentTime,
                        frameRate: previewState.frameRate
                    )
                    .allowsHitTesting(false)
                    .transition(.opacity)

                    // Ruler overlay for precision/frame-by-frame modes
                    if previewState.scrubLevel != .normal {
                        ScrubRulerView(
                            centerX: previewState.thumbCenterX,
                            centerY: previewState.fingerY,
                            anchorTime: previewState.rulerAnchorTime,
                            currentTime: previewState.rulerCurrentTime,
                            visibleRange: previewState.rulerVisibleRange,
                            containerWidth: geometry.size.width,
                            scrubLevel: previewState.scrubLevel,
                            frameRate: previewState.frameRate
                        )
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    }
                }

                // Navigation indicators during swipe
                if isSwipeActive {
                    navigationIndicatorsView
                }
            }
            .gesture(swipeGesture)
        }
        .coordinateSpace(name: coordinateSpaceName)
        .onAppear {
            tile.show(videoId: videoId, serverURL: serverURL)
            setupPlayerManager()
            syncGestureStateFromFramingState()
            tile.loadRating()
            loadListsForBadge()
            tile.loadMemberships()
            tile.loadTimeRanges()
            loadAnnotations()
            applyMuteStateToCurrentPlayer()
        }
        .onDisappear {
            // Only clean up adjacent players - current player stays in pool for fullscreen
            playerManager.cleanupAdjacentPlayers()
            // Note: We don't unregister currentPlayer from playbackManager here
            // as fullscreen mode will use the same player from the pool

            // The tile lost its video (cleared source, preset that could not
            // be restored): stop, unregister and free its player, or it keeps
            // playing unseen and Play All restarts it.
            if !gridState.isFullscreenMode,
               tileIndex < gridState.tiles.count,
               gridState.tiles[tileIndex].videoURL == nil {
                playerPool.removePlayers(forTile: tileIndex)
            }
        }
        .onChange(of: videoURL) { oldURL, newURL in
            // Consume the cold-start restore flag before any early-return so a
            // tile that already happens to have the right URL loaded (rare) does
            // not leave the deferred-autoplay flag dangling for the next change.
            let isColdStartRestore = gridState.consumePendingRestoreFlag(at: tileIndex)

            // Check if current player already has the correct URL (swipe navigation already handled it)
            if currentPlayer.videoURL == newURL {
                // Player already set up correctly, just ensure it's registered and playing
                playbackManager.register(currentPlayer)
                updateVolume()
                if isColdStartRestore {
                    currentPlayer.pause()
                } else if !currentPlayer.isPlaying {
                    currentPlayer.play()
                }
                // Update adjacent videos based on new history position
                playerManager.preloadAdjacentVideos()
                return
            }

            // Different URL - need to set up new player
            playbackManager.unregister(currentPlayer)

            // Same stream with a new session token (re-login): reload it
            // where it was, in the same play/pause state
            let isTokenRefresh = VideoURLBuilder.removingToken(from: oldURL) == VideoURLBuilder.removingToken(from: newURL)

            // Check if we're navigating in history (URL matches previous or next)
            let seekTime: Double?
            if isTokenRefresh {
                seekTime = currentPlayer.currentTime
            } else if let entry = tileHistory.currentEntry, entry.videoURL == newURL {
                seekTime = entry.playbackTime
            } else {
                seekTime = nil
            }

            playerManager.setupCurrentPlayer(
                url: newURL,
                fileId: tileHistory.currentEntry?.videoId,
                seekTo: seekTime,
                autoplay: isTokenRefresh ? currentPlayer.wantsToPlay : !isColdStartRestore
            )
            playbackManager.register(currentPlayer)

            // Sync mute state for new video
            applyMuteStateToCurrentPlayer()
        }
        .onChange(of: videoId) { _, _ in
            // A new video also resets ToI editing and leaves annotation mode
            tile.show(videoId: videoId, serverURL: serverURL)
            tile.loadRating()
            tile.loadTimeRanges()
            loadAnnotations()
            // Sync mute state for new video
            applyMuteStateToCurrentPlayer()
        }
        // The tile loads its metadata on appear, before the session check:
        // with an expired token or a Mac not reachable yet that load fails.
        // Load again on another server and once requests are authorized
        // (and after a re-login).
        .onChange(of: metadataReloadKey) { _, key in
            tile.show(videoId: videoId, serverURL: serverURL)
            guard key.authorizedTokenRevision != nil else { return }
            tile.loadRating()
            tile.loadTimeRanges()
        }
        .onChange(of: tileIndex) { _, _ in
            // An earlier tile was removed: pool, history and audio state have
            // been reindexed, so retarget the swipe manager and re-apply this
            // tile's audio state to its player.
            configurePlayerManager()
            loadAudioStateFromManager()
            updateVolume()
        }
        .onChange(of: isSelected) { _, _ in
            updateVolume()
        }
        .onChange(of: isVolumeOverrideActive) { _, _ in
            updateVolume()
        }
        .onChange(of: currentSmartListId) { _, _ in
            loadListsForBadge()
        }
        .onChange(of: currentSimpleListId) { _, _ in
            loadListsForBadge()
        }
        .onChange(of: isToIMode) { _, newValue in
            if newValue {
                controlsState.suspendAutoHide()
            } else {
                controlsState.resumeAutoHide()
            }
        }
        .onChange(of: annotationManager.isAnnotationMode) { _, newValue in
            if newValue {
                controlsState.suspendAutoHide()
            } else {
                controlsState.resumeAutoHide()
            }
        }
        // Changes from switching to another player are ignored: the
        // annotations of its video load with the switch.
        .onChange(of: playerTime) { old, new in
            guard old.playerID == new.playerID else { return }
            annotationManager.syncFromTimelineIfNeeded(of: currentPlayer)
        }
        .onChange(of: playerSeek) { old, new in
            guard old.playerID == new.playerID, let marker = new.value else { return }
            annotationManager.syncFromSeek(marker, of: currentPlayer)
        }
        .onChange(of: currentPlayer.isPlaying) { _, isPlaying in
            guard isPlaying else { return }
            annotationManager.exitAnnotationModeForPlayback(of: currentPlayer)
        }
        .sheet(isPresented: $showingContentLibrary) {
            UnifiedContentLibraryView(
                isPresented: $showingContentLibrary,
                serverURL: serverURL,
                initialTab: .tags,
                currentVideoId: videoId,
                appliedTagIds: Set(tile.videoTags.map { $0.id }),
                onTagAppliedToVideo: tile.toggleTag,
                targetTileIndex: tileIndex,
                onApplySmartListToTileAt: { smartListId, targetIndex in
                    gridState.setSmartList(smartListId, at: targetIndex)
                },
                onApplySimpleListToTileAt: { simpleListId, targetIndex in
                    gridState.setSimpleList(simpleListId, at: targetIndex)
                },
                tiles: gridState.tiles,
                initialSmartListId: currentSmartListId,
                initialSimpleListId: currentSimpleListId
            )
        }
        .sheet(isPresented: annotationTextSheetBinding) {
            AnnotationTextView(
                text: Bindable(annotationManager).currentFrameText,
                onTextChanged: handleTextAnnotationChange,
                onDone: { annotationManager.setTextInputVisible(false) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Setup

    private func configurePlayerManager() {
        playerManager.configure(
            with: playerPool,
            tileIndex: tileIndex,
            history: tileHistory,
            playbackManager: playbackManager,
            playbackStatsReporter: makePlaybackStatsReporter()
        )
    }

    private func setupPlayerManager() {
        configurePlayerManager()

        // Check if we should restore a playback position
        let seekTime = tileHistory.currentEntry?.playbackTime

        // If this tile materialised because phase-2 restore just set its URL,
        // consume the deferred-autoplay flag here so the first onAppear stays
        // paused at the restored position rather than autoplaying.
        let isColdStartRestore = gridState.consumePendingRestoreFlag(at: tileIndex)

        playerManager.setupCurrentPlayer(
            url: videoURL,
            fileId: videoId,
            seekTo: seekTime,
            autoplay: !isColdStartRestore
        )
        currentPlayer.diagnosticDisplayContext = "tile"
        playbackManager.register(currentPlayer)

        // Load persisted audio state from shared manager
        loadAudioStateFromManager()

        // Set initial volume based on selection state
        updateVolume()
    }

    private func makePlaybackStatsReporter() -> VideoPlayerState.PlaybackStatsReporter? {
        guard let serverURL else { return nil }

        return { fileId, incrementPlayCount, addViewTime in
            _ = try await contentLibraryService.updatePlaybackStats(
                fileId: fileId,
                incrementPlayCount: incrementPlayCount,
                addViewTime: addViewTime,
                serverURL: serverURL
            )
        }
    }

    /// Loads audio state from the shared manager (for persistence across tile/fullscreen modes)
    private func loadAudioStateFromManager() {
        let state = audioStateManager.state(for: tileIndex)
        isVolumeOverrideActive = state.isVolumeOverrideActive
        overrideVolume = state.overrideVolume

        // Apply mute state to player. Solo needs nothing here: registering
        // the player hands it the tile's solo.
        currentPlayer.setMuted(state.isMuted)
    }

    /// Pushes the tile's mute onto the current player. Video changes and swipe
    /// navigation hand the tile a different player, which knows nothing of this
    /// tile's mute, so the tile re-asserts it rather than reading it back.
    private func applyMuteStateToCurrentPlayer() {
        currentPlayer.setMuted(isMuted)
    }

    /// Updates volume based on selection state and optional override
    /// Base volume is override if active, else 100%. Focus multiplier applied: focused=100%, blurred=30%
    /// Also applies volume to adjacent players to prevent sound spikes during swipe transitions
    private func updateVolume() {
        // Base volume: use override if set, otherwise full volume
        let baseVolume: Float = isVolumeOverrideActive ? overrideVolume : Self.selectedVolume
        // Apply focus multiplier: focused stays at base, blurred reduces to 30%
        let focusMultiplier: Float = isSelected ? 1.0 : (Self.unselectedVolume / Self.selectedVolume)
        let targetVolume = baseVolume * focusMultiplier

        // Apply to current player
        currentPlayer.setVolume(targetVolume)

        // Apply to adjacent players to prevent sound spikes during swipe
        // They stay paused but will have correct volume when they become current
        playerManager.previousPlayer?.setVolume(targetVolume)
        playerManager.nextPlayer?.setVolume(targetVolume)
    }

    /// Handles volume change from the audio control popover slider
    private func handleVolumeOverrideChange(_ newVolume: Float) {
        // Store the new override volume (this is the "focused" level)
        overrideVolume = newVolume
        isVolumeOverrideActive = true  // Mark override as active when user adjusts volume

        // Save to shared manager for persistence across tile/fullscreen modes
        audioStateManager.setVolumeOverride(active: true, level: newVolume, for: tileIndex)

        // Apply with focus multiplier
        let focusMultiplier: Float = isSelected ? 1.0 : (Self.unselectedVolume / Self.selectedVolume)
        let targetVolume = newVolume * focusMultiplier
        currentPlayer.setVolume(targetVolume)
        // Also update adjacent players for smooth transitions
        playerManager.previousPlayer?.setVolume(targetVolume)
        playerManager.nextPlayer?.setVolume(targetVolume)
    }

    /// Handles mute toggle
    private func handleMuteToggle() {
        let muted = !isMuted

        // Save to shared manager for persistence across tile/fullscreen modes
        audioStateManager.setMuted(muted, for: tileIndex)

        currentPlayer.setMuted(muted)
    }

    /// Handles solo toggle. The playback manager records the tile's solo
    /// (exclusive, persisted) and applies it to the current player.
    private func handleSoloToggle() {
        playbackManager.setSolo(!isSolo, for: currentPlayer)
    }

    /// Handles exclusive solo (long press)
    private func handleExclusiveSolo() {
        playbackManager.exclusiveSolo(for: currentPlayer)
    }

    private func syncGestureStateFromFramingState() {
        gestureScale = currentZoomLevel
        gestureOffset = currentPanOffset
        baseScale = currentZoomLevel
        baseOffset = currentPanOffset
    }

    // MARK: - Video Content Layer

    private var videoContentLayer: some View {
        ZStack {
            VideoPlayerView(
                playerState: currentPlayer,
                framingMode: currentFramingMode,
                customScale: gestureScale,
                customOffset: gestureOffset
            )
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                controlsState.forceHide()
            }
            .onTapGesture {
                controlsState.show()
                onTap()
            }

            // PencilKit canvas: drawings show in annotation mode only
            if annotationManager.isAnnotationMode {
                AnnotationCanvasView(
                    videoSize: videoSize(for: currentPlayer),
                    framingMode: currentFramingMode,
                    customScale: gestureScale,
                    customOffset: gestureOffset,
                    frameTime: annotationManager.displayedFrameTime ?? currentPlayer.currentTime,
                    existingStrokes: annotationManager.currentFrameStrokes,
                    target: annotationManager.target(frameRate: Double(currentPlayer.videoFrameRate)),
                    onStrokesChanged: { strokes, frameTime, target in
                        guard let target else { return }
                        Task {
                            await annotationManager.saveAnnotation(
                                frameTime: frameTime,
                                strokes: strokes,
                                target: target
                            )
                        }
                    },
                    onFingerTap: {
                        controlsState.show()
                        onTap()
                    },
                    onFingerDoubleTap: {
                        controlsState.forceHide()
                    }
                )
            }

            if annotationManager.isAnnotationMode,
               !annotationManager.isTextInputVisible,
               !annotationManager.currentFrameText.isEmpty {
                AnnotationTextOverlayView(text: annotationManager.currentFrameText)
                    .padding(.horizontal, 20)
                    .padding(.top, controlsState.isVisible ? 72 : 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
            }

            // A looping tile restarts at once; no end screen in between.
            VideoPlaybackStatusOverlay(
                status: endAction == .loop && currentPlayer.playbackStatus == .ended ? nil : currentPlayer.playbackStatus,
                endActions: videoEndActions
            ) {
                currentPlayer.play()
            }

            // Capture flash overlay (shutter effect)
            if tile.showCaptureFlash {
                Color.white
                    .allowsHitTesting(false)
            }

            if let error = currentPlayer.error {
                VideoErrorView(error: error, onRetry: {
                    currentPlayer.retry()
                })
            }

        }
    }

    // MARK: - Adjacent Video Layer (for fluid swipe)

    @ViewBuilder
    private func adjacentVideoLayer(direction: SwipeDirection, geometry: GeometryProxy) -> some View {
        let offsetX: CGFloat = swipeOffset > 0 ? -geometry.size.width + swipeOffset : geometry.size.width + swipeOffset
        let opacity = min(abs(swipeOffset) / swipeThreshold, 1.0)

        if let adjacentPlayer = playerManager.playerForDirection(direction) {
            // Show actual video player for smooth transition
            VideoPlayerView(playerState: adjacentPlayer)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .offset(x: offsetX)
                .opacity(Double(opacity))
        } else if let frame = tileHistory.frameForDirection(direction) {
            // Fallback to static frame if player not available
            Image(decorative: frame, scale: 1.0)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .offset(x: offsetX)
                .opacity(Double(opacity))
        }
    }

    // MARK: - Controls Overlay Layer

    private func controlsOverlayLayer(geometry: GeometryProxy) -> some View {
        let isCompactControls = geometry.size.height < 400
        let buttonSpacing: CGFloat = isCompactControls ? 6 : 12
        let controlsPadding: CGFloat = isCompactControls ? 8 : 16
        let overlayScale: CGFloat = isCompactControls ? max(0.5, geometry.size.height / 500) : 1.0

        // The bottom button bar is sized by tile width, not height, so a tile
        // can be tall enough to stay non-compact yet too narrow to fit every
        // button in a 3-column grid. Compute how wide the bar needs to be and
        // scale it down to fit so no button spills outside the tile. The capture
        // button is intentionally NOT in this bar (it lives on its own row), so
        // the bar's button count — and thus its size — never changes on pause.
        let barButtonSize: CGFloat = isCompactControls ? 32 : 44
        // Transparent, non-interactive placeholder used to line up the capture
        // button on its own row directly above the corresponding bar button.
        let barSlot = Color.clear
            .frame(width: barButtonSize, height: barButtonSize)
            .allowsHitTesting(false)
        var barButtonCount = 3 // audio + framing + manage tags are always shown
        if onRandomVideo != nil { barButtonCount += 1 }
        if onEndActionChange != nil { barButtonCount += 1 }
        if onFullscreen != nil { barButtonCount += 1 }
        if videoId != nil, onQuickAddToList != nil { barButtonCount += 1 }
        if onChangeVideo != nil { barButtonCount += 1 }
        let requiredBarWidth = CGFloat(barButtonCount) * barButtonSize
            + CGFloat(barButtonCount) * buttonSpacing // gaps between buttons + the spacer gap
            + controlsPadding * 2
        let barScale = min(1, geometry.size.width / requiredBarWidth)

        AppLogger.video.debug("controlsOverlayLayer: height=\(geometry.size.height), isCompact=\(isCompactControls), scale=\(overlayScale), barScale=\(barScale)")

        return ZStack {
            // Left side: List badge + Rating overlay (positioned 20% higher)
            HStack {
                VStack(alignment: .leading, spacing: isCompactControls ? 4 : 8) {
                    Spacer(minLength: 0)
                        .frame(maxHeight: .infinity)

                    // List badge (only when a list is applied)
                    if let smartListName = computedSmartListName {
                        SmartListBadge(name: smartListName, videoCount: tile.smartListVideoCount, isSmartList: true)
                            .scaleEffect(overlayScale, anchor: .bottomLeading)
                    } else if let simpleListId = currentSimpleListId,
                              let simpleList = tile.simpleLists.first(where: { $0.id == simpleListId }) {
                        SmartListBadge(name: simpleList.name, videoCount: simpleList.videoCount, isSmartList: false)
                            .scaleEffect(overlayScale, anchor: .bottomLeading)
                    }

                    // Rating overlay
                    if videoId != nil {
                        PlaybackRatingOverlay(
                            videoId: videoId ?? "",
                            ratingInfo: $tile.ratingInfo,
                            videoTags: tile.videoTags,
                            serverURL: serverURL,
                            onGlobalRatingChanged: { tile.setGlobalRating($0) },
                            onTagRatingChanged: { tile.setTagRating($0, $1) },
                            playCount: tile.playCount,
                            viewTime: tile.viewTime,
                            isCompact: true,
                            onExpand: { controlsState.suspendAutoHide() },
                            onCollapse: { controlsState.resumeAutoHide() }
                        )
                        .scaleEffect(overlayScale, anchor: .bottomLeading)

                        if tile.ratingSaveFailed {
                            RatingSaveErrorBadge()
                                .scaleEffect(overlayScale, anchor: .bottomLeading)
                        }
                    }

                    Spacer(minLength: 0)
                        .frame(maxHeight: .infinity)
                        .layoutPriority(1)
                }
                .padding(.leading, isCompactControls ? 6 : 12)
                .padding(.top, geometry.size.height * 0.15)
                Spacer()

                // Right side: Video tags display
                VStack {
                    Spacer()
                    VideoTagsDisplay(tags: tile.videoTags, isCompact: true)
                        .scaleEffect(overlayScale, anchor: .bottomTrailing)
                    Spacer()
                }
                .padding(.trailing, isCompactControls ? 6 : 12)
            }

            // Bottom controls: button bar + transport controls
            VStack(spacing: 0) {
                Spacer()

                // Capture button on its own row above the main bar (only on
                // pause), aligned directly above the random button. Keeping it
                // out of the main bar means the bar's button count never changes,
                // so the bar keeps a constant size/padding between play and pause.
                if videoId != nil, !currentPlayer.isPlaying {
                    HStack(spacing: buttonSpacing) {
                        barSlot // above the audio button
                        Spacer()
                        // Placeholders for every cluster button before the
                        // rightmost one, so the capture button lines up directly
                        // above the far-right (change video / Content Library) button.
                        if onEndActionChange != nil { barSlot } // end action
                        if onRandomVideo != nil { barSlot } // random
                        barSlot // framing
                        if onFullscreen != nil { barSlot } // fullscreen
                        barSlot // manage tags
                        if videoId != nil, onQuickAddToList != nil { barSlot } // quick add
                        CaptureFrameButton(
                            isCapturing: tile.isCapturingFrame,
                            showSuccess: tile.frameCaptureSuccess,
                            showError: tile.frameCaptureError,
                            action: handleCaptureFrame,
                            isCompact: isCompactControls
                        )
                    }
                    .padding(.horizontal, controlsPadding)
                    .padding(.bottom, buttonSpacing)
                    .scaleEffect(barScale, anchor: .center)
                }

                // Horizontal button bar above transport controls
                HStack(spacing: buttonSpacing) {
                    // Unified audio control button (volume, mute, solo) - offset down 10%
                    AudioControlButton(
                        volume: $overrideVolume,
                        isMuted: .constant(isMuted),
                        isSolo: .constant(isSolo),
                        onVolumeChanged: handleVolumeOverrideChange,
                        onMuteToggle: handleMuteToggle,
                        onSoloToggle: handleSoloToggle,
                        onSoloLongPress: handleExclusiveSolo,
                        onPopoverOpen: { controlsState.suspendAutoHide() },
                        onPopoverClose: { controlsState.resumeAutoHide() },
                        isCompact: isCompactControls
                    )

                    Spacer()

                    // End action (stop / loop / next / random)
                    if let onEndActionChange {
                        EndActionButton(
                            endAction: endAction,
                            onChange: onEndActionChange,
                            isCompact: isCompactControls,
                            onMenuOpen: { controlsState.suspendAutoHide() },
                            onMenuClose: { controlsState.resumeAutoHide() }
                        )
                    }

                    // Random video button
                    if onRandomVideo != nil {
                        RandomVideoButton(onRandomVideo: handleRandomVideo, isCompact: isCompactControls)
                    }

                    // Framing mode button
                    FramingModeButton(
                        currentMode: currentFramingMode,
                        onModeChange: handleFramingModeChange,
                        isCompact: isCompactControls
                    )

                    // Fullscreen button
                    if let onFullscreen = onFullscreen {
                        FullscreenButton(onFullscreen: onFullscreen, isCompact: isCompactControls)
                    }

                    // Manage Tags button
                    ManageTagsButton(onManageTags: {
                        showingContentLibrary = true
                    }, isCompact: isCompactControls)

                    // Quick add to list button
                    if videoId != nil, let onQuickAddToList = onQuickAddToList {
                        QuickAddToListButton(onQuickAdd: onQuickAddToList, isCompact: isCompactControls)
                    }

                    // Change video button
                    if let onChangeVideo = onChangeVideo {
                        ChangeVideoButton(onChangeVideo: onChangeVideo, isCompact: isCompactControls)
                    }
                }
                .padding(.horizontal, controlsPadding)
                .padding(.bottom, isCompactControls ? 4 : 8)
                // Shrink the bar when it would otherwise overflow the tile width.
                // When an HStack's content exceeds its frame, SwiftUI centers the
                // overflow (it spills past BOTH edges), so the scale must be
                // anchored at center to pull both ends back inside the tile.
                .scaleEffect(barScale, anchor: .center)

                // Annotation editor panel (above transport controls when annotation mode active)
                if annotationManager.isAnnotationMode {
                    AnnotationEditorView(
                        annotationTimes: annotationManager.annotationTimes.sorted(),
                        currentTime: currentPlayer.currentTime,
                        frameRate: Double(currentPlayer.videoFrameRate),
                        serverURL: serverURL,
                        videoFileId: videoId,
                        onStepBackward: { stepFrame(by: -1) },
                        onStepForward: { stepFrame(by: 1) },
                        onSeekToFrame: { time in
                            annotationManager.seekToFrame(time: time, of: currentPlayer)
                        },
                        onDeleteAnnotation: { time in
                            Task { await annotationManager.deleteAnnotation(frameTime: time) }
                        },
                        isCompact: isCompactControls
                    )
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, controlsPadding)
                    .padding(.bottom, 4)
                }

                // ToI editor panel (above transport controls when active)
                if isToIMode {
                    TimeRangeEditorView(
                        timeRanges: tile.timeRanges,
                        currentTime: currentPlayer.currentTime,
                        pendingStart: $tile.pendingToIStart,
                        editingRangeId: $tile.editingToIRangeId,
                        serverURL: serverURL,
                        videoFileId: videoId,
                        frameRate: Double(currentPlayer.videoFrameRate),
                        onCreateRange: { tile.createTimeRange(start: $0, end: $1) },
                        onUpdateRange: { tile.updateTimeRange($0, start: $1, end: $2) },
                        onDeleteRange: { tile.deleteTimeRange($0) },
                        onSeek: handleSeekToTime,
                        onDone: {
                            tile.editingToIRangeId = nil
                            tile.pendingToIStart = nil
                            isToIMode = false
                        }
                    )
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, controlsPadding)
                    .padding(.bottom, 4)
                }

                // List membership chips (smart + simple lists this video is in)
                if !membershipSmartLists.isEmpty || !membershipSimpleLists.isEmpty {
                    ListMembershipChips(
                        smartLists: membershipSmartLists,
                        simpleLists: membershipSimpleLists,
                        isCompact: isCompactControls
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, controlsPadding)
                    .padding(.bottom, 4)
                }

                // Transport controls at bottom
                TransportControlsView(
                    playerState: currentPlayer,
                    controlsState: controlsState,
                    serverURL: serverURL,
                    previewCoordinateSpace: coordinateSpaceName,
                    scrubPreviewState: $scrubPreviewState,
                    onScrubStart: {
                        showScrubPreview = true
                    },
                    onScrubEnd: {
                        showScrubPreview = false
                    },
                    filename: currentVideoFilename,
                    sourceName: currentVideoSourceName,
                    isCompact: isCompactControls,
                    timeRanges: timeRangeColoredIntervals,
                    isToIMode: isToIMode,
                    pendingStart: tile.pendingToIStart,
                    editingRange: editingToIRange,
                    onToIModeToggle: { isToIMode.toggle() },
                    isAnnotationMode: annotationManager.isAnnotationMode,
                    onAnnotationModeToggle: { handleAnnotationModeToggle() },
                    isTextInputVisible: annotationManager.isTextInputVisible,
                    hasTextAnnotation: !annotationManager.currentFrameText.isEmpty,
                    onTextInputToggle: { annotationManager.setTextInputVisible(!annotationManager.isTextInputVisible) }
                )
                .padding(controlsPadding)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: isCompactControls ? 6 : 8))
                .padding(controlsPadding)
            }
        }
        // Pin the overlay's layout size to the tile. Without this, an
        // overflowing button bar (e.g. the capture button on pause) makes the
        // HStack report a width wider than the tile; that width propagates up
        // to the shared ZStack and is re-proposed to the sibling VideoPlayerView,
        // whose resizeAspectFill layer then re-crops and looks like the video
        // zooming/shifting until playback resumes. Fixing the frame stops the
        // overflow from ever reaching the video layer.
        .frame(width: geometry.size.width, height: geometry.size.height)
        // Hard guarantee that no control/overlay can ever visually escape the
        // tile (the "cadre"), regardless of button count or scale rounding.
        .clipped()
    }

    // MARK: - Time Range Handlers

    private func handleSeekToTime(_ time: Double) {
        currentPlayer.seek(to: time)
    }

    // MARK: - Annotation Handlers

    private func handleAnnotationModeToggle() {
        annotationManager.toggleAnnotationMode(of: currentPlayer)
    }

    private func handleTextAnnotationChange(_ newText: String) {
        // The displayed frame: the text belongs with the strokes shown.
        let frameTime = annotationManager.displayedFrameTime ?? currentPlayer.currentTime
        let frameRate = Double(currentPlayer.videoFrameRate)

        Task {
            await annotationManager.saveTextAnnotation(
                text: newText,
                frameTime: frameTime,
                frameRate: frameRate
            )
        }
    }

    private func stepFrame(by delta: Int) {
        annotationManager.stepFrame(by: delta, of: currentPlayer)
    }

    private func videoSize(for playerState: VideoPlayerState) -> CGSize {
        playerState.videoPresentationSize
    }

    // MARK: - Metadata

    private func loadAnnotations() {
        tile.loadAnnotations { currentPlayer }
    }

    private func loadListsForBadge() {
        tile.loadLists(smartListId: currentSmartListId, simpleListId: currentSimpleListId, tileIndex: tileIndex)
    }

    // MARK: - Navigation Indicators

    private var navigationIndicatorsView: some View {
        HStack {
            // Back indicator (left side)
            if tileHistory.canGoBack && swipeOffset > 0 {
                VStack {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(min(swipeOffset / swipeThreshold, 1.0)))
                    Text("Previous")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(min(swipeOffset / swipeThreshold, 1.0)))
                }
                .padding(.leading, 20)
            }

            Spacer()

            // Forward indicator (right side)
            if tileHistory.canGoForward && swipeOffset < 0 {
                VStack {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(min(abs(swipeOffset) / swipeThreshold, 1.0)))
                    Text("Next")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(min(abs(swipeOffset) / swipeThreshold, 1.0)))
                }
                .padding(.trailing, 20)
            }
        }
    }

    // MARK: - Swipe Gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 50)
            .onChanged { value in
                handleSwipeChanged(value)
            }
            .onEnded { value in
                handleSwipeEnded(value)
            }
    }

    private func handleSwipeChanged(_ value: DragGesture.Value) {
        let horizontalAmount = value.translation.width
        let verticalAmount = value.translation.height

        // Only handle horizontal swipes
        guard abs(horizontalAmount) > abs(verticalAmount) else { return }

        // Check if we can navigate in this direction
        let canNavigate: Bool
        if horizontalAmount > 0 {
            canNavigate = tileHistory.canGoBack
            swipeDirection = .back
        } else {
            canNavigate = tileHistory.canGoForward
            swipeDirection = .forward
        }

        guard canNavigate else {
            // Small resistance when can't navigate
            swipeOffset = horizontalAmount * 0.2
            return
        }

        isSwipeActive = true
        swipeOffset = horizontalAmount
    }

    private func handleSwipeEnded(_ value: DragGesture.Value) {
        let horizontalAmount = value.translation.width
        let velocity = value.velocity.width

        // Check if swipe should trigger navigation
        let shouldNavigate = abs(horizontalAmount) > swipeThreshold || abs(velocity) > 500

        if shouldNavigate {
            if horizontalAmount > 0 && tileHistory.canGoBack {
                // Navigate back
                captureStateAndNavigate(direction: .back)
            } else if horizontalAmount < 0 && tileHistory.canGoForward {
                // Navigate forward
                captureStateAndNavigate(direction: .forward)
            } else {
                // Can't navigate, spring back
                resetSwipeState()
            }
        } else {
            // Spring back
            resetSwipeState()
        }
    }

    private func captureStateAndNavigate(direction: SwipeDirection) {
        Task {
            // Capture current frame and playback time before navigating
            let capturedFrame = await playerManager.captureCurrentFrame()
            let currentTime = playerManager.currentPlaybackTime

            await MainActor.run {
                // Update history with captured state
                tileHistory.updateCurrentState(frame: capturedFrame, playbackTime: currentTime)

                // Perform navigation using player swapping
                switch direction {
                case .back:
                    _ = playerManager.navigateBack()
                    onNavigateBack?()
                case .forward:
                    _ = playerManager.navigateForward()
                    onNavigateForward?()
                }

                // Update volume after navigation to ensure correct level
                updateVolume()

                // Re-assert the tile's mute on the player swapped in
                applyMuteStateToCurrentPlayer()

                // Reset swipe state after navigation
                withAnimation(.easeOut(duration: 0.2)) {
                    resetSwipeState()
                }
            }
        }
    }

    private func resetSwipeState() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            swipeOffset = 0
            isSwipeActive = false
            swipeDirection = nil
        }
    }

    /// Next and Random on the end screen, when the grid provides them.
    private var videoEndActions: VideoEndActions? {
        guard onNextVideo != nil, onRandomVideo != nil else { return nil }
        return VideoEndActions(
            onNext: handleNextVideo,
            onRandom: handleRandomVideo,
            sourceName: attachedSmartListName ?? attachedSimpleListName
        )
    }

    // MARK: - Random Video Handler

    private func handleRandomVideo() {
        Task {
            // Capture current frame and playback time before switching
            let capturedFrame = await playerManager.captureCurrentFrame()
            let currentTime = playerManager.currentPlaybackTime

            await MainActor.run {
                // Update history with captured state
                tileHistory.updateCurrentState(frame: capturedFrame, playbackTime: currentTime)

                // Trigger random video callback
                onRandomVideo?()
            }
        }
    }

    // MARK: - Next Video Handler

    private func handleNextVideo() {
        Task {
            let capturedFrame = await playerManager.captureCurrentFrame()
            let currentTime = playerManager.currentPlaybackTime

            await MainActor.run {
                tileHistory.updateCurrentState(frame: capturedFrame, playbackTime: currentTime)
                onNextVideo?()
            }
        }
    }

    // MARK: - Frame Capture

    private func handleCaptureFrame() {
        tile.captureFrame(at: currentPlayer.currentTime)
    }

    // MARK: - Framing Mode Handler

    private func handleFramingModeChange(_ newMode: FramingMode) {
        framingState?.framingMode = newMode
        // Sync gesture state when switching to custom mode
        if newMode == .custom {
            syncGestureStateFromFramingState()
        }
    }

    // MARK: - Reset Framing

    func resetCustomFraming() {
        guard currentFramingMode == .custom else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        framingState?.resetCustomFraming()
        gestureScale = 1.0
        gestureOffset = .zero
        baseScale = 1.0
        baseOffset = .zero
    }

    init(videoURL: URL, tileIndex: Int, onTap: @escaping () -> Void, videoId: String? = nil, initialPlayCount: Int = 0, initialViewTime: Int = 0, onChangeVideo: (() -> Void)? = nil, onRandomVideo: (() -> Void)? = nil, onNavigateBack: (() -> Void)? = nil, onNavigateForward: (() -> Void)? = nil, onFullscreen: (() -> Void)? = nil, onQuickAddToList: (() -> Void)? = nil, attachedSmartListName: String? = nil, attachedSimpleListName: String? = nil, attachedSimpleListVideoCount: Int? = nil, framingState: TileFramingState? = nil) {
        self.videoURL = videoURL
        self.tileIndex = tileIndex
        self.onTap = onTap
        self.videoId = videoId
        self.initialPlayCount = initialPlayCount
        self.initialViewTime = initialViewTime
        self.onChangeVideo = onChangeVideo
        self.onRandomVideo = onRandomVideo
        self.onNavigateBack = onNavigateBack
        self.onNavigateForward = onNavigateForward
        self.onFullscreen = onFullscreen
        self.onQuickAddToList = onQuickAddToList
        self.attachedSmartListName = attachedSmartListName
        self.attachedSimpleListName = attachedSimpleListName
        self.attachedSimpleListVideoCount = attachedSimpleListVideoCount
        self.framingState = framingState
        AppLogger.video.info("VideoTileView init: playCount=\(initialPlayCount), viewTime=\(initialViewTime)")
        self._tile = State(initialValue: TileController(playCount: initialPlayCount, viewTime: initialViewTime))
    }
}

// MARK: - Backward Compatible Initializer

extension VideoTileView {
    /// Full initializer matching all parameters
    init(
        videoURL: URL,
        tileIndex: Int,
        isSelected: Bool = false,
        onTap: @escaping () -> Void,
        videoId: String? = nil,
        initialPlayCount: Int = 0,
        initialViewTime: Int = 0,
        onChangeVideo: (() -> Void)? = nil,
        onRandomVideo: (() -> Void)? = nil,
        onNavigateBack: (() -> Void)? = nil,
        onNavigateForward: (() -> Void)? = nil,
        onFullscreen: (() -> Void)? = nil,
        onQuickAddToList: (() -> Void)? = nil,
        attachedSmartListName: String? = nil,
        attachedSimpleListName: String? = nil,
        attachedSimpleListVideoCount: Int? = nil,
        framingState: TileFramingState? = nil,
        onNextVideo: (() -> Void)? = nil,
        endAction: TileEndAction = .stop,
        onEndActionChange: ((TileEndAction) -> Void)? = nil
    ) {
        self.videoURL = videoURL
        self.tileIndex = tileIndex
        self.isSelected = isSelected
        self.onNextVideo = onNextVideo
        self.endAction = endAction
        self.onEndActionChange = onEndActionChange
        self.onTap = onTap
        self.videoId = videoId
        self.initialPlayCount = initialPlayCount
        self.initialViewTime = initialViewTime
        self.onChangeVideo = onChangeVideo
        self.onRandomVideo = onRandomVideo
        self.onNavigateBack = onNavigateBack
        self.onNavigateForward = onNavigateForward
        self.onFullscreen = onFullscreen
        self.onQuickAddToList = onQuickAddToList
        self.attachedSmartListName = attachedSmartListName
        self.attachedSimpleListName = attachedSimpleListName
        self.attachedSimpleListVideoCount = attachedSimpleListVideoCount
        self.framingState = framingState
        self._tile = State(initialValue: TileController(playCount: initialPlayCount, viewTime: initialViewTime))
    }

    /// Backward compatible initializer without new parameters
    init(videoURL: URL, onTap: @escaping () -> Void, onChangeVideo: (() -> Void)? = nil) {
        self.init(
            videoURL: videoURL,
            tileIndex: 0,
            isSelected: false,
            onTap: onTap,
            videoId: nil,
            initialPlayCount: 0,
            initialViewTime: 0,
            onChangeVideo: onChangeVideo,
            onRandomVideo: nil,
            onNavigateBack: nil,
            onNavigateForward: nil,
            onFullscreen: nil,
            framingState: nil
        )
    }
}

#Preview {
    VideoTileView(
        videoURL: URL(string: "http://localhost:8080/api/v1/videos/test/stream")!,
        tileIndex: 0,
        onTap: {},
        onChangeVideo: {},
        onRandomVideo: {},
        onFullscreen: {}
    )
    .environment(GlobalPlaybackManager.shared)
    .environment(VideoHistoryManager())
    .environment(SharedPlayerPool())
    .frame(width: 400, height: 300)
    .background(Color.black)
}

#Preview("Multiple Tiles") {
    VStack(spacing: 8) {
        HStack(spacing: 8) {
            VideoTileView(
                videoURL: URL(string: "http://localhost:8080/api/v1/videos/1/stream")!,
                tileIndex: 0,
                onTap: {},
                onChangeVideo: {},
                onRandomVideo: {},
                onFullscreen: {}
            )
            VideoTileView(
                videoURL: URL(string: "http://localhost:8080/api/v1/videos/2/stream")!,
                tileIndex: 1,
                onTap: {},
                onChangeVideo: {},
                onRandomVideo: {},
                onFullscreen: {}
            )
        }
    }
    .environment(GlobalPlaybackManager.shared)
    .environment(VideoHistoryManager())
    .environment(SharedPlayerPool())
    .frame(height: 300)
    .padding()
}

#Preview("Without Change Button") {
    VideoTileView(
        videoURL: URL(string: "http://localhost:8080/api/v1/videos/test/stream")!,
        onTap: {}
    )
    .environment(GlobalPlaybackManager.shared)
    .environment(VideoHistoryManager())
    .environment(SharedPlayerPool())
    .frame(width: 400, height: 300)
    .background(Color.black)
}

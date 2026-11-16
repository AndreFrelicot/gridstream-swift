//
//  FullscreenModeView.swift
//  gridstream-ipad
//
//  Uses SharedPlayerPool to reference the same players as grid tiles,
//  enabling seamless transitions without video reload or position loss.
//

import AVFoundation
import GridStreamAPI
import OSLog
import SwiftUI

struct FullscreenModeView: View {
    let tiles: [Tile]
    let fullscreenTileIndex: Int
    let tileLayouts: [TileLayout]
    let pipLayouts: [PiPLayoutEntry]
    let onExitFullscreen: () -> Void
    let onSwapFullscreen: (Int, PiPTransform) -> Void  // (pipTileIndex, transform)
    let onPiPPositionChanged: (Int, CGPoint) -> Void
    let onPiPScaleChanged: (Int, CGFloat) -> Void
    let onPiPRotationChanged: (Int, CGFloat) -> Void
    var onQuickAddToList: ((Int) -> Void)?
    var onRandomVideo: ((Int) -> Void)?
    var onNextVideo: ((Int) -> Void)?
    var onVideoSelected: ((Int, VideoItem) -> Void)?
    /// Height of the status bar area. The view sits in a container that
    /// ignores the safe area, so it reads zero insets itself.
    var topSafeAreaInset: CGFloat = 0

    @Environment(GlobalPlaybackManager.self) private var playbackManager
    @Environment(GridState.self) private var gridState
    @Environment(VideoHistoryManager.self) private var historyManager
    @Environment(SharedPlayerPool.self) private var playerPool
    @Environment(ServerSessionManager.self) private var sessionManager

    @State private var controlsState = VideoControlsState()
    @State private var scrubPreviewState: ScrubPreviewState?
    @State private var showScrubPreview = false
    @Namespace private var fullscreenNamespace

    /// Server metadata for the fullscreen video (rating, tags, time ranges,
    /// annotations, captures, list badges) and its stale-response guards.
    @State private var tile = TileController()
    private var annotationManager: AnnotationManager { tile.annotationManager }

    // Volume override state (per-tile, keyed by tile index)
    @State private var volumeOverrideStates: [Int: Bool] = [:]
    @State private var volumeOverrideLevels: [Int: Float] = [:]

    // SuperSolo state (fullscreen-only mode)
    @State private var isSuperSoloActive: Bool = false

    // Global pause state for play/pause all toggle
    @State private var isAllPaused: Bool = false

    // Stereo panning state
    @State private var isStereoPanningActive: Bool = false
    @State private var recalculatePanTrigger: Bool = false

    // PiP layout memory state
    @State private var isPiPLayoutMemoryActive: Bool = !UserDefaults.standard.bool(forKey: "pipLayoutMemoryDisabled")
    @State private var pipLayoutResetTrigger = 0

    // PiP dismiss gesture state
    @State private var pipDismissProgress: CGFloat = 0
    @State private var pipDismissCorner: DiagonalCorner = .topRight
    @State private var isPiPsDismissed: Bool = false
    @State private var isDismissGestureActive: Bool = false

    // Shared audio state manager for persistence across tile/fullscreen modes
    private var audioStateManager: TileAudioStateManager { TileAudioStateManager.shared }

    private let coordinateSpaceName = "fullscreen"

    // MARK: - Volume Constants
    private static let fullscreenVolume: Float = 1.0
    private static let pipVolume: Float = 0.3

    // Time of Interest mode
    @State private var isToIMode: Bool = false

    // Capture gallery mode
    @State private var isCaptureGalleryMode = false

    // Content library state
    @State private var showingContentLibrary = false
    @State private var contentLibraryInitialTab: UnifiedContentTab = .tags

    // MARK: - Framing State

    private var fullscreenTileLayout: TileLayout? {
        tileLayouts.first(where: { $0.index == fullscreenTileIndex })
    }

    private var framingState: TileFramingState? {
        fullscreenTileLayout?.framingState
    }

    private var currentFramingMode: FramingMode {
        framingState?.framingMode ?? .fill
    }

    private var currentZoomLevel: CGFloat {
        CGFloat(framingState?.customZoomLevel ?? 1.0)
    }

    private var currentPanOffset: CGPoint {
        framingState?.customPanOffset ?? .zero
    }

    // MARK: - Computed Properties

    private var fullscreenTile: Tile? {
        tiles.first(where: { $0.index == fullscreenTileIndex })
    }

    private var fullscreenVideoURL: URL? {
        fullscreenTile?.videoURL
    }

    private var fullscreenVideoId: String? {
        fullscreenTile?.videoId
    }

    /// Gets the player for the fullscreen tile from the shared pool
    private var fullscreenPlayerState: VideoPlayerState? {
        guard playerPool.hasCurrentPlayer(forTile: fullscreenTileIndex) else { return nil }
        return playerPool.currentPlayer(forTile: fullscreenTileIndex)
    }

    private var fullscreenPlayerTime: VideoPlayerState.Reading<Double> {
        VideoPlayerState.Reading(playerID: fullscreenPlayerState?.id, value: fullscreenPlayerState?.currentTime)
    }

    private var fullscreenPlayerSeek: VideoPlayerState.Reading<VideoPlayerState.SeekMarker> {
        VideoPlayerState.Reading(playerID: fullscreenPlayerState?.id, value: fullscreenPlayerState?.lastSeek)
    }

    /// Gets player states for all tiles from the shared pool
    private var playerStatesFromPool: [Int: VideoPlayerState] {
        var states: [Int: VideoPlayerState] = [:]
        for tile in tiles where tile.videoURL != nil {
            if playerPool.hasCurrentPlayer(forTile: tile.index) {
                states[tile.index] = playerPool.currentPlayer(forTile: tile.index)
            }
        }
        return states
    }

    /// Extract server URL from video URL
    private var serverURL: URL? {
        guard let videoURL = fullscreenVideoURL,
              let host = videoURL.host,
              let scheme = videoURL.scheme else { return nil }
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

    /// Capture marker positions for the seek bar
    private var captureMarkerPositions: [Double] {
        tile.captures.map { $0.timestamp }
    }

    /// The editing range's bounds for seek bar animation
    private var editingToIRange: ClosedRange<Double>? {
        guard let id = tile.editingToIRangeId,
              let range = tile.timeRanges.first(where: { $0.id == id }) else { return nil }
        return range.startTime...range.endTime
    }

    // MARK: - Video Info Properties

    private var currentVideoFilename: String? {
        guard let id = fullscreenVideoId else { return nil }
        return historyManager.availableVideos.first { $0.fileId == id }?.filename
    }

    private var currentVideoSourceName: String? {
        guard let id = fullscreenVideoId else { return nil }
        return historyManager.availableVideos.first { $0.fileId == id }?.sourceDirectoryName
    }

    // MARK: - List Badge Properties

    /// Returns the smart list name for the fullscreen tile's attached smart list
    private var currentSmartListName: String? {
        guard let smartListId = fullscreenTile?.smartListId else { return nil }
        return tile.smartLists.first { $0.id == smartListId }?.name
    }

    /// Returns the simple list for the fullscreen tile's attached simple list
    private var currentSimpleList: SimpleListDTO? {
        guard let simpleListId = fullscreenTile?.simpleListId else { return nil }
        return tile.simpleLists.first { $0.id == simpleListId }
    }

    /// Next and Random on the end screen, when the grid provides them.
    private var videoEndActions: VideoEndActions? {
        guard let onNextVideo, let onRandomVideo else { return nil }
        let index = fullscreenTileIndex
        return VideoEndActions(
            onNext: { onNextVideo(index) },
            onRandom: { onRandomVideo(index) },
            sourceName: currentSmartListName ?? currentSimpleList?.name
        )
    }

    private var membershipSmartLists: [SmartListInfo] { tile.memberSmartLists(of: fullscreenVideoId) }
    private var membershipSimpleLists: [SimpleListDTO] { tile.memberSimpleLists(of: fullscreenVideoId) }

    private var annotationTextSheetBinding: Binding<Bool> {
        Binding(
            get: { annotationManager.isTextInputVisible },
            set: { annotationManager.setTextInputVisible($0) }
        )
    }

    var body: some View {
        ZStack {
            // Layer 1: Fullscreen video (bottom)
            fullscreenVideoLayer

            // Layer 2: PiP container - uses players from pool
            PiPContainerView(
                tiles: tiles,
                fullscreenTileIndex: fullscreenTileIndex,
                tileLayouts: tileLayouts,
                pipLayouts: pipLayouts,
                playerStates: playerStatesFromPool,
                serverURL: serverURL,
                onSwapToFullscreen: { pipIndex, transform in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        onSwapFullscreen(pipIndex, transform)
                    }
                },
                onPositionChanged: onPiPPositionChanged,
                onScaleChanged: onPiPScaleChanged,
                onRotationChanged: onPiPRotationChanged,
                recalculatePanTrigger: recalculatePanTrigger,
                dismissProgress: pipDismissProgress,
                dismissCorner: pipDismissCorner,
                isPiPLayoutMemoryEnabled: isPiPLayoutMemoryActive,
                layoutResetTrigger: pipLayoutResetTrigger
            )

            // Layer 2.5: Dismiss guide overlay
            if isDismissGestureActive {
                PiPDismissGuideView(
                    progress: pipDismissProgress,
                    corner: pipDismissCorner,
                    isDismissed: isPiPsDismissed
                )
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            // Layer 3: Controls overlay (top - above PiP tiles when visible)
            if controlsState.isVisible {
                controlsOverlayLayer
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
                    GeometryReader { rulerGeo in
                        ScrubRulerView(
                            centerX: previewState.thumbCenterX,
                            centerY: previewState.fingerY,
                            anchorTime: previewState.rulerAnchorTime,
                            currentTime: previewState.rulerCurrentTime,
                            visibleRange: previewState.rulerVisibleRange,
                            containerWidth: rulerGeo.size.width,
                            scrubLevel: previewState.scrubLevel,
                            frameRate: previewState.frameRate
                        )
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
        }
        .coordinateSpace(name: coordinateSpaceName)
        .background {
            // 2-finger diagonal dismiss gesture — installs on UIKit window, never blocks touches
            PiPDismissGestureView(
                onGestureChanged: handleDismissGestureChanged,
                onGestureEnded: handleDismissGestureEnded
            )
            .allowsHitTesting(false)
        }
        .onAppear {
            tile.show(videoId: fullscreenVideoId, serverURL: serverURL)
            updatePlaybackDiagnosticContexts()
            // Load persisted audio state from shared manager for all tiles
            loadAudioStateFromManager()
            adjustPlayerVolumes()
            tile.loadRating()
            loadListsData()
            tile.loadMemberships()
            tile.loadTimeRanges()
            tile.loadCaptures()
            loadAnnotations()
            // Load stereo panning state
            isStereoPanningActive = StereoPanState.shared.isEnabled
            // Sync play/pause state from actual player states
            syncPlayPauseState()
        }
        .onChange(of: fullscreenTileIndex) { oldIndex, newIndex in
            updatePlaybackDiagnosticContexts()
            // Swap tile - load audio state for new tile and adjust volumes
            loadAudioStateFromManager()
            adjustPlayerVolumes()
            tile.loadRating()
            loadListsData()
            // Same video on both tiles: no annotation reload follows, so the
            // displayed frame follows the new player here.
            if tiles.first(where: { $0.index == oldIndex })?.videoId == fullscreenVideoId,
               let playerState = fullscreenPlayerState {
                annotationManager.syncFromTimelineIfNeeded(of: playerState)
            }

            // If superSolo is active, switch it to the new fullscreen tile
            if isSuperSoloActive, let newPlayer = playerPool.hasCurrentPlayer(forTile: newIndex) ? playerPool.currentPlayer(forTile: newIndex) : nil {
                GlobalPlaybackManager.shared.activateSuperSolo(for: newPlayer)
            }
        }
        .onDisappear {
            for playerState in playerStatesFromPool.values {
                playerState.diagnosticDisplayContext = "tile"
            }
        }
        // The grid's tile views, which load a tile's new video, are not on
        // screen in fullscreen: load it here, for the fullscreen tile and for
        // the PiP tiles alike (Next or Play Random at the end of a PiP video).
        .onChange(of: tiles.map(\.videoURL)) { oldURLs, newURLs in
            for (position, tile) in tiles.enumerated() {
                let oldURL = position < oldURLs.count ? oldURLs[position] : nil
                guard position < newURLs.count, oldURL != newURLs[position] else { continue }
                loadVideoChange(forTile: tile.index, videoId: tile.videoId, from: oldURL, to: newURLs[position])
            }
        }
        .onChange(of: fullscreenVideoId) { _, _ in
            // A new video also resets ToI editing and leaves annotation mode
            tile.show(videoId: fullscreenVideoId, serverURL: serverURL)
            tile.loadRating()
            loadListsData()
            tile.loadMemberships()
            tile.loadTimeRanges()
            tile.loadCaptures()
            // Reset capture gallery on video change
            isCaptureGalleryMode = false
            loadAnnotations()
        }
        // A load sent before the session check (expired token, Mac not
        // reachable yet) failed: load again on another server and once
        // requests are authorized (and after a re-login).
        .onChange(of: metadataReloadKey) { _, key in
            tile.show(videoId: fullscreenVideoId, serverURL: serverURL)
            guard key.authorizedTokenRevision != nil else { return }
            tile.loadRating()
            tile.loadTimeRanges()
            tile.loadCaptures()
        }
        // Changes from switching to another tile's player are ignored: the
        // annotations of its video load with the switch.
        .onChange(of: fullscreenPlayerTime) { old, new in
            guard old.playerID == new.playerID, let playerState = fullscreenPlayerState else { return }
            annotationManager.syncFromTimelineIfNeeded(of: playerState)
        }
        .onChange(of: fullscreenPlayerSeek) { old, new in
            guard old.playerID == new.playerID, let marker = new.value, let playerState = fullscreenPlayerState else { return }
            annotationManager.syncFromSeek(marker, of: playerState)
        }
        .onChange(of: fullscreenPlayerState?.isPlaying) { _, isPlaying in
            guard isPlaying == true, let playerState = fullscreenPlayerState else { return }
            annotationManager.exitAnnotationModeForPlayback(of: playerState)
        }
        .onChange(of: annotationManager.isAnnotationMode) { _, isAnnotating in
            if isAnnotating {
                controlsState.suspendAutoHide()
            } else {
                controlsState.resumeAutoHide()
            }
        }
        .sheet(isPresented: $showingContentLibrary) {
            UnifiedContentLibraryView(
                isPresented: $showingContentLibrary,
                serverURL: serverURL,
                initialTab: contentLibraryInitialTab,
                currentVideoId: fullscreenVideoId,
                appliedTagIds: Set(tile.videoTags.map { $0.id }),
                onTagAppliedToVideo: { _ in tile.loadRating() },
                targetTileIndex: fullscreenTileIndex,
                onVideoSelected: { video in
                    onVideoSelected?(fullscreenTileIndex, video)
                },
                onApplySmartListToTileAt: { smartListId, tileIndex in
                    gridState.setSmartList(smartListId, at: tileIndex)
                    loadListsData()
                },
                onApplySimpleListToTileAt: { simpleListId, tileIndex in
                    gridState.setSimpleList(simpleListId, at: tileIndex)
                    loadListsData()
                },
                tiles: tiles,
                initialSmartListId: fullscreenTile?.smartListId,
                initialSimpleListId: fullscreenTile?.simpleListId
            )
            .presentationDetents([.large])
            .id(contentLibraryInitialTab)
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

    // MARK: - Fullscreen Video Layer

    private var fullscreenVideoLayer: some View {
        ZStack {
            Color.black

            if let playerState = fullscreenPlayerState {
                VideoPlayerView(
                    playerState: playerState,
                    framingMode: currentFramingMode,
                    customScale: currentZoomLevel,
                    customOffset: currentPanOffset
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    controlsState.forceHide()
                }
                .onTapGesture {
                    controlsState.show()
                }

                // PencilKit canvas: drawings show in annotation mode only
                if annotationManager.isAnnotationMode {
                    AnnotationCanvasView(
                        videoSize: videoSize(for: playerState),
                        framingMode: currentFramingMode,
                        customScale: currentZoomLevel,
                        customOffset: currentPanOffset,
                        frameTime: annotationManager.displayedFrameTime ?? playerState.currentTime,
                        existingStrokes: annotationManager.currentFrameStrokes,
                        target: annotationManager.target(frameRate: Double(playerState.videoFrameRate)),
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
                    status: gridState.endAction(at: fullscreenTileIndex) == .loop && playerState.playbackStatus == .ended
                        ? nil : playerState.playbackStatus,
                    endActions: videoEndActions
                ) {
                    playerState.play()
                }

                // Capture flash overlay (shutter effect)
                if tile.showCaptureFlash {
                    Color.white
                        .allowsHitTesting(false)
                }

                if let error = playerState.error {
                    VideoErrorView(error: error, onRetry: {
                        playerState.retry()
                    })
                }

            } else {
                ContentUnavailableView(
                    "No Video",
                    systemImage: "video.slash",
                    description: Text("Select a video to play in fullscreen.")
                )
            }

        }
    }

    // MARK: - Controls Overlay Layer

    private var controlsOverlayLayer: some View {
        ZStack {
            // Top-right exit button, below the status bar: the view ignores
            // the safe area, so it would cover the battery.
            VStack {
                HStack {
                    Spacer()
                    ExitFullscreenButton(onExitFullscreen: {
                        // Deactivate superSolo before exiting to restore audio states
                        if isSuperSoloActive {
                            GlobalPlaybackManager.shared.deactivateSuperSolo()
                            isSuperSoloActive = false
                        }
                        // No need to save positions - same players continue in grid tiles
                        onExitFullscreen()
                    })
                        .padding()
                }
                Spacer()
            }
            .padding(.top, topSafeAreaInset)

            // Left side: Rating overlay, Audio control, and List badge
            HStack {
                VStack(alignment: .leading, spacing: 12) {
                    Spacer()

                    // List badge (bottom left)
                    if let smartListName = currentSmartListName {
                        SmartListBadge(name: smartListName, videoCount: tile.smartListVideoCount, isSmartList: true)
                    } else if let simpleList = currentSimpleList {
                        SmartListBadge(name: simpleList.name, videoCount: simpleList.videoCount, isSmartList: false)
                    }

                    // Rating overlay (left middle)
                    if fullscreenVideoId != nil {
                        PlaybackRatingOverlay(
                            videoId: fullscreenVideoId ?? "",
                            ratingInfo: $tile.ratingInfo,
                            videoTags: tile.videoTags,
                            serverURL: serverURL,
                            onGlobalRatingChanged: { tile.setGlobalRating($0) },
                            onTagRatingChanged: { tile.setTagRating($0, $1) },
                            playCount: tile.playCount,
                            viewTime: tile.viewTime,
                            isCompact: false,
                            onExpand: { controlsState.suspendAutoHide() },
                            onCollapse: { controlsState.resumeAutoHide() }
                        )
                        .frame(maxWidth: 320, alignment: .leading)

                        if tile.ratingSaveFailed {
                            RatingSaveErrorBadge()
                        }
                    }

                    // Audio control button (under rating, like tile mode)
                    AudioControlButton(
                        volume: fullscreenOverrideVolume,
                        isMuted: isFullscreenMuted,
                        isSolo: isFullscreenSolo,
                        onVolumeChanged: handleVolumeOverrideChange,
                        onMuteToggle: handleMuteToggle,
                        onSoloToggle: handleSoloToggle,
                        onSoloLongPress: handleExclusiveSolo,
                        onPopoverOpen: { controlsState.suspendAutoHide() },
                        onPopoverClose: { controlsState.resumeAutoHide() }
                    )

                    // SuperSolo button - temporarily solos fullscreen video
                    SuperSoloButton(
                        isActive: $isSuperSoloActive,
                        onToggle: handleSuperSoloToggle
                    )

                    // Play/Pause all toggle button
                    PlayPauseAllButton(
                        isPaused: $isAllPaused,
                        onPauseAll: { playbackManager.pauseAll() },
                        onPlayAll: { playbackManager.playAll() }
                    )

                    // Stereo panning toggle button
                    StereoPanningButton(
                        isActive: $isStereoPanningActive,
                        onToggle: handleStereoPanningToggle
                    )

                    // PiP layout memory toggle button
                    PiPLayoutMemoryButton(
                        isActive: $isPiPLayoutMemoryActive,
                        action: handlePiPLayoutMemoryToggle,
                        onResetCurrentLayout: {
                            gridState.resetPiPLayout(forFullscreen: fullscreenTileIndex)
                            pipLayoutResetTrigger += 1
                        },
                        onResetAllLayouts: {
                            gridState.resetAllPiPLayouts()
                            pipLayoutResetTrigger += 1
                        },
                        onMenuOpen: { controlsState.suspendAutoHide() },
                        onMenuClose: { controlsState.resumeAutoHide() }
                    )

                    Spacer()
                }
                .padding(.leading, 20)
                Spacer()
            }

            // Right-side controls
            HStack {
                Spacer()
                VStack(spacing: 16) {
                    Spacer()
                    VideoTagsDisplay(tags: tile.videoTags)
                    EndActionButton(
                        endAction: gridState.endAction(at: fullscreenTileIndex),
                        onChange: { action in
                            gridState.setEndAction(action, at: fullscreenTileIndex)
                        },
                        onMenuOpen: { controlsState.suspendAutoHide() },
                        onMenuClose: { controlsState.resumeAutoHide() }
                    )
                    if onRandomVideo != nil {
                        RandomVideoButton {
                            onRandomVideo?(fullscreenTileIndex)
                        }
                    }
                    FramingModeButton(
                        currentMode: currentFramingMode,
                        onModeChange: handleFramingModeChange,
                        onLongPress: handleFramingModeChangeAll
                    )
                    if fullscreenVideoId != nil, let playerState = fullscreenPlayerState, !playerState.isPlaying {
                        CaptureFrameButton(
                            isCapturing: tile.isCapturingFrame,
                            showSuccess: tile.frameCaptureSuccess,
                            showError: tile.frameCaptureError,
                            action: handleCaptureFrame
                        )
                    }
                    if fullscreenVideoId != nil, let onQuickAddToList = onQuickAddToList {
                        QuickAddToListButton {
                            onQuickAddToList(fullscreenTileIndex)
                        }
                    }
                    ManageTagsButton {
                        contentLibraryInitialTab = .tags
                        showingContentLibrary = true
                    }
                    ChangeVideoButton {
                        contentLibraryInitialTab = .content
                        showingContentLibrary = true
                    }
                    Spacer()
                }
                .padding(.trailing, 12)
            }

            // Transport controls at bottom (with optional ToI editor above)
            if let playerState = fullscreenPlayerState {
                VStack {
                    Spacer()

                    // Annotation editor panel (above transport controls when annotation mode active)
                    if annotationManager.isAnnotationMode {
                        AnnotationEditorView(
                            annotationTimes: annotationManager.annotationTimes.sorted(),
                            currentTime: playerState.currentTime,
                            frameRate: Double(playerState.videoFrameRate),
                            serverURL: serverURL,
                            videoFileId: fullscreenVideoId,
                            onStepBackward: { stepFrame(by: -1) },
                            onStepForward: { stepFrame(by: 1) },
                            onSeekToFrame: { time in
                                annotationManager.seekToFrame(time: time, of: playerState)
                            },
                            onDeleteAnnotation: { time in
                                Task { await annotationManager.deleteAnnotation(frameTime: time) }
                            }
                        )
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                    }

                    // ToI editor panel (above transport controls when active)
                    if isToIMode {
                        TimeRangeEditorView(
                            timeRanges: tile.timeRanges,
                            currentTime: playerState.currentTime,
                            pendingStart: $tile.pendingToIStart,
                            editingRangeId: $tile.editingToIRangeId,
                            serverURL: serverURL,
                            videoFileId: fullscreenVideoId,
                            frameRate: Double(fullscreenPlayerState?.videoFrameRate ?? 24),
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
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                    }

                    // Capture gallery panel (above transport controls when active)
                    if isCaptureGalleryMode {
                        CaptureGalleryView(
                            captures: tile.captures,
                            currentTime: playerState.currentTime,
                            serverURL: serverURL,
                            frameRate: Double(playerState.videoFrameRate),
                            onSeek: { time in playerState.seek(to: time) },
                            onDelete: { tile.deleteCapture($0) },
                            onDone: { isCaptureGalleryMode = false }
                        )
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                    }

                    // List membership chips (smart + simple lists this video is in)
                    if !membershipSmartLists.isEmpty || !membershipSimpleLists.isEmpty {
                        ListMembershipChips(
                            smartLists: membershipSmartLists,
                            simpleLists: membershipSimpleLists
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                    }

                    TransportControlsView(
                        playerState: playerState,
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
                        timeRanges: timeRangeColoredIntervals,
                        isToIMode: isToIMode,
                        pendingStart: tile.pendingToIStart,
                        editingRange: editingToIRange,
                        onToIModeToggle: { isToIMode.toggle() },
                        isAnnotationMode: annotationManager.isAnnotationMode,
                        onAnnotationModeToggle: { handleAnnotationModeToggle() },
                        isTextInputVisible: annotationManager.isTextInputVisible,
                        hasTextAnnotation: !annotationManager.currentFrameText.isEmpty,
                        onTextInputToggle: { annotationManager.setTextInputVisible(!annotationManager.isTextInputVisible) },
                        captureMarkerPositions: captureMarkerPositions,
                        isCaptureMode: isCaptureGalleryMode,
                        onCapturesModeToggle: { isCaptureGalleryMode.toggle() }
                    )
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
                }
            }
        }
    }

    // MARK: - Metadata

    /// Loads the lists for the badge and the attached smart list's video count.
    /// Loads a tile's new video into its player from the pool.
    private func loadVideoChange(forTile tileIndex: Int, videoId: String?, from oldURL: URL?, to newURL: URL?) {
        guard let newURL else {
            // The tile lost its video: stop, unregister and free its
            // player so it does not keep playing unseen.
            if oldURL != nil {
                playerPool.removePlayers(forTile: tileIndex)
            }
            return
        }
        guard playerPool.hasCurrentPlayer(forTile: tileIndex) else { return }
        let playerState = playerPool.currentPlayer(forTile: tileIndex)

        // Only update if the player's current URL is different
        guard playerState.videoURL != newURL else { return }

        // Same stream with a new session token (re-login): reload it
        // where it was, in the same play/pause state
        let isTokenRefresh = oldURL.map { VideoURLBuilder.removingToken(from: $0) } == VideoURLBuilder.removingToken(from: newURL)
        let resumeTime = playerState.currentTime
        let resumePlaying = playerState.wantsToPlay

        playbackManager.unregister(playerState)
        if isTokenRefresh {
            playerState.setupPlayer(url: newURL, fileId: videoId, autoplay: resumePlaying)
            Task {
                guard await playerState.waitUntilReadyToPlay() else { return }
                playerState.seek(to: resumeTime)
            }
        } else {
            playerState.setupPlayer(url: newURL, fileId: videoId)
            playerState.play()
        }
        playbackManager.register(playerState)
        adjustPlayerVolumes()
        AppLogger.playback.info("Fullscreen: Updated player of tile \(tileIndex) to new video URL")

        // Re-apply superSolo if active - ensure the new video stays in superSolo mode
        if isSuperSoloActive, tileIndex == fullscreenTileIndex {
            GlobalPlaybackManager.shared.activateSuperSolo(for: playerState)
        }
    }

    private func loadListsData() {
        tile.loadLists(
            smartListId: fullscreenTile?.smartListId,
            simpleListId: fullscreenTile?.simpleListId,
            tileIndex: fullscreenTileIndex
        )
    }

    private func loadAnnotations() {
        tile.loadAnnotations { fullscreenPlayerState }
    }

    // MARK: - Time Range Handlers

    private func handleSeekToTime(_ time: Double) {
        fullscreenPlayerState?.seek(to: time)
    }

    // MARK: - Annotation Handlers

    private func handleAnnotationModeToggle() {
        guard let playerState = fullscreenPlayerState else { return }
        annotationManager.toggleAnnotationMode(of: playerState)
    }

    private func handleTextAnnotationChange(_ newText: String) {
        guard let playerState = fullscreenPlayerState else { return }

        // The displayed frame: the text belongs with the strokes shown.
        let frameTime = annotationManager.displayedFrameTime ?? playerState.currentTime
        let frameRate = Double(playerState.videoFrameRate)

        Task {
            await annotationManager.saveTextAnnotation(
                text: newText,
                frameTime: frameTime,
                frameRate: frameRate
            )
        }
    }

    private func stepFrame(by delta: Int) {
        guard let playerState = fullscreenPlayerState else { return }
        annotationManager.stepFrame(by: delta, of: playerState)
    }

    private func videoSize(for playerState: VideoPlayerState) -> CGSize {
        playerState.videoPresentationSize
    }

    // MARK: - Framing Mode Handler

    private func handleFramingModeChange(_ newMode: FramingMode) {
        framingState?.framingMode = newMode
    }

    private func handleFramingModeChangeAll() {
        let newMode: FramingMode = currentFramingMode == .fill ? .fit : .fill
        for layout in tileLayouts {
            layout.ensureFramingState()
            layout.framingState?.framingMode = newMode
        }
    }

    // MARK: - Frame Capture

    private func handleCaptureFrame() {
        guard let playerState = fullscreenPlayerState else { return }
        tile.captureFrame(at: playerState.currentTime) { tile.loadCaptures() }
    }

    // MARK: - PiP Dismiss Gesture Handlers

    private func handleDismissGestureChanged(translation: CGPoint, velocity: CGPoint, viewSize: CGSize) {
        isDismissGestureActive = true

        // Determine corner from translation direction
        let corner: DiagonalCorner
        if translation.x >= 0 && translation.y >= 0 { corner = .bottomRight }
        else if translation.x >= 0 && translation.y < 0 { corner = .topRight }
        else if translation.x < 0 && translation.y >= 0 { corner = .bottomLeft }
        else { corner = .topLeft }
        pipDismissCorner = corner

        // Calculate progress based on diagonal distance
        let diagonal = sqrt(translation.x * translation.x + translation.y * translation.y)
        let maxDiagonal: CGFloat = 300  // full dismiss at 300pt diagonal

        if isPiPsDismissed {
            // Restoring: progress goes from 1 → 0
            pipDismissProgress = max(0, 1.0 - diagonal / maxDiagonal)
        } else {
            // Dismissing: progress goes from 0 → 1
            pipDismissProgress = min(1.0, diagonal / maxDiagonal)
        }
    }

    private func handleDismissGestureEnded(translation: CGPoint, velocity: CGPoint, viewSize: CGSize) {
        isDismissGestureActive = false
        let diagonal = sqrt(translation.x * translation.x + translation.y * translation.y)

        // Threshold: commit if > 40% distance or velocity is high
        let velocityMagnitude = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        let shouldCommit = diagonal > 120 || velocityMagnitude > 500

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if isPiPsDismissed {
                // Was dismissed, check if restoring
                if shouldCommit {
                    pipDismissProgress = 0
                    isPiPsDismissed = false
                } else {
                    pipDismissProgress = 1.0  // snap back to dismissed
                }
            } else {
                // Was visible, check if dismissing
                if shouldCommit {
                    pipDismissProgress = 1.0
                    isPiPsDismissed = true
                } else {
                    pipDismissProgress = 0  // snap back to visible
                }
            }
        }
    }

    // MARK: - Playback Management

    /// Syncs the play/pause toggle state from actual player playback states.
    /// If all players are paused the button shows "play"; otherwise it shows "pause".
    private func syncPlayPauseState() {
        let playingPlayers = playbackManager.activePlayers.values.filter { $0.wantsToPlay }
        isAllPaused = playingPlayers.isEmpty
    }

    private func updatePlaybackDiagnosticContexts() {
        for (tileIndex, playerState) in playerStatesFromPool {
            playerState.diagnosticDisplayContext = tileIndex == fullscreenTileIndex ? "fullscreen" : "pip"
        }
    }

    private func adjustPlayerVolumes() {
        // Adjust volume levels for all tile players (preserves play/pause state)
        for tile in tiles where tile.videoURL != nil {
            if playerPool.hasCurrentPlayer(forTile: tile.index) {
                let player = playerPool.currentPlayer(forTile: tile.index)
                let isFullscreen = tile.index == fullscreenTileIndex
                // Focus multiplier: fullscreen=100%, PiP=30%
                let focusMultiplier: Float = isFullscreen ? 1.0 : (Self.pipVolume / Self.fullscreenVolume)

                // Check for volume override - apply focus multiplier to override as well
                if volumeOverrideStates[tile.index] == true,
                   let overrideLevel = volumeOverrideLevels[tile.index] {
                    player.setVolume(overrideLevel * focusMultiplier)
                } else {
                    // No override: fullscreen=100%, PiP=30%
                    player.setVolume(isFullscreen ? Self.fullscreenVolume : Self.pipVolume)
                }
            }
        }
    }

    /// Updates volume for a specific tile
    private func updateVolumeForTile(_ tileIndex: Int) {
        guard playerPool.hasCurrentPlayer(forTile: tileIndex) else { return }
        let player = playerPool.currentPlayer(forTile: tileIndex)
        let isFullscreen = tileIndex == fullscreenTileIndex
        // Focus multiplier: fullscreen=100%, PiP=30%
        let focusMultiplier: Float = isFullscreen ? 1.0 : (Self.pipVolume / Self.fullscreenVolume)

        if volumeOverrideStates[tileIndex] == true,
           let overrideLevel = volumeOverrideLevels[tileIndex] {
            player.setVolume(overrideLevel * focusMultiplier)
        } else {
            player.setVolume(isFullscreen ? Self.fullscreenVolume : Self.pipVolume)
        }
    }

    /// Handles volume override change for fullscreen tile
    private func handleVolumeOverrideChange(_ newVolume: Float) {
        volumeOverrideLevels[fullscreenTileIndex] = newVolume
        volumeOverrideStates[fullscreenTileIndex] = true  // Mark override as active when user adjusts volume

        // Save to shared manager for persistence across tile/fullscreen modes
        audioStateManager.setVolumeOverride(active: true, level: newVolume, for: fullscreenTileIndex)

        // This handler only targets the fullscreen tile, so no PiP focus multiplier applies.
        if playerPool.hasCurrentPlayer(forTile: fullscreenTileIndex) {
            playerPool.currentPlayer(forTile: fullscreenTileIndex).setVolume(newVolume)
        }
    }

    /// Binding for fullscreen volume override active state
    private var isFullscreenVolumeOverrideActive: Binding<Bool> {
        Binding(
            get: { volumeOverrideStates[fullscreenTileIndex] ?? false },
            set: { newValue in
                volumeOverrideStates[fullscreenTileIndex] = newValue
                updateVolumeForTile(fullscreenTileIndex)
            }
        )
    }

    /// Binding for fullscreen volume override level
    private var fullscreenOverrideVolume: Binding<Float> {
        Binding(
            get: { volumeOverrideLevels[fullscreenTileIndex] ?? 1.0 },
            set: { volumeOverrideLevels[fullscreenTileIndex] = $0 }
        )
    }

    // MARK: - Audio State Management

    /// Loads audio state from the shared manager (for persistence across tile/fullscreen modes)
    private func loadAudioStateFromManager() {
        // Load state for all tiles
        for tile in tiles where tile.videoURL != nil {
            let state = audioStateManager.state(for: tile.index)
            volumeOverrideStates[tile.index] = state.isVolumeOverrideActive
            volumeOverrideLevels[tile.index] = state.overrideVolume

            // Apply mute state to player. Safe to do while superSolo is active:
            // superSolo silences through the suppression layer, which sits on
            // top of this and is not disturbed by it.
            if playerPool.hasCurrentPlayer(forTile: tile.index) {
                let player = playerPool.currentPlayer(forTile: tile.index)
                player.setMuted(state.isMuted)

                // Re-apply solo state if this tile was solo (solo is exclusive
                // across tiles, so at most one tile gets here)
                if state.isSolo {
                    GlobalPlaybackManager.shared.activateSolo(for: player)
                }
            }
        }
    }

    // MARK: - Mute Management

    /// Handles mute toggle for fullscreen tile
    private func handleMuteToggle() {
        guard let playerState = fullscreenPlayerState else { return }
        let newMuteState = !audioStateManager.isMuted(for: fullscreenTileIndex)

        // Save to shared manager for persistence across tile/fullscreen modes
        audioStateManager.setMuted(newMuteState, for: fullscreenTileIndex)

        // Apply to player
        playerState.setMuted(newMuteState)
    }

    /// Binding for fullscreen mute state
    private var isFullscreenMuted: Binding<Bool> {
        Binding(
            get: { audioStateManager.isMuted(for: fullscreenTileIndex) },
            set: { _ in }  // Changed only through handleMuteToggle
        )
    }

    // MARK: - Solo Management

    /// Handles solo toggle for fullscreen tile. The playback manager records
    /// the tile's solo (exclusive, persisted) and applies it.
    private func handleSoloToggle() {
        guard let playerState = fullscreenPlayerState else { return }
        GlobalPlaybackManager.shared.setSolo(!audioStateManager.isSolo(for: fullscreenTileIndex), for: playerState)
    }

    /// Handles exclusive solo (long press) for fullscreen tile
    private func handleExclusiveSolo() {
        guard let playerState = fullscreenPlayerState else { return }
        GlobalPlaybackManager.shared.exclusiveSolo(for: playerState)
    }

    /// Binding for fullscreen solo state
    private var isFullscreenSolo: Binding<Bool> {
        Binding(
            get: { audioStateManager.isSolo(for: fullscreenTileIndex) },
            set: { _ in }  // Changed only through handleSoloToggle
        )
    }

    // MARK: - SuperSolo Management

    /// Handles SuperSolo toggle for fullscreen tile.
    /// SuperSolo temporarily solos the fullscreen video while preserving original audio states.
    private func handleSuperSoloToggle() {
        guard let playerState = fullscreenPlayerState else { return }

        if isSuperSoloActive {
            // Deactivate superSolo - restore previous audio states
            GlobalPlaybackManager.shared.deactivateSuperSolo()
            isSuperSoloActive = false
        } else {
            // Activate superSolo - mute all except fullscreen, save states for later restore
            GlobalPlaybackManager.shared.activateSuperSolo(for: playerState)
            isSuperSoloActive = true
        }
    }

    // MARK: - Stereo Panning Management

    /// Handles stereo panning toggle.
    /// When enabled, PiP tiles' audio pans left/right based on screen position.
    private func handleStereoPanningToggle() {
        isStereoPanningActive.toggle()
        StereoPanState.shared.setEnabled(isStereoPanningActive)

        if isStereoPanningActive {
            // Trigger recalculation of pan values for all PiP tiles
            recalculatePanTrigger = true
            // Reset trigger after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                recalculatePanTrigger = false
            }
        }
    }

    private func handlePiPLayoutMemoryToggle() {
        isPiPLayoutMemoryActive.toggle()
        gridState.setPiPLayoutMemoryEnabled(isPiPLayoutMemoryActive)
    }

    private func syncPiPPlaybackState(isPlaying: Bool) {
        if isPlaying {
            playbackManager.playAll()
        } else {
            playbackManager.pauseAll()
        }
    }
}

#Preview {
    let tiles = [
        Tile(index: 0, videoURL: URL(string: "http://localhost:8080/api/v1/videos/1/stream")),
        Tile(index: 1, videoURL: URL(string: "http://localhost:8080/api/v1/videos/2/stream")),
        Tile(index: 2, videoURL: URL(string: "http://localhost:8080/api/v1/videos/3/stream")),
        Tile(index: 3, videoURL: URL(string: "http://localhost:8080/api/v1/videos/4/stream"))
    ]

    return FullscreenModeView(
        tiles: tiles,
        fullscreenTileIndex: 0,
        tileLayouts: [],
        pipLayouts: [],
        onExitFullscreen: {},
        onSwapFullscreen: { _, _ in },
        onPiPPositionChanged: { _, _ in },
        onPiPScaleChanged: { _, _ in },
        onPiPRotationChanged: { _, _ in }
    )
    .environment(GlobalPlaybackManager.shared)
    .environment(VideoHistoryManager())
    .environment(SharedPlayerPool())
}

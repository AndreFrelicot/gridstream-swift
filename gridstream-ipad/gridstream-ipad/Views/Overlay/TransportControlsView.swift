//
//  TransportControlsView.swift
//  gridstream-ipad
//

import AVFoundation
import CoreMedia
import OSLog
import SwiftUI

/// Scrub level for multi-level precision scrubbing
enum ScrubLevel: Equatable {
    case normal
    case precision    // 1/10th range
    case frameByFrame // one frame per pixel
}

/// State for the scrub preview, exposed to parent for rendering
struct ScrubPreviewState {
    let previewImage: CGImage?
    let thumbCenterX: CGFloat
    let thumbCenterY: CGFloat
    let scrubLevel: ScrubLevel
    // Ruler data
    let rulerAnchorTime: Double
    let rulerCurrentTime: Double
    let rulerVisibleRange: Double
    let fingerY: CGFloat
    let frameRate: Double
}

struct TransportControlsView: View {
    var playerState: VideoPlayerState?
    var controlsState: VideoControlsState?
    /// Server URL for scrub frame fetching
    var serverURL: URL?
    /// Coordinate space for positioning the preview - must be set by parent
    var previewCoordinateSpace: String = "videoTile"
    /// Binding to receive scrub preview state for rendering at parent level
    @Binding var scrubPreviewState: ScrubPreviewState?
    /// Explicit callback when scrubbing starts - reliable way to show preview
    var onScrubStart: (() -> Void)?
    /// Explicit callback when scrubbing ends - reliable way to hide preview
    var onScrubEnd: (() -> Void)?
    /// Optional filename to display below the controls
    var filename: String?
    /// Optional source name to display below the filename
    var sourceName: String?
    /// Compact mode for small tiles (3x3, 3x4 layouts)
    var isCompact: Bool = false
    /// Time-of-interest ranges to display on the seek bar
    var timeRanges: [(range: ClosedRange<Double>, color: Color)] = []
    /// Whether ToI editing mode is active
    var isToIMode: Bool = false
    /// Pending ToI start time — the seek bar computes the range using the live slider value
    var pendingStart: Double? = nil
    /// Editing range bounds — the seek bar animates this segment with marching ants
    var editingRange: ClosedRange<Double>? = nil
    /// Callback to toggle ToI editing mode
    var onToIModeToggle: (() -> Void)? = nil
    /// Whether annotation mode is active
    var isAnnotationMode: Bool = false
    /// Callback to toggle annotation mode
    var onAnnotationModeToggle: (() -> Void)? = nil
    /// Whether text input is visible in annotation mode
    var isTextInputVisible: Bool = false
    /// Whether the current frame already has text content
    var hasTextAnnotation: Bool = false
    /// Callback to toggle text input visibility
    var onTextInputToggle: (() -> Void)? = nil
    /// Capture marker positions (timestamps) for yellow diamonds on the seek bar
    var captureMarkerPositions: [Double] = []
    /// Whether capture gallery mode is active
    var isCaptureMode: Bool = false
    /// Callback to toggle capture gallery mode
    var onCapturesModeToggle: (() -> Void)? = nil

    @State private var isScrubbing = false
    @State private var sliderValue: Double = 0
    @State private var localIsPlaying = false
    @State private var previewGenerator = ScrubPreviewGenerator()
    @State private var sliderFrame: CGRect = .zero
    @State private var pollingTask: Task<Void, Never>?
    @State private var preloadTask: Task<Void, Never>?
    @State private var previousVideoId: String?
    @State private var cachedRanges: [ClosedRange<Double>] = []
    @State private var allFramesCached = false
    @State private var serverCachedTimes: [Double] = []
    @State private var scrubLevel: ScrubLevel = .normal
    @State private var precisionVerticalOffset: CGFloat = 0
    @State private var scrubAnchorTime: Double = 0

    /// Cached ranges adjusted for display - extends to full duration when all frames are cached
    private var displayCachedRanges: [ClosedRange<Double>] {
        guard !cachedRanges.isEmpty else { return [] }

        // When all frames are cached, extend the last range to cover the full video duration
        // This ensures the orange bar fills 100% of the slider when generation is complete
        if allFramesCached && duration > 0 {
            var adjusted = cachedRanges
            if let lastRange = adjusted.last {
                adjusted.removeLast()
                // Extend to duration (or slightly beyond to ensure visual coverage)
                adjusted.append(lastRange.lowerBound...max(lastRange.upperBound, duration))
            }
            return adjusted
        }

        return cachedRanges
    }

    private var isPlaying: Bool {
        playerState?.isPlaying ?? localIsPlaying
    }

    private var currentTime: Double {
        playerState?.currentTime ?? 0
    }

    private var duration: Double {
        playerState?.duration ?? 0
    }

    private var isPinned: Bool {
        controlsState?.isPinned ?? false
    }

    private var thumbColor: Color {
        allFramesCached ? .green : .red
    }

    /// Calculated thumb center X position in the coordinate space
    private var thumbCenterX: CGFloat {
        let progress = sliderValue / max(duration, 1)
        return sliderFrame.minX + CGFloat(progress) * sliderFrame.width
    }

    /// Calculated thumb center Y position in the coordinate space
    private var thumbCenterY: CGFloat {
        if scrubLevel != .normal {
            // precisionVerticalOffset is negative (finger moved up), moves preview upward
            return sliderFrame.midY + precisionVerticalOffset
        }
        return sliderFrame.midY
    }

    /// Editing range extended to include the live slider position (updates during scrub)
    private var computedEditingRange: ClosedRange<Double>? {
        guard let editing = editingRange else { return nil }
        let current = sliderValue
        let lo = min(editing.lowerBound, current)
        let hi = max(editing.upperBound, current)
        guard hi - lo > 0.01 else { return editing }
        return lo...hi
    }

    /// Pending range computed from pendingStart and the live slider value (updates during drag)
    private var computedPendingRange: ClosedRange<Double>? {
        guard let start = pendingStart else { return nil }
        let current = sliderValue
        let lo = min(start, current)
        let hi = max(start, current)
        guard hi - lo > 0.01 else { return nil }
        return lo...hi
    }

    /// Video frame rate for frame-by-frame scrubbing
    private var videoFrameRate: Double {
        Double(playerState?.videoFrameRate ?? 24.0)
    }

    /// Visible time range for the ruler at the current scrub level
    private var rulerVisibleRange: Double {
        switch scrubLevel {
        case .normal:
            return 0
        case .precision:
            return duration / 10.0
        case .frameByFrame:
            // 4 pixels per frame, so visible range = (sliderWidth / 4) frames in seconds
            return Double(sliderFrame.width) / 4.0 * (1.0 / videoFrameRate)
        }
    }

    var body: some View {
        VStack(spacing: isCompact ? 2 : 4) {
            // Transport controls row
            HStack(spacing: isCompact ? 8 : 16) {
                playPauseButton
                seekSlider
                if !isCompact {
                    timeDisplay
                }
                annotationButton
                toiButton
                capturesButton
                pinButton
            }

            // Filename row underneath (if provided) - hidden in compact mode
            if !isCompact, let filename = filename {
                Text(filename)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Source name row underneath filename (if provided) - hidden in compact mode
            if !isCompact, let sourceName = sourceName {
                Text(sourceName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .onChange(of: currentTime) { _, newTime in
            if !isScrubbing {
                sliderValue = newTime
            }
        }
        .onChange(of: sliderValue) { _, newValue in
            if isScrubbing {
                triggerPreviewGeneration(at: newValue)
                updatePreviewState()
            }
        }
        .onChange(of: previewGenerator.currentPreviewImage) { _, _ in
            // Update preview when image becomes available (async generation complete)
            updatePreviewState()
        }
        .onAppear {
            sliderValue = currentTime
            startScrubFrameTracking()
        }
        .onDisappear {
            stopPollingAndGeneration()
        }
        .onChange(of: playerState?.videoFileId) { oldValue, newValue in
            if oldValue != newValue {
                // Video changed - stop server generation for old video
                stopPollingAndGeneration(for: oldValue, stopServerGeneration: true)
            }
            startScrubFrameTracking()
        }
    }

    private func updatePreviewState() {
        // Only update if actively scrubbing and we have an actual image
        // Don't show empty preview - wait for frame to be ready
        guard isScrubbing, let previewImage = previewGenerator.currentPreviewImage else { return }

        scrubPreviewState = ScrubPreviewState(
            previewImage: previewImage,
            thumbCenterX: thumbCenterX,
            thumbCenterY: thumbCenterY,
            scrubLevel: scrubLevel,
            rulerAnchorTime: scrubAnchorTime,
            rulerCurrentTime: sliderValue,
            rulerVisibleRange: rulerVisibleRange,
            fingerY: scrubLevel != .normal ? sliderFrame.midY + precisionVerticalOffset : sliderFrame.midY,
            frameRate: videoFrameRate
        )
    }

    private var playPauseButton: some View {
        Button(action: togglePlayback) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(isCompact ? .body : .title2)
        }
        .frame(minWidth: isCompact ? 32 : 44, minHeight: isCompact ? 32 : 44)
    }

    private var seekSlider: some View {
        CustomSeekSlider(
            value: $sliderValue,
            range: 0...max(duration, 1),
            thumbColor: thumbColor,
            cachedRanges: displayCachedRanges,
            timeRanges: timeRanges,
            isToIMode: isToIMode,
            captureMarkerPositions: captureMarkerPositions,
            pendingRange: computedPendingRange,
            editingRange: computedEditingRange,
            onScrubStart: {
                handleScrubStart()
            },
            onScrubbing: { newValue in
                handleScrubbing(newValue)
            },
            onScrubEnd: { finalValue, level in
                handleScrubEnd(finalValue, level: level)
            },
            onScrubLevelChanged: { level, yOffset, anchorValue in
                handleScrubLevelChanged(level: level, yOffset: yOffset, anchorValue: anchorValue)
            },
            frameDuration: 1.0 / videoFrameRate
        )
        .disabled(playerState == nil)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        sliderFrame = geometry.frame(in: .named(previewCoordinateSpace))
                    }
                    .onChange(of: geometry.frame(in: .named(previewCoordinateSpace))) { _, newFrame in
                        sliderFrame = newFrame
                    }
            }
        )
    }

    private var timeDisplay: some View {
        Text("\(formatTime(currentTime)) / \(formatTime(duration))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    @ViewBuilder
    private var annotationButton: some View {
        if onAnnotationModeToggle != nil {
            Button(action: { onAnnotationModeToggle?() }) {
                Image(systemName: "pencil.tip.crop.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isAnnotationMode ? .black : .white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(isAnnotationMode ? Color.orange : Color.white.opacity(0.15)))
            }
            .buttonStyle(.plain)
            // Float the text-annotation button directly below the pencil button
            // instead of inline, so it doesn't widen the transport row (which
            // would shrink the seek bar) when annotation mode is active.
            .overlay(alignment: .bottom) {
                textAnnotationButton
                    .offset(y: 38)
            }
        }
    }

    @ViewBuilder
    private var textAnnotationButton: some View {
        if isAnnotationMode && onTextInputToggle != nil {
            let isActive = isTextInputVisible || hasTextAnnotation
            Button(action: { onTextInputToggle?() }) {
                Image(systemName: "textformat")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isActive ? .black : .white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(isActive ? Color.orange : Color.white.opacity(0.15)))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var capturesButton: some View {
        if onCapturesModeToggle != nil {
            Button(action: { onCapturesModeToggle?() }) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isCaptureMode ? .black : .white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(isCaptureMode ? Color.yellow : Color.white.opacity(0.15)))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var toiButton: some View {
        if onToIModeToggle != nil {
            Button(action: { onToIModeToggle?() }) {
                Image(systemName: "timeline.selection")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isToIMode ? .black : .white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(isToIMode ? Color.teal : Color.white.opacity(0.15)))
            }
            .buttonStyle(.plain)
        }
    }

    private var pinButton: some View {
        Button(action: { controlsState?.togglePin() }) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(isCompact ? .body : .title2)
                .foregroundStyle(isPinned ? .primary : .secondary)
        }
        .frame(minWidth: isCompact ? 32 : 44, minHeight: isCompact ? 32 : 44)
        .disabled(controlsState == nil)
    }

    // MARK: - Actions

    private func togglePlayback() {
        if let playerState = playerState {
            if playerState.wantsToPlay {
                playerState.pause()
            } else {
                playerState.play()
            }
        } else {
            localIsPlaying.toggle()
        }
        controlsState?.resetTimer()
    }

    private func handleScrubStart() {
        isScrubbing = true
        onScrubStart?()

        // Prevent controls from auto-hiding while finger is down
        controlsState?.suspendAutoHide()

        // Pause ALL background generation to prioritize on-demand frame fetching
        if let serverURL = serverURL {
            Task {
                await previewGenerator.pauseAllBackgroundGeneration(serverURL: serverURL)
            }
        }

        // Configure server frame fetching if server URL is available
        if let serverURL = serverURL, let fileId = playerState?.videoFileId {
            previewGenerator.configureServerFrameFetching(serverURL: serverURL, videoId: fileId)

            // Record which video this stream's frames belong to
            if let videoURL = playerState?.videoURL {
                PreviewFrameCache.shared.registerVideo(id: fileId, url: videoURL)
            }

            // Trigger preloading of frames around current position
            if let videoURL = playerState?.videoURL {
                previewGenerator.preloadFramesAround(time: sliderValue, for: videoURL)
            }
        }

        // Local fallback when the server cannot provide a frame
        if let asset = playerState?.currentAsset {
            previewGenerator.configure(with: asset)
            AppLogger.video.debug("Using fallback AVAssetImageGenerator for preview")
        }

        // Trigger initial preview generation immediately (no debounce for first frame)
        triggerPreviewGeneration(at: sliderValue, immediate: true)
        updatePreviewState()
    }

    private func handleScrubbing(_ newValue: Double) {
        sliderValue = newValue
    }

    private func handleScrubEnd(_ finalValue: Double, level: ScrubLevel) {
        // Cleanup preview generation
        previewGenerator.cancelPendingGeneration()

        // IMPORTANT: Seek BEFORE setting isScrubbing = false
        // This ensures currentTime is updated to finalValue before onChange can fire
        // Otherwise, stale currentTime from time observer causes backward jump
        playerState?.seek(to: finalValue, tolerance: seekTolerance(for: level))

        // Now safe to allow time observer updates - currentTime is already at target
        isScrubbing = false
        scrubLevel = .normal
        precisionVerticalOffset = 0
        scrubAnchorTime = 0

        // Resume ALL background generation (server tracks which videos were paused)
        if let serverURL = serverURL {
            Task {
                await previewGenerator.resumeAllBackgroundGeneration(serverURL: serverURL)
            }
        }

        // Resume auto-hide now that finger is released
        controlsState?.resumeAutoHide()

        // Notify parent
        onScrubEnd?()
    }

    private func seekTolerance(for level: ScrubLevel) -> Double {
        switch level {
        case .normal:
            return max(0.05, min(0.25, 2.0 / videoFrameRate))
        case .precision:
            return 1.0 / videoFrameRate
        case .frameByFrame:
            return 0
        }
    }

    private func handleScrubLevelChanged(level: ScrubLevel, yOffset: CGFloat, anchorValue: Double) {
        let previousLevel = scrubLevel
        scrubLevel = level
        precisionVerticalOffset = yOffset
        if level != .normal {
            scrubAnchorTime = anchorValue
        }

        if isScrubbing {
            updatePreviewState()

            // When transitioning between levels, trigger
            // a fresh frame generation at the current position
            if previousLevel != level {
                triggerPreviewGeneration(at: sliderValue, immediate: true)
            }
        }
    }

    private func triggerPreviewGeneration(at time: Double, immediate: Bool = false) {
        guard let videoURL = playerState?.videoURL else { return }

        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        previewGenerator.generatePreview(at: cmTime, for: videoURL, immediate: immediate, precisionMode: scrubLevel != .normal)
    }

    private func formatTime(_ timeInSeconds: Double) -> String {
        guard timeInSeconds.isFinite && timeInSeconds >= 0 else {
            return "0:00"
        }

        let totalSeconds = Int(timeInSeconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    /// Sets up server frame fetching and cache-range polling for the
    /// current video.
    private func startScrubFrameTracking() {
        guard let fileId = playerState?.videoFileId,
              let serverURL = serverURL else {
            return
        }

        // Configure server frame fetching for on-demand frame generation
        previewGenerator.configureServerFrameFetching(serverURL: serverURL, videoId: fileId)

        // Record which video this stream's frames belong to
        if let videoURL = playerState?.videoURL {
            PreviewFrameCache.shared.registerVideo(id: fileId, url: videoURL)
        }

        // Start background generation and polling
        startBackgroundGenerationAndPolling(videoId: fileId, serverURL: serverURL)
    }

    private func startBackgroundGenerationAndPolling(videoId: String, serverURL: URL) {
        previousVideoId = videoId
        cachedRanges = PreviewFrameCache.shared.cachedRanges(forVideoId: videoId)
        allFramesCached = false

        Task {
            await previewGenerator.startBackgroundGeneration(serverURL: serverURL, videoId: videoId)
        }

        pollingTask?.cancel()
        pollingTask = Task { @MainActor in
            await fetchCachedTimesFromServer(videoId: videoId, serverURL: serverURL)

            while !Task.isCancelled && !allFramesCached {
                try? await Task.sleep(nanoseconds: 3_000_000_000)

                guard !Task.isCancelled else { break }

                await fetchCachedTimesFromServer(videoId: videoId, serverURL: serverURL)
            }
        }
    }

    private func fetchCachedTimesFromServer(videoId: String, serverURL: URL) async {
        guard let url = VideoURLBuilder.buildScrubCachedTimesURL(from: serverURL, videoId: videoId) else {
            AppLogger.video.warning("Failed to build cached-times URL")
            return
        }

        do {
            let (data, response) = try await ServerSessionManager.shared.urlSession.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let times = json["times"] as? [Double] {
                PreviewFrameCache.shared.updateFromServerTimes(videoId: videoId, times: times)
                // The poll may finish after the tile switched videos
                guard playerState?.videoFileId == videoId else { return }
                cachedRanges = PreviewFrameCache.shared.cachedRanges(forVideoId: videoId)
                serverCachedTimes = times

                if let cachedCount = json["cachedCount"] as? Int,
                   let totalFrames = json["totalFrames"] as? Int,
                   totalFrames > 0,
                   cachedCount >= totalFrames {
                    allFramesCached = true
                    pollingTask?.cancel()
                    pollingTask = nil
                    AppLogger.video.info("All \(totalFrames) scrub frames cached for \(videoId), stopping polling")

                    // Preload all server frames to iPad NSCache
                    startPreloadingFrames(times: times, videoId: videoId, serverURL: serverURL)
                }
            }
        } catch {
            AppLogger.video.debug("Failed to fetch cached times: \(error.localizedDescription)")
        }
    }

    private func startPreloadingFrames(times: [Double], videoId: String, serverURL: URL) {
        guard let videoURL = playerState?.videoURL else { return }

        preloadTask?.cancel()
        preloadTask = Task {
            AppLogger.video.info("Starting preload of \(times.count) frames for \(videoId)")
            let loaded = await PreviewFrameCache.shared.preloadAllFrames(
                times: times,
                videoURL: videoURL,
                serverURL: serverURL,
                videoId: videoId
            )
            AppLogger.video.info("Preload complete: \(loaded)/\(times.count) frames loaded to NSCache")
        }
    }

    private func stopPollingAndGeneration(for videoId: String? = nil, stopServerGeneration: Bool = false) {
        pollingTask?.cancel()
        pollingTask = nil
        preloadTask?.cancel()
        preloadTask = nil

        // Only stop server-side generation when explicitly requested (e.g., video changed)
        // Do NOT stop when controls simply hide - background generation should continue
        if stopServerGeneration {
            let idToStop = videoId ?? previousVideoId
            guard let fileId = idToStop, let serverURL = serverURL else { return }

            Task {
                await previewGenerator.stopBackgroundGeneration(serverURL: serverURL, videoId: fileId)
            }
        }

        previousVideoId = nil
        serverCachedTimes = []
    }
}

#Preview("Without State (Placeholder)") {
    TransportControlsView(
        scrubPreviewState: .constant(nil)
    )
    .padding()
    .background(.ultraThinMaterial)
}

#Preview("With State") {
    let playerState = VideoPlayerState()
    let controlsState = VideoControlsState()
    return TransportControlsView(
        playerState: playerState,
        controlsState: controlsState,
        scrubPreviewState: .constant(nil)
    )
    .padding()
    .background(.ultraThinMaterial)
}

#Preview("Pinned") {
    let playerState = VideoPlayerState()
    let controlsState = VideoControlsState()
    controlsState.show()
    return TransportControlsView(
        playerState: playerState,
        controlsState: controlsState,
        scrubPreviewState: .constant(nil)
    )
    .padding()
    .background(.ultraThinMaterial)
    .onAppear {
        controlsState.togglePin()
    }
}

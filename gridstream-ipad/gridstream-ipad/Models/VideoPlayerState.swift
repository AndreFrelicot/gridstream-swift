//
//  VideoPlayerState.swift
//  gridstream-ipad
//

import AVFoundation
import Combine
import Foundation
import OSLog
import UIKit

@Observable
final class VideoPlayerState {
    typealias PlaybackStatsReporter = (_ fileId: String, _ incrementPlayCount: Bool, _ addViewTime: Int) async throws -> Void

    enum PlaybackStatus: Equatable {
        case preparing
        case seeking
        case buffering
        case ended
        case interrupted
    }

    /// Identifies the most recent explicit seek request. Views observe this to
    /// react to deliberate navigation (scrubbing, frame stepping, jumps) without
    /// confusing it with the periodic time observer's sub-frame drift.
    struct SeekMarker: Equatable {
        let id: UUID
        let targetTime: Double
    }

    /// A value read from the player a view currently shows, with that
    /// player's identity, so the view can tell a change of the player's own
    /// state from a switch to another player (whose time belongs to another
    /// video, and whose last seek was handled long ago).
    struct Reading<Value: Equatable>: Equatable {
        let playerID: UUID?
        let value: Value?
    }

    let id: UUID = UUID()

    private(set) var lastSeek: SeekMarker?
    private(set) var isPlaying = false
    private(set) var wantsToPlay = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isBuffering = false
    private(set) var playbackStatus: PlaybackStatus?
    private(set) var error: Error?
    private(set) var volume: Float = 1.0

    /// The mute control's state. Stored rather than read back from the AVPlayer
    /// so it survives a video change — which builds a brand new AVPlayer — and
    /// so nothing else can clear it: it is the user's intent, and it wins.
    private(set) var isMuted = false

    /// Audio silenced by something other than the user: solo / superSolo, or a
    /// pre-loaded adjacent player kept quiet until it becomes current. Layered
    /// on top of `isMuted`, never replacing it.
    private(set) var isAudioSuppressed = false
    private(set) var videoPresentationSize = CGSize(width: 1920, height: 1080)

    /// The tile index this player is assigned to, used for stereo panning.
    /// nil means no panning (e.g., fullscreen video).
    var tileIndex: Int?

    /// Current presentation context, included in persisted playback diagnostics.
    var diagnosticDisplayContext = "tile"

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    private(set) var player: AVPlayer?

    /// The view this player's picture is drawn in, made when a view first
    /// shows the player. There is one for the player's whole life and it
    /// follows the current AVPlayer: the views showing the player (grid tile,
    /// fullscreen, PiP) pass it on, see `PlayerSurfaceHostView`.
    var surface: PlayerLayerView {
        if let loadedSurface { return loadedSurface }
        let surface = PlayerLayerView()
        surface.playerLayer.player = player
        loadedSurface = surface
        return surface
    }
    @ObservationIgnored private var loadedSurface: PlayerLayerView?

    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var playbackLikelyObservation: NSKeyValueObservation?
    private var playbackBufferEmptyObservation: NSKeyValueObservation?
    private var durationObservation: NSKeyValueObservation?
    private var currentURL: URL?

    // In-flight Tasks for async metadata/audio mix loading. Stored so a
    // rapid second `setupPlayer` can cancel the prior load before the new
    // one starts, preventing late writes onto an orphaned player item.
    private var assetLoadTask: Task<Void, Never>?
    private var audioMixTask: Task<Void, Never>?

    // Audio processing
    private var audioMix: AVAudioMix?

    // Lifecycle state
    private var wasPlayingBeforeBackground = false
    @ObservationIgnored private let activateAudioSession: () throws -> Void
    private var isAppInactive = false
    /// Another app (call, Siri, alarm) holds the audio session. Playback is
    /// held like when the app is inactive, and resumes only if the system says
    /// it should.
    private(set) var isAudioInterrupted = false
    private var isPlaybackSuspended: Bool { isAppInactive || isAudioInterrupted }
    private var lifecycleCancellables = Set<AnyCancellable>()
    private var itemCancellables = Set<AnyCancellable>()

    // Seek state - prevents time observer from overwriting currentTime during seek
    private(set) var isSeeking = false
    private var seekRequestID: UUID?
    private var isWaitingForBufferRecovery = false
    private var didAttemptUnexpectedPauseRecovery = false

    // Playback stats. Reports are handed to the app-wide queue, which alone
    // stores, sends and retries them.
    @ObservationIgnored private var playbackStatsReporter: PlaybackStatsReporter?
    /// Called when the item plays to its end. Set by `SharedPlayerPool`,
    /// which routes it to the tile the player currently belongs to.
    @ObservationIgnored var onPlaybackEnded: (() -> Void)?
    @ObservationIgnored private let statsQueue: PlaybackStatsQueue

    private var lastStatsPlaybackTime: Double?
    private var unreportedViewTime: Double = 0
    private var sessionPlaybackTime: Double = 0
    private var didIncrementPlayCountForCurrentItem = false
    private let playCountThreshold: Double = 60
    private let viewTimeFlushInterval: Double = 60
    private var shouldAutoplayCurrentItem = true
    private var cachedVideoFrameRate: Float = 24.0

    // MARK: - Asset Access for Preview Frame Generation

    /// The current AVAsset from the player item, used for preview frame generation.
    /// Returns nil when player is not ready or not configured.
    var currentAsset: AVAsset? {
        return playerItem?.asset
    }

    /// The current video URL, used for cache key generation.
    /// Returns nil when no video is loaded.
    var videoURL: URL? {
        return currentURL
    }

    /// The video frame rate (fps), used for frame-by-frame scrubbing.
    /// Defaults to 24.0 if the track info is unavailable.
    var videoFrameRate: Float {
        cachedVideoFrameRate
    }

    /// The player's time right now. `currentTime` is refreshed every half
    /// second (and when playback starts or stops), so it can lag behind; while
    /// a seek is in flight it already holds the seek target, which is used.
    var exactCurrentTime: Double {
        guard !isSeeking, let seconds = player?.currentTime().seconds, seconds.isFinite else {
            return currentTime
        }
        return seconds
    }

    /// The fileId of the current video, used for scrub video lookup.
    private(set) var videoFileId: String?

    // MARK: - Frame Capture for History Navigation

    /// Captures the current frame from the video for use in transition animations.
    /// Uses AVAssetImageGenerator for accurate frame extraction at current playback position.
    /// - Returns: A CGImage of the current frame, or nil if capture fails
    func captureCurrentFrame() async -> CGImage? {
        guard let asset = currentAsset else {
            AppLogger.video.warning("Cannot capture frame: no asset available")
            return nil
        }

        // Handed to its own async API below and not touched while it runs;
        // the compiler can't tell, as it is made from the player's asset.
        nonisolated(unsafe) let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360) // Larger than preview for better quality
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

        let requestedTime = CMTime(seconds: currentTime, preferredTimescale: 600)

        // Asynchronous generation: the asset is streamed over HTTP, and the
        // synchronous copyCGImage would freeze every tile while it fetches.
        do {
            let cgImage = try await generator.image(at: requestedTime).image
            AppLogger.video.debug("Captured frame at \(requestedTime.seconds) seconds")
            return cgImage
        } catch {
            AppLogger.video.warning("Failed to capture frame: \(error.localizedDescription)")
            return nil
        }
    }

    init(
        statsQueue: PlaybackStatsQueue = .shared,
        activateAudioSession: @escaping () throws -> Void = { try AVAudioSession.sharedInstance().setActive(true) }
    ) {
        self.statsQueue = statsQueue
        self.activateAudioSession = activateAudioSession
        configureAudioSession()
        setupLifecycleObservers()
    }

    func configurePlaybackStatsReporter(_ reporter: PlaybackStatsReporter?) {
        playbackStatsReporter = reporter
        guard let reporter else { return }
        let queue = statsQueue
        Task { await queue.setReporter(reporter) }
    }

    func releasePlayerResources() {
        cleanupPlayer()
    }

    func setupPlayer(url: URL, fileId: String? = nil, autoplay: Bool = true) {
        AppLogger.video.info("Setting up player with URL: \(VideoURLBuilder.removingToken(from: url).absoluteString)")

        cleanupPlayer()
        resetPlaybackStatsState()

        currentURL = url
        videoFileId = fileId
        shouldAutoplayCurrentItem = autoplay
        wantsToPlay = autoplay
        playbackStatus = .preparing
        isBuffering = true
        resetVideoTrackMetadata()

        // Demo streams play the pack's local file; `currentURL` keeps the
        // demo URL, which identifies the server.
        let asset = AVURLAsset(url: DemoMode.playableURL(for: url))
        let item = AVPlayerItem(asset: asset)
        // Keep forward buffer small to reduce A/V drift when multiple players
        // compete for decode resources. Default (~10s) lets audio race ahead of video.
        item.preferredForwardBufferDuration = 2.0
        playerItem = item
        loadVideoTrackMetadata(from: asset)

        // Attach audio processing tap for normalization
        attachAudioProcessingTap(to: item)

        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.volume = volume
        // Disable automatic stall waiting — prefer continuous playback with smaller
        // buffer over buffering pauses that cause persistent A/V desync.
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        player = newPlayer
        loadedSurface?.playerLayer.player = newPlayer
        // A new AVPlayer starts unmuted; re-assert the state the user chose for
        // this tile so a video change does not silently restore the sound.
        applyMuteState()

        setupObservers(player: newPlayer, item: item)

        recordDiagnostic(
            name: "player_setup",
            message: "autoplay=\(autoplay) buffer=\(item.preferredForwardBufferDuration)s"
        )
        AppLogger.video.debug("Player setup complete")
    }

    func play() {
        guard let player = player else {
            AppLogger.video.warning("Attempted to play without player setup")
            return
        }

        // A suspension can deliver .began without .ended. An explicit Play
        // retries activation; a still-active call makes activation fail.
        if !isAppInactive {
            _ = reactivateAudioSession()
        }
        wantsToPlay = true
        shouldAutoplayCurrentItem = false
        didAttemptUnexpectedPauseRecovery = false
        recordDiagnostic(name: "play_requested")

        if playbackStatus == .ended || isAtPlaybackEnd(player: player) {
            seek(to: 0, tolerance: 0)
            return
        }

        startPlayback(player: player)
    }

    func pause() {
        guard let player = player else {
            AppLogger.video.warning("Attempted to pause without player setup")
            return
        }

        recordCurrentPlaybackStatsProgress(player: player)
        flushPlaybackStats()
        recordDiagnostic(name: "pause_requested")
        wantsToPlay = false
        shouldAutoplayCurrentItem = false
        isWaitingForBufferRecovery = false
        didAttemptUnexpectedPauseRecovery = false
        player.pause()
        isPlaying = false
        isBuffering = false
        playbackStatus = nil
        AppLogger.video.debug("Playback paused")
    }

    /// Sets the volume level (0.0 to 1.0)
    /// Volume is stored and only applied to player if audible.
    /// While silenced, volume changes are saved but audio stays off.
    func setVolume(_ level: Float) {
        let clampedLevel = max(0.0, min(1.0, level))
        volume = clampedLevel
        // Only apply volume to player if audible
        // This prevents blur/focus volume changes from overriding mute state
        if !isSilenced {
            player?.volume = clampedLevel
        }
        AppLogger.video.debug("Volume set to \(clampedLevel), muted: \(self.isMuted)")
    }

    /// Whether any layer is currently keeping this player quiet.
    var isSilenced: Bool {
        isMuted || isAudioSuppressed
    }

    /// Sets the user's mute intent. Only the mute control should call this.
    func setMuted(_ muted: Bool) {
        isMuted = muted
        applyMuteState()
        AppLogger.video.debug("Player mute set to \(muted)")
    }

    /// Silences the player without touching the user's mute intent — used by
    /// solo / superSolo and by pre-loaded players. Clearing it restores sound
    /// only if the user has not muted this player.
    func setAudioSuppressed(_ suppressed: Bool) {
        isAudioSuppressed = suppressed
        applyMuteState()
    }

    private func applyMuteState() {
        guard let player else { return }
        player.isMuted = isSilenced
        if !isSilenced {
            // Restore the stored volume level when the player becomes audible
            player.volume = volume
        }
    }

    /// Waits (up to `timeout`) for the loaded item to become ready, so a seek
    /// issued right after `setupPlayer` lands on a known duration. Returns
    /// false if the task was cancelled or the player loaded another item in
    /// the meantime: the caller's seek no longer applies.
    func waitUntilReadyToPlay(timeout: Double = 5) async -> Bool {
        guard let item = playerItem else { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while item.status == .unknown, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled, playerItem === item else { return false }
        }
        return !Task.isCancelled && playerItem === item
    }

    func seek(to time: Double, tolerance: Double = 0) {
        guard let player = player, let item = playerItem else {
            AppLogger.video.warning("Attempted to seek without player setup")
            return
        }

        let targetTime = Self.resolvedSeekTarget(
            requestedTime: time,
            duration: duration,
            frameRate: Double(videoFrameRate),
            wantsToPlay: wantsToPlay
        )
        let requestID = UUID()

        // Set seeking state to prevent time observer from overwriting currentTime
        // This prevents the "backward jump" when scrubbing while video is playing
        isSeeking = true
        seekRequestID = requestID
        lastSeek = SeekMarker(id: requestID, targetTime: targetTime)
        isWaitingForBufferRecovery = false
        playbackStatus = .seeking
        isBuffering = true
        recordDiagnostic(
            name: "seek_started",
            message: "requested=\(time) target=\(targetTime) tolerance=\(max(0, tolerance))"
        )

        // Update currentTime immediately so UI shows the seek target
        currentTime = targetTime

        let cmTime = CMTime(seconds: targetTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        let toleranceTime = CMTime(seconds: max(0, tolerance), preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        item.cancelPendingSeeks()
        player.seek(to: cmTime, toleranceBefore: toleranceTime, toleranceAfter: toleranceTime) { [weak self] completed in
            DispatchQueue.main.async {
                guard let self = self else { return }

                // Only clear seeking state if this is still the latest seek.
                // When seeks overlap, earlier completions must not unlock the guard
                // or the time observer will overwrite currentTime with a stale position.
                guard self.seekRequestID == requestID else { return }

                self.isSeeking = false
                self.seekRequestID = nil

                if completed {
                    self.recordDiagnostic(
                        name: "seek_completed",
                        message: "target=\(targetTime)"
                    )
                    AppLogger.video.debug("Seek completed to \(targetTime) seconds")
                    if self.wantsToPlay && !self.isPlaybackSuspended {
                        if item.isPlaybackBufferEmpty {
                            self.markWaitingForBufferRecovery()
                        } else {
                            self.startPlayback(player: player)
                        }
                    } else if self.duration > 0, targetTime >= self.duration {
                        self.playbackStatus = .ended
                        self.isBuffering = false
                    } else {
                        self.playbackStatus = nil
                        self.isBuffering = false
                    }
                } else {
                    self.recordDiagnostic(
                        level: .warning,
                        name: "seek_interrupted",
                        message: "target=\(targetTime)"
                    )
                    AppLogger.video.warning("Seek was interrupted")
                    self.isBuffering = false
                    self.playbackStatus = self.wantsToPlay ? .interrupted : nil
                }
            }
        }
    }

    func retry() {
        guard let url = currentURL else {
            AppLogger.video.warning("No URL available for retry")
            return
        }
        let fileId = videoFileId

        AppLogger.video.info("Retrying playback")
        recordDiagnostic(name: "retry_requested")
        error = nil
        setupPlayer(url: url, fileId: fileId)
    }

    // MARK: - Audio Processing

    /// Attaches the audio processing tap for normalization to the player item.
    /// If tileIndex is set, the tap will apply stereo panning based on tile position.
    private func attachAudioProcessingTap(to item: AVPlayerItem) {
        audioMixTask = Task { @MainActor [weak self, item] in
            guard let self else { return }
            let mix = await AudioTapManager.createAudioMix(for: item, tileIndex: self.tileIndex)
            // Bail out if the in-flight load has been superseded by a new setup
            // (player item replaced, or task cancelled).
            guard !Task.isCancelled,
                  self.playerItem === item,
                  let mix else {
                return
            }

            self.audioMix = mix
            item.audioMix = mix
            AppLogger.video.debug("Audio processing tap attached to player item (tileIndex: \(String(describing: self.tileIndex)))")
        }
    }

    private func resetVideoTrackMetadata() {
        cachedVideoFrameRate = 24.0
        videoPresentationSize = CGSize(width: 1920, height: 1080)
    }

    private func loadVideoTrackMetadata(from asset: AVAsset) {
        assetLoadTask = Task { @MainActor [weak self, asset] in
            do {
                guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                    return
                }
                try Task.checkCancellation()

                let frameRate = try await videoTrack.load(.nominalFrameRate)
                try Task.checkCancellation()
                let naturalSize = try await videoTrack.load(.naturalSize)
                try Task.checkCancellation()
                let preferredTransform = try await videoTrack.load(.preferredTransform)
                let rotatedSize = naturalSize.applying(preferredTransform)

                guard let self, self.currentAsset === asset else { return }
                self.cachedVideoFrameRate = frameRate > 0 ? frameRate : 24.0
                self.videoPresentationSize = CGSize(
                    width: abs(rotatedSize.width),
                    height: abs(rotatedSize.height)
                )
            } catch is CancellationError {
                // Superseded by a new setupPlayer call — nothing to do.
            } catch {
                AppLogger.video.debug("Unable to load video track metadata: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Lifecycle Management

    private func setupLifecycleObservers() {
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleAppWillResignActive()
            }
            .store(in: &lifecycleCancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleAppDidBecomeActive()
            }
            .store(in: &lifecycleCancellables)

        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let info = notification.userInfo,
                      let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
                let rawOptions = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
                self?.handleAudioInterruption(type, shouldResume: shouldResume)
            }
            .store(in: &lifecycleCancellables)

        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else { return }
                self?.handleAudioRouteChange(reason)
            }
            .store(in: &lifecycleCancellables)

        AppLogger.video.debug("Lifecycle observers configured")
    }

    func handleAppWillResignActive() {
        isAppInactive = true
        wasPlayingBeforeBackground = wantsToPlay
        recordDiagnostic(name: "app_inactive")
        if let player {
            recordCurrentPlaybackStatsProgress(player: player)
        }
        flushPlaybackStats(requireBackgroundTask: true)

        if wantsToPlay {
            player?.pause()
            isPlaying = false
            AppLogger.video.info("Paused playback on background (wasPlaying: true)")
        } else {
            AppLogger.video.debug("App backgrounded (wasPlaying: false)")
        }
    }

    func handleAppDidBecomeActive() {
        isAppInactive = false
        recordDiagnostic(name: "app_active")
        // Interruption end notifications are not guaranteed across suspension.
        // Activation succeeds only when iOS lets us reclaim the audio session.
        if wasPlayingBeforeBackground, wantsToPlay {
            _ = reactivateAudioSession()
        }
        if wasPlayingBeforeBackground, wantsToPlay, !isAudioInterrupted {
            if let player, playerItem?.isPlaybackBufferEmpty == true {
                markWaitingForBufferRecovery()
                player.play()
            } else if let player {
                startPlayback(player: player)
            }
            AppLogger.video.info("Requested playback resume on foreground")
        } else {
            AppLogger.video.debug("App returned to foreground (not resuming - was not playing)")
        }

        wasPlayingBeforeBackground = false
        let queue = statsQueue
        Task { await queue.flush() }
    }

    // MARK: - Audio Session

    /// A call, Siri or another app took the audio session. The system has
    /// already paused the AVPlayer; keep the intent to play but hold playback
    /// until its end, a foreground return or an explicit Play can reactivate it.
    func handleAudioInterruption(_ type: AVAudioSession.InterruptionType, shouldResume: Bool) {
        switch type {
        case .began:
            isAudioInterrupted = true
            recordDiagnostic(name: "audio_interruption_began")
            if wantsToPlay {
                player?.pause()
                isPlaying = false
                isBuffering = false
            }
        case .ended:
            isAudioInterrupted = false
            recordDiagnostic(name: "audio_interruption_ended", message: "shouldResume=\(shouldResume)")
            guard wantsToPlay, let player else { return }
            if shouldResume {
                guard reactivateAudioSession() else { return }
                startPlayback(player: player)
            } else {
                // The system does not want playback back on its own: show the
                // tile as paused rather than stuck waiting.
                pause()
            }
        @unknown default:
            break
        }
    }

    /// Headphones unplugged (or another output went away): pause instead of
    /// carrying on through the speaker, as the system guidelines expect.
    func handleAudioRouteChange(_ reason: AVAudioSession.RouteChangeReason) {
        guard reason == .oldDeviceUnavailable, wantsToPlay, player != nil else { return }
        recordDiagnostic(name: "audio_route_lost")
        pause()
    }

    @discardableResult
    private func reactivateAudioSession() -> Bool {
        do {
            try activateAudioSession()
            isAudioInterrupted = false
            return true
        } catch {
            isAudioInterrupted = true
            recordDiagnostic(level: .warning, name: "audio_reactivation_failed", error: error)
            return false
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try activateAudioSession()
            AppLogger.video.debug("Audio session configured for playback")
        } catch {
            AppLogger.video.error("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - Player Observers

    private func setupObservers(player: AVPlayer, item: AVPlayerItem) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            // Delivered on the main queue, as requested above.
            MainActor.assumeIsolated {
                guard let self = self else { return }

                // Don't update currentTime while seeking - prevents backward jump
                // The seek completion handler will allow updates once seek finishes
                guard !self.isSeeking else { return }

                self.currentTime = time.seconds
                self.recordPlaybackStatsProgress(currentTime: time.seconds, isPlaybackActive: player.rate > 0)
            }
        }

        statusObservation = player.observe(\.status, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                guard self?.player === player else { return }
                switch player.status {
                case .readyToPlay:
                    AppLogger.video.debug("Player ready to play")
                case .failed:
                    self?.error = player.error
                    self?.wantsToPlay = false
                    self?.isBuffering = false
                    self?.playbackStatus = .interrupted
                    self?.recordDiagnostic(
                        level: .error,
                        name: "player_failed",
                        error: player.error
                    )
                    AppLogger.video.error("Player failed: \(player.error?.localizedDescription ?? "Unknown error")")
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }

        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                guard let self, self.player === player else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.isPlaying = true
                    self.isBuffering = false
                    self.isWaitingForBufferRecovery = false
                    self.didAttemptUnexpectedPauseRecovery = false
                    self.playbackStatus = nil
                    self.recordDiagnostic(name: "player_playing")
                case .paused:
                    self.recordDiagnostic(
                        level: self.wantsToPlay && !self.isPlaybackSuspended ? .warning : .info,
                        name: "player_paused"
                    )
                    self.handleUnexpectedPause(player: player, item: item)
                case .waitingToPlayAtSpecifiedRate:
                    self.isPlaying = false
                    if self.wantsToPlay && !self.isPlaybackSuspended {
                        self.isBuffering = true
                        self.playbackStatus = self.isSeeking ? .seeking : .buffering
                    }
                    self.recordDiagnostic(
                        level: .warning,
                        name: "player_waiting",
                        message: player.reasonForWaitingToPlay?.rawValue
                    )
                @unknown default:
                    break
                }
            }
        }

        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard self?.playerItem === item else { return }
                switch item.status {
                case .readyToPlay:
                    AppLogger.video.debug("Item ready to play")
                    // Don't autoplay until duration is known. The duration KVO
                    // observation below will retry once the item reports a
                    // finite duration; that prevents the first time observer
                    // from running with duration == 0 and confusing the
                    // playback-stats predicate.
                    self?.maybeAutoplay()
                    if self?.wantsToPlay != true {
                        self?.isBuffering = false
                        self?.playbackStatus = nil
                    }
                case .failed:
                    self?.error = item.error
                    self?.wantsToPlay = false
                    self?.isBuffering = false
                    self?.playbackStatus = .interrupted
                    self?.recordDiagnostic(
                        level: .error,
                        name: "item_failed",
                        error: item.error
                    )
                    AppLogger.video.error("Item failed: \(item.error?.localizedDescription ?? "Unknown error")")
                case .unknown:
                    self?.isBuffering = true
                    self?.playbackStatus = .preparing
                @unknown default:
                    break
                }
            }
        }

        durationObservation = item.observe(\.duration, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                let durationSeconds = item.duration.seconds
                if durationSeconds.isFinite && durationSeconds > 0 {
                    self?.duration = durationSeconds
                    AppLogger.video.debug("Duration updated: \(durationSeconds) seconds")
                    // Retry autoplay now that we know the duration.
                    self?.maybeAutoplay()
                }
            }
        }

        playbackLikelyObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                if item.isPlaybackLikelyToKeepUp {
                    self?.resumeAfterBufferRecoveryIfNeeded(player: player, item: item)
                }
            }
        }

        playbackBufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, self.wantsToPlay, !self.isPlaybackSuspended else { return }
                if item.isPlaybackBufferEmpty {
                    self.markWaitingForBufferRecovery()
                } else {
                    self.resumeAfterBufferRecoveryIfNeeded(player: player, item: item)
                }
            }
        }

        NotificationCenter.default.publisher(for: AVPlayerItem.playbackStalledNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.wantsToPlay else { return }
                self.markWaitingForBufferRecovery()
                self.recordDiagnostic(level: .warning, name: "playback_stalled")
                AppLogger.video.warning("Playback stalled while waiting for media data")
            }
            .store(in: &itemCancellables)

        NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handlePlaybackEnded()
            }
            .store(in: &itemCancellables)

        NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self else { return }
                self.error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                self.wantsToPlay = false
                self.isPlaying = false
                self.isBuffering = false
                self.playbackStatus = .interrupted
                self.recordDiagnostic(
                    level: .error,
                    name: "playback_failed",
                    error: self.error
                )
                AppLogger.video.error("Playback failed before reaching the end")
            }
            .store(in: &itemCancellables)

        NotificationCenter.default.publisher(for: AVPlayerItem.newAccessLogEntryNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] _ in
                guard let self, let accessEvent = item?.accessLog()?.events.last else { return }
                self.recordDiagnostic(name: "access_log", accessEvent: accessEvent)
            }
            .store(in: &itemCancellables)

        NotificationCenter.default.publisher(for: AVPlayerItem.newErrorLogEntryNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] _ in
                guard let self, let errorEvent = item?.errorLog()?.events.last else { return }
                let error = NSError(
                    domain: errorEvent.errorDomain,
                    code: errorEvent.errorStatusCode,
                    userInfo: [NSLocalizedDescriptionKey: errorEvent.errorComment ?? "AVPlayer item error log entry"]
                )
                self.recordDiagnostic(
                    level: .error,
                    name: "error_log",
                    message: errorEvent.serverAddress,
                    error: error
                )
            }
            .store(in: &itemCancellables)
    }

    private func startPlayback(player: AVPlayer) {
        guard wantsToPlay, !isPlaybackSuspended else { return }

        player.play()
        isPlaying = true
        isBuffering = false
        isWaitingForBufferRecovery = false
        playbackStatus = nil
        AppLogger.video.debug("Playback started")
    }

    private func handleUnexpectedPause(player: AVPlayer, item: AVPlayerItem) {
        isPlaying = false

        guard wantsToPlay, !isPlaybackSuspended else {
            isBuffering = false
            if playbackStatus != .ended {
                playbackStatus = nil
            }
            return
        }

        guard item.status == .readyToPlay else {
            isBuffering = true
            playbackStatus = .preparing
            return
        }

        if isAtPlaybackEnd(player: player) {
            handlePlaybackEnded()
        } else if isSeeking {
            isBuffering = true
            playbackStatus = .seeking
        } else if item.isPlaybackBufferEmpty || isWaitingForBufferRecovery {
            markWaitingForBufferRecovery()
        } else {
            isBuffering = false
            playbackStatus = .interrupted
            recordDiagnostic(level: .warning, name: "unexpected_pause")

            guard !didAttemptUnexpectedPauseRecovery else { return }
            didAttemptUnexpectedPauseRecovery = true
            DispatchQueue.main.async { [weak self, weak player] in
                guard let self, let player,
                      self.wantsToPlay,
                      !self.isPlaybackSuspended,
                      self.playbackStatus == .interrupted else { return }
                player.play()
                AppLogger.video.warning("Attempting one automatic recovery from an unexpected pause")
            }
        }
    }

    private func markWaitingForBufferRecovery() {
        guard wantsToPlay, !isPlaybackSuspended else { return }
        let wasAlreadyWaiting = isWaitingForBufferRecovery
        isPlaying = false
        isBuffering = true
        isWaitingForBufferRecovery = true
        playbackStatus = isSeeking ? .seeking : .buffering
        if !wasAlreadyWaiting {
            recordDiagnostic(level: .warning, name: "buffer_empty")
        }
    }

    private func resumeAfterBufferRecoveryIfNeeded(player: AVPlayer, item: AVPlayerItem) {
        guard Self.shouldResumeAfterBufferRecovery(
            wantsToPlay: wantsToPlay,
            isAppInactive: isPlaybackSuspended,
            isSeeking: isSeeking,
            isAtEnd: isAtPlaybackEnd(player: player),
            isBufferEmpty: item.isPlaybackBufferEmpty
        ) else { return }

        guard isWaitingForBufferRecovery || playbackStatus == .buffering else { return }
        recordDiagnostic(name: "buffer_recovered")
        startPlayback(player: player)
        AppLogger.video.info("Playback resumed after buffer recovery")
    }

    private func handlePlaybackEnded() {
        wantsToPlay = false
        isPlaying = false
        isBuffering = false
        isWaitingForBufferRecovery = false
        playbackStatus = .ended
        recordDiagnostic(name: "playback_ended")
        AppLogger.video.info("Playback reached the end of the item")
        onPlaybackEnded?()
    }

    private func isAtPlaybackEnd(player: AVPlayer) -> Bool {
        guard duration > 0 else { return false }
        let currentSeconds = player.currentTime().seconds
        guard currentSeconds.isFinite else { return false }
        let threshold = max(0.1, 1.5 / Double(max(videoFrameRate, 1)))
        return currentSeconds >= duration - threshold
    }

    nonisolated static func shouldResumeAfterBufferRecovery(
        wantsToPlay: Bool,
        isAppInactive: Bool,
        isSeeking: Bool,
        isAtEnd: Bool,
        isBufferEmpty: Bool
    ) -> Bool {
        wantsToPlay && !isAppInactive && !isSeeking && !isAtEnd && !isBufferEmpty
    }

    nonisolated static func resolvedSeekTarget(
        requestedTime: Double,
        duration: Double,
        frameRate: Double,
        wantsToPlay: Bool
    ) -> Double {
        let lowerClamped = max(0, requestedTime)
        guard duration.isFinite, duration > 0 else { return lowerClamped }

        let upperClamped = min(lowerClamped, duration)
        guard wantsToPlay, upperClamped >= duration else { return upperClamped }

        let frameDuration = 1 / max(frameRate, 1)
        return max(0, duration - frameDuration)
    }

    private func recordDiagnostic(
        level: PlaybackDiagnosticEvent.Level = .info,
        name: String,
        message: String? = nil,
        error: Error? = nil,
        accessEvent: AVPlayerItemAccessLogEvent? = nil
    ) {
        let resolvedError = error ?? self.error
        let nsError = resolvedError as NSError?
        let currentPlayerTime = player?.currentTime().seconds
        let diagnosticPlaybackTime = currentPlayerTime?.isFinite == true ? currentPlayerTime! : currentTime
        let item = playerItem

        let snapshot = PlaybackDiagnosticSnapshot(
            playerID: id.uuidString,
            videoFileID: videoFileId,
            tileIndex: tileIndex,
            displayContext: diagnosticDisplayContext,
            playbackTime: diagnosticPlaybackTime,
            duration: duration,
            rate: player?.rate ?? 0,
            wantsToPlay: wantsToPlay,
            isPlaying: isPlaying,
            isSeeking: isSeeking,
            timeControlStatus: Self.timeControlStatusName(player?.timeControlStatus),
            waitingReason: player?.reasonForWaitingToPlay?.rawValue,
            playerStatus: Self.playerStatusName(player?.status),
            itemStatus: Self.itemStatusName(item?.status),
            bufferEmpty: item?.isPlaybackBufferEmpty ?? false,
            likelyToKeepUp: item?.isPlaybackLikelyToKeepUp ?? false,
            bufferedAhead: Self.bufferedDurationAhead(item: item, currentTime: diagnosticPlaybackTime),
            activePlayerCount: GlobalPlaybackManager.shared.activePlayers.count,
            videoWidth: videoPresentationSize.width,
            videoHeight: videoPresentationSize.height,
            frameRate: videoFrameRate,
            thermalState: Self.thermalStateName(ProcessInfo.processInfo.thermalState),
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            errorDomain: nsError?.domain,
            errorCode: nsError?.code,
            errorDescription: nsError?.localizedDescription,
            bytesTransferred: accessEvent?.numberOfBytesTransferred,
            transferDuration: accessEvent?.transferDuration,
            observedBitrate: accessEvent?.observedBitrate,
            averageVideoBitrate: accessEvent?.averageVideoBitrate,
            numberOfStalls: accessEvent?.numberOfStalls,
            droppedVideoFrames: accessEvent?.numberOfDroppedVideoFrames,
            serverAddress: accessEvent?.serverAddress
        )
        let event = PlaybackDiagnosticEvent(
            level: level,
            name: name,
            message: message,
            snapshot: snapshot
        )

        Task {
            await PlaybackDiagnosticsStore.shared.record(event)
        }
    }

    private nonisolated static func bufferedDurationAhead(item: AVPlayerItem?, currentTime: Double) -> Double {
        guard let item, currentTime.isFinite else { return 0 }

        for value in item.loadedTimeRanges {
            let range = value.timeRangeValue
            let start = range.start.seconds
            let end = CMTimeRangeGetEnd(range).seconds
            if start.isFinite, end.isFinite, currentTime >= start, currentTime <= end {
                return max(0, end - currentTime)
            }
        }
        return 0
    }

    private nonisolated static func timeControlStatusName(_ status: AVPlayer.TimeControlStatus?) -> String {
        switch status {
        case .playing: return "playing"
        case .paused: return "paused"
        case .waitingToPlayAtSpecifiedRate: return "waiting"
        case nil: return "unavailable"
        @unknown default: return "unknown"
        }
    }

    private nonisolated static func playerStatusName(_ status: AVPlayer.Status?) -> String {
        switch status {
        case .readyToPlay: return "ready"
        case .failed: return "failed"
        case .unknown: return "unknown"
        case nil: return "unavailable"
        @unknown default: return "unknown"
        }
    }

    private nonisolated static func itemStatusName(_ status: AVPlayerItem.Status?) -> String {
        switch status {
        case .readyToPlay: return "ready"
        case .failed: return "failed"
        case .unknown: return "unknown"
        case nil: return "unavailable"
        @unknown default: return "unknown"
        }
    }

    private nonisolated static func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    // MARK: - Autoplay Gate

    /// Plays the current item only when both the item is ready and the
    /// duration is known. Called from both the item-status and the duration
    /// KVO observations — whichever arrives last actually starts playback.
    /// `shouldAutoplayCurrentItem` is consumed (set to false) so we never
    /// re-autoplay after a subsequent observation fires.
    private func maybeAutoplay() {
        guard shouldAutoplayCurrentItem else { return }
        guard duration > 0 else { return }
        guard let item = playerItem, item.status == .readyToPlay else { return }
        shouldAutoplayCurrentItem = false
        if let player {
            startPlayback(player: player)
        }
    }

    // MARK: - Cleanup

    private func cleanupPlayer() {
        // Cancel any in-flight async loads from a previous setup BEFORE we
        // tear down the player. The task bodies guard on `playerItem === item`
        // and `Task.isCancelled`, so cancelling here prevents stale writes
        // onto the next setup's player item.
        assetLoadTask?.cancel()
        assetLoadTask = nil
        audioMixTask?.cancel()
        audioMixTask = nil

        flushPlaybackStats()

        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil

        statusObservation?.invalidate()
        statusObservation = nil

        timeControlObservation?.invalidate()
        timeControlObservation = nil

        itemStatusObservation?.invalidate()
        itemStatusObservation = nil

        durationObservation?.invalidate()
        durationObservation = nil

        playbackLikelyObservation?.invalidate()
        playbackLikelyObservation = nil

        playbackBufferEmptyObservation?.invalidate()
        playbackBufferEmptyObservation = nil

        itemCancellables.removeAll()

        player?.pause()
        player = nil
        loadedSurface?.playerLayer.player = nil
        playerItem = nil
        audioMix = nil

        isPlaying = false
        wantsToPlay = false
        currentTime = 0
        duration = 0
        isBuffering = false
        playbackStatus = nil
        error = nil
        videoFileId = nil
        shouldAutoplayCurrentItem = true
        isSeeking = false
        seekRequestID = nil
        lastSeek = nil
        isWaitingForBufferRecovery = false
        didAttemptUnexpectedPauseRecovery = false
        resetPlaybackStatsState()

        AppLogger.video.debug("Player cleaned up")
    }

    @discardableResult
    func recordPlaybackStatsProgressForTesting(currentTime: Double, isPlaybackActive: Bool) -> Bool {
        recordPlaybackStatsProgress(currentTime: currentTime, isPlaybackActive: isPlaybackActive)
    }

    @discardableResult
    private func recordPlaybackStatsProgress(currentTime: Double, isPlaybackActive: Bool) -> Bool {
        defer { lastStatsPlaybackTime = currentTime }

        guard isPlaybackActive,
              let fileId = videoFileId,
              playbackStatsReporter != nil else { return false }

        guard let lastTime = lastStatsPlaybackTime else { return false }

        let delta = currentTime - lastTime
        guard delta > 0, delta < 5 else { return false }

        sessionPlaybackTime += delta
        unreportedViewTime += delta

        let shouldIncrementPlayCount = !didIncrementPlayCountForCurrentItem && sessionPlaybackTime >= playCountThreshold
        if shouldIncrementPlayCount {
            didIncrementPlayCountForCurrentItem = true
        }

        var viewTimeToReport = 0
        if unreportedViewTime >= viewTimeFlushInterval {
            viewTimeToReport = Int(unreportedViewTime)
            unreportedViewTime -= Double(viewTimeToReport)
        }

        reportPlaybackStats(fileId: fileId, incrementPlayCount: shouldIncrementPlayCount, addViewTime: viewTimeToReport)
        return shouldIncrementPlayCount || viewTimeToReport > 0
    }

    private func recordCurrentPlaybackStatsProgress(player: AVPlayer) {
        let currentSeconds = player.currentTime().seconds
        guard currentSeconds.isFinite else { return }
        recordPlaybackStatsProgress(currentTime: currentSeconds, isPlaybackActive: player.rate > 0)
    }

    private func flushPlaybackStats(requireBackgroundTask: Bool = false) {
        guard let fileId = videoFileId else { return }

        let viewTimeToReport = Int(unreportedViewTime)
        guard viewTimeToReport > 0 else { return }

        unreportedViewTime -= Double(viewTimeToReport)
        reportPlaybackStats(fileId: fileId, incrementPlayCount: false, addViewTime: viewTimeToReport, requireBackgroundTask: requireBackgroundTask)
    }

    private func reportPlaybackStats(
        fileId: String,
        incrementPlayCount: Bool,
        addViewTime: Int,
        requireBackgroundTask: Bool = false
    ) {
        let queue = statsQueue
        let reporter = playbackStatsReporter
        Task {
            await queue.enqueue(
                fileId: fileId,
                incrementPlayCount: incrementPlayCount,
                addViewTime: addViewTime,
                reporter: reporter,
                requireBackgroundTask: requireBackgroundTask
            )
        }
    }

    private func resetPlaybackStatsState() {
        lastStatsPlaybackTime = nil
        unreportedViewTime = 0
        sessionPlaybackTime = 0
        didIncrementPlayCountForCurrentItem = false
    }

    deinit {
        // Not an isolated deinit: its back-deployment shim aborts when the
        // object is released outside a Swift task. Players are released on the
        // main thread (the pool releases them before dropping them), so the
        // teardown runs there synchronously; `lifecycleCancellables` cancel
        // themselves when freed.
        guard Thread.isMainThread else { return }
        MainActor.assumeIsolated {
            cleanupPlayer()
        }
    }
}

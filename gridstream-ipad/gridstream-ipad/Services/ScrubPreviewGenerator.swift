//
//  ScrubPreviewGenerator.swift
//  gridstream-ipad
//

import AVFoundation
import CoreMedia
import Foundation
import OSLog
import UIKit

/// Generates preview frames for video scrubbing using AVAssetImageGenerator.
/// Implements debouncing and fallback behavior for smooth user experience.
@Observable
final class ScrubPreviewGenerator {

    // MARK: - Public Properties

    /// The current preview image to display, updated asynchronously
    private(set) var currentPreviewImage: CGImage?

    // MARK: - Private Properties

    /// The last successfully generated image, used as fallback when generation fails
    private var lastSuccessfulImage: CGImage?

    /// The AVAssetImageGenerator configured for the current asset.
    /// Only touched on the main actor, and in deinit once nothing else holds the object.
    @ObservationIgnored nonisolated(unsafe) private var imageGenerator: AVAssetImageGenerator?

    /// The pending frame generation task, cancelled on new requests.
    /// Only touched on the main actor, and in deinit once nothing else holds the object.
    @ObservationIgnored nonisolated(unsafe) private var pendingGenerationTask: Task<Void, Never>?

    /// The current asset URL for cache key generation
    private var currentAssetURL: URL?

    /// The most recently requested time - used by debounce to generate the latest position
    private var pendingTime: CMTime?

    /// Whether a debounced generation is in progress
    private var isDebouncing: Bool = false

    /// Identifies the generation task allowed to publish its result. Bumped for
    /// every new task and on cancellation, so a superseded task (cancelled or
    /// still finishing its fetch) can neither show its stale frame nor reset
    /// the debounce state that belongs to the task that replaced it.
    private var generationToken: UInt64 = 0

    /// Whether the current request is in precision mode (no rounding, no caching)
    private var currentPrecisionMode: Bool = false

    /// Debounce delay in nanoseconds (50ms = ~20 requests/sec max)
    private static let debounceDelayNanoseconds: UInt64 = 50_000_000

    // MARK: - Server Frame Fetching Properties

    /// Server base URL for frame API requests
    private var serverURL: URL?

    /// Current video file ID for server frame requests
    private var currentVideoId: String?

    /// Frame interval matching server-side caching (2 seconds)
    private nonisolated static let frameInterval: Double = 2.0

    // MARK: - Configuration

    /// Configures the generator with an AVAsset for frame extraction (fallback mode).
    /// - Parameter asset: The AVAsset to extract frames from
    func configure(with asset: AVAsset) {
        cancelPendingGeneration()

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 180)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        imageGenerator = generator

        AppLogger.video.debug("ScrubPreviewGenerator configured with asset (fallback mode)")
    }

    /// Configures the generator with server connection details for frame fetching.
    /// - Parameters:
    ///   - serverURL: The server base URL
    ///   - videoId: The video file ID for frame requests
    func configureServerFrameFetching(serverURL: URL, videoId: String) {
        self.serverURL = serverURL
        self.currentVideoId = videoId
        AppLogger.video.debug("ScrubPreviewGenerator configured for server frame fetching: \(videoId)")
    }

    // MARK: - Frame Generation

    /// Generates a preview frame at the specified time for the given video URL.
    /// Implements debouncing to limit requests during rapid scrubbing.
    /// - Parameters:
    ///   - time: The CMTime position to generate a preview for
    ///   - url: The video URL, used for cache key generation
    ///   - immediate: If true, skip debounce delay
    ///   - precisionMode: If true, skip cache lookup/write and time rounding
    func generatePreview(at time: CMTime, for url: URL, immediate: Bool = false, precisionMode: Bool = false) {
        currentAssetURL = url
        pendingTime = time
        currentPrecisionMode = precisionMode

        // In precision mode, skip cache lookup (we want fresh exact frames)
        if !precisionMode {
            // Check cache first for immediate return
            if let cachedImage = PreviewFrameCache.shared.frame(forURL: url, atTime: time) {
                currentPreviewImage = cachedImage
                lastSuccessfulImage = cachedImage
                return
            }
        }

        // If already debouncing, just update pendingTime (already done above) and return
        // The existing task will pick up the latest time when it completes
        if isDebouncing && !immediate {
            return
        }

        // Cancel any existing debounce task if we need immediate generation
        if immediate {
            pendingGenerationTask?.cancel()
            isDebouncing = false
        }

        // Start debounced generation task
        isDebouncing = true
        generationToken &+= 1
        let token = generationToken
        pendingGenerationTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            // Skip debounce delay for immediate requests (first frame when scrubbing starts)
            if !immediate {
                try? await Task.sleep(nanoseconds: Self.debounceDelayNanoseconds)
            }
            guard self.isCurrentGeneration(token) else {
                AppLogger.video.debug("Preview generation cancelled")
                return
            }

            // Capture the time to generate before async work
            let timeToGenerate = self.pendingTime
            let urlToUse = self.currentAssetURL
            let precision = self.currentPrecisionMode

            // Generate the frame for the most recent requested time
            var image: CGImage?
            if let time = timeToGenerate, let url = urlToUse {
                image = await self.performFrameGeneration(at: time, for: url, precisionMode: precision)
            }

            // A newer request or a cancellation took over while generating:
            // its state is not ours to touch.
            guard self.isCurrentGeneration(token) else { return }

            if let image {
                self.currentPreviewImage = image
                self.lastSuccessfulImage = image
            } else {
                self.useFallbackImage()
            }
            self.isDebouncing = false

            // If pendingTime changed during generation, start another cycle
            if let latestTime = self.pendingTime,
               let generatedTime = timeToGenerate,
               latestTime != generatedTime,
               let latestURL = self.currentAssetURL {
                self.generatePreview(at: latestTime, for: latestURL, precisionMode: self.currentPrecisionMode)
            }
        }
    }

    private func isCurrentGeneration(_ token: UInt64) -> Bool {
        token == generationToken && !Task.isCancelled
    }

    /// Cancels any pending frame generation task.
    func cancelPendingGeneration() {
        generationToken &+= 1
        pendingGenerationTask?.cancel()
        pendingGenerationTask = nil
        isDebouncing = false
    }

    /// Cleans up the generator, cancelling tasks and releasing resources.
    func cleanup() {
        cancelPendingGeneration()
        imageGenerator?.cancelAllCGImageGeneration()
        imageGenerator = nil
        currentPreviewImage = nil
        lastSuccessfulImage = nil
        currentAssetURL = nil
        pendingTime = nil
        isDebouncing = false
        AppLogger.video.debug("ScrubPreviewGenerator cleaned up")
    }

    // MARK: - Private Methods

    /// Produces the frame for `time` without publishing it; the caller
    /// decides whether the result is still wanted.
    /// Priority: 1) Server frame fetch, 2) AVAssetImageGenerator fallback
    private func performFrameGeneration(at time: CMTime, for url: URL, precisionMode: Bool = false) async -> CGImage? {
        // Try server frame fetch first if configured
        if let serverURL = serverURL, let videoId = currentVideoId,
           let image = await performServerFrameFetch(at: time, for: url, serverURL: serverURL, videoId: videoId, precisionMode: precisionMode) {
            return image
        }
        return await performImageGeneratorFrameGeneration(at: time, for: url, precisionMode: precisionMode)
    }

    /// Fetches a frame from the server API.
    /// Returns nil on failure (caller should try fallback).
    private func performServerFrameFetch(at time: CMTime, for url: URL, serverURL: URL, videoId: String, precisionMode: Bool = false) async -> CGImage? {
        // In precision mode, use exact time; otherwise round to 2s interval
        let requestTime = precisionMode ? time.seconds : Self.roundTimeToInterval(time.seconds)

        do {
            let frameURL = VideoURLBuilder.buildScrubFrameURL(
                from: serverURL,
                videoId: videoId,
                time: requestTime,
                additionalQueryItems: precisionMode ? [URLQueryItem(name: "exact", value: "true")] : []
            )
            guard let frameURL else { throw ScrubPreviewError.invalidURL }
            let frameData = try await Self.fetchFrameFromServer(url: frameURL, session: ServerSessionManager.shared.urlSession)

            guard let uiImage = UIImage(data: frameData),
                  let cgImage = uiImage.cgImage else {
                AppLogger.video.warning("Failed to convert server frame data to CGImage")
                return nil
            }

            // Only cache in normal mode, not precision mode
            if !precisionMode {
                PreviewFrameCache.shared.setFrame(cgImage, forURL: url, atTime: time)
            }
            return cgImage
        } catch {
            AppLogger.video.debug("Server frame fetch failed at \(requestTime)s: \(error.localizedDescription)")
            return nil
        }
    }

    /// Fetches a single frame from an (authorized) scrub frame URL.
    private nonisolated static func fetchFrameFromServer(url: URL, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ScrubPreviewError.serverError
        }

        return data
    }

    /// Rounds time to match server frame interval for cache efficiency.
    private nonisolated static func roundTimeToInterval(_ time: Double) -> Double {
        (time / Self.frameInterval).rounded() * Self.frameInterval
    }

    private func performImageGeneratorFrameGeneration(at time: CMTime, for url: URL, precisionMode: Bool = false) async -> CGImage? {
        guard let configuredGenerator = imageGenerator else {
            AppLogger.video.warning("No image generator configured for preview")
            return nil
        }
        // Handed to its own async API below; it is only configured here, on
        // the main actor, which the compiler can't tell of a stored generator.
        nonisolated(unsafe) let generator = configuredGenerator

        // Use tighter tolerance for precision mode
        if precisionMode {
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        } else {
            generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        }

        do {
            let (cgImage, _) = try await generator.image(at: time)

            // Only cache in normal mode, not precision mode
            if !precisionMode {
                PreviewFrameCache.shared.setFrame(cgImage, forURL: url, atTime: time)
            }
            return cgImage
        } catch {
            AppLogger.video.error("Frame generation failed at \(time.seconds)s: \(error.localizedDescription)")
            return nil
        }
    }

    /// Sets the current preview image to the last successful image as a fallback.
    private func useFallbackImage() {
        if let fallback = lastSuccessfulImage {
            currentPreviewImage = fallback
            AppLogger.video.debug("Using fallback preview image")
        }
    }

    // MARK: - Preloading

    /// Preloads frames around the current position for smoother scrubbing.
    /// Fetches ±5 frames in parallel without blocking the UI.
    func preloadFramesAround(time: Double, for url: URL) {
        guard let serverURL = serverURL, let videoId = currentVideoId else {
            AppLogger.video.debug("Cannot preload: server frame fetching not configured")
            return
        }

        Task {
            let framesToPreload = 5
            var timesToFetch: [Double] = []

            for offset in -framesToPreload...framesToPreload where offset != 0 {
                let frameTime = time + Double(offset) * Self.frameInterval
                if frameTime >= 0 {
                    // Skip if already in cache
                    let cmTime = CMTime(seconds: frameTime, preferredTimescale: 600)
                    if PreviewFrameCache.shared.frame(forURL: url, atTime: cmTime) == nil {
                        timesToFetch.append(frameTime)
                    }
                }
            }

            guard !timesToFetch.isEmpty else {
                AppLogger.video.debug("Preload: All frames already cached")
                return
            }

            AppLogger.video.debug("Preloading \(timesToFetch.count) frames around \(time)s")

            // Build the URLs here: the token lookup is main-actor bound
            let session = ServerSessionManager.shared.urlSession
            let frameRequests = timesToFetch.compactMap { frameTime in
                VideoURLBuilder.buildScrubFrameURL(
                    from: serverURL,
                    videoId: videoId,
                    time: Self.roundTimeToInterval(frameTime)
                ).map { (frameTime, $0) }
            }

            await withTaskGroup(of: Void.self) { group in
                for (frameTime, frameURL) in frameRequests {
                    group.addTask { [url] in
                        do {
                            let data = try await Self.fetchFrameFromServer(url: frameURL, session: session)
                            if let uiImage = UIImage(data: data), let cgImage = uiImage.cgImage {
                                let cmTime = CMTime(seconds: frameTime, preferredTimescale: 600)
                                await MainActor.run {
                                    PreviewFrameCache.shared.setFrame(cgImage, forURL: url, atTime: cmTime)
                                }
                            }
                        } catch {
                            // Silently ignore preload failures
                        }
                    }
                }
            }

            AppLogger.video.debug("Preloading complete")
        }
    }

    deinit {
        pendingGenerationTask?.cancel()
        imageGenerator?.cancelAllCGImageGeneration()
    }
}

enum ScrubPreviewError: Error {
    case invalidURL
    case serverError
    case invalidResponse
}

extension ScrubPreviewGenerator {

    func startBackgroundGeneration(serverURL: URL, videoId: String) async {
        do {
            try await APIClient(serverURL: serverURL).send(.post, "videos/\(videoId)/scrub/generate")
            AppLogger.video.info("Started background generation for \(videoId)")
        } catch let error as APIError {
            AppLogger.video.warning("Failed to start background generation for \(videoId): \(error.localizedDescription)")
        } catch {
            AppLogger.video.warning("Error starting background generation: \(error.localizedDescription)")
        }
    }

    func stopBackgroundGeneration(serverURL: URL, videoId: String) async {
        do {
            try await APIClient(serverURL: serverURL).send(.delete, "videos/\(videoId)/scrub/generate")
            AppLogger.video.info("Stopped background generation for \(videoId)")
        } catch let error as APIError {
            AppLogger.video.debug("Background generation stop failed for \(videoId): \(error.localizedDescription)")
        } catch {
            AppLogger.video.warning("Error stopping background generation: \(error.localizedDescription)")
        }
    }

    func pauseAllBackgroundGeneration(serverURL: URL) async {
        do {
            try await APIClient(serverURL: serverURL).send(.post, "scrub/pause-all")
            AppLogger.video.info("Paused all background generation")
        } catch let error as APIError {
            AppLogger.video.debug("Pause-all failed: \(error.localizedDescription)")
        } catch {
            AppLogger.video.warning("Error pausing all background generation: \(error.localizedDescription)")
        }
    }

    func resumeAllBackgroundGeneration(serverURL: URL) async {
        do {
            try await APIClient(serverURL: serverURL).send(.post, "scrub/resume-all")
            AppLogger.video.info("Resumed all background generation")
        } catch let error as APIError {
            AppLogger.video.debug("Resume-all failed: \(error.localizedDescription)")
        } catch {
            AppLogger.video.warning("Error resuming all background generation: \(error.localizedDescription)")
        }
    }
}

import AVFoundation
import AppKit
import Foundation
import ImageIO
import OSLog

actor ScrubFrameGenerator {
    static let shared = ScrubFrameGenerator(databaseManager: .shared)

    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    private let logger = Logger(subsystem: "com.gridstream.macos", category: "ScrubFrameGenerator")

    static let frameWidth = 320
    static let frameHeight = 180
    static let frameInterval: Double = 2.0
    private static let compressionQuality: CGFloat = 0.50

    /// AVAssetImageGenerator returns error -11832 ("Cannot Open") for a requested time at or
    /// before the first frame's PTS. Videos with a non-zero stream start_time / edit list
    /// (e.g. first frame at 0.046s) therefore fail at the t=0 grid point even though playback
    /// works. Request the first grid point slightly later so the generator returns the opening
    /// frame. Must stay below frameInterval/2 so `roundTime` maps it back to grid slot 0 —
    /// otherwise the first frame would be re-requested (and re-fail) on every sweep.
    static let firstFrameRequestOffset: Double = 0.1

    /// The time actually requested from AVAssetImageGenerator for a given scrub-grid time.
    nonisolated static func requestTime(forGridTime time: Double) -> Double {
        max(time, firstFrameRequestOffset)
    }

    func generateFrame(videoId: String, time: Double, exact: Bool = false) async throws -> Data {
        // In exact mode (precision scrubbing), use the exact time without rounding
        let targetTime = exact ? time : roundTime(time)

        let videoRecord = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(videoId, in: db)
        }

        guard let videoRecord else {
            logger.error("Video not found: \(videoId)")
            throw ScrubFrameError.videoNotFound
        }

        let videoURL = URL(fileURLWithPath: videoRecord.path)
        let asset = AVURLAsset(url: videoURL)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: Self.frameWidth, height: Self.frameHeight)

        // Use tighter tolerance for exact/precision mode
        if exact {
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        } else {
            generator.requestedTimeToleranceBefore = CMTime(seconds: 1.0, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 1.0, preferredTimescale: 600)
        }

        // Same first-frame offset as frameStream: t=0 fails on videos whose first PTS is not 0
        let cmTime = CMTime(seconds: Self.requestTime(forGridTime: targetTime), preferredTimescale: 600)

        let cgImage: CGImage
        do {
            let result = try await generator.image(at: cmTime)
            cgImage = result.image
        } catch {
            logger.error("Failed to extract frame at \(targetTime)s: \(error.localizedDescription)")
            throw ScrubFrameError.frameExtractionFailed
        }

        guard let frameData = Self.encodeToJPEG(cgImage) else {
            logger.error("Failed to encode frame to JPEG")
            throw ScrubFrameError.compressionFailed
        }

        logger.debug("Generated frame at \(targetTime)s (JPEG), size: \(frameData.count) bytes")
        return frameData
    }

    /// Streams JPEG-encoded frames for `times` using a single reused image generator.
    /// `nonisolated` so decoding/encoding run off the actor; per-frame failures are skipped.
    nonisolated func frameStream(videoPath: String, times: [Double]) -> AsyncThrowingStream<(Double, Data), Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let asset = AVURLAsset(url: URL(fileURLWithPath: videoPath))
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: Self.frameWidth, height: Self.frameHeight)
                generator.requestedTimeToleranceBefore = CMTime(seconds: 1.0, preferredTimescale: 600)
                generator.requestedTimeToleranceAfter = CMTime(seconds: 1.0, preferredTimescale: 600)

                let cmTimes = times.map { CMTime(seconds: Self.requestTime(forGridTime: $0), preferredTimescale: 600) }

                for await result in generator.images(for: cmTimes) {
                    if Task.isCancelled { break }
                    guard let cgImage = try? result.image,
                          let data = Self.encodeToJPEG(cgImage) else {
                        continue
                    }
                    continuation.yield((result.requestedTime.seconds, data))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Streams frames for `times` (one reused generator) and stores them in batches.
    /// `flushEvery` controls transaction size = visibility granularity for the iPad.
    /// `onBatchStored` is called after each successful flush with the count just stored
    /// (used by the idle preloader to update aggregate progress; nil for on-demand).
    /// Honors task cancellation and flushes the partial buffer before returning,
    /// so already-decoded frames are never discarded.
    nonisolated func generateAndStore(
        videoId: String,
        videoPath: String,
        times: [Double],
        flushEvery: Int,
        onBatchStored: (@Sendable (Int) async -> Void)? = nil
    ) async -> ScrubGenerationResult {
        var result = ScrubGenerationResult()
        var buffer: [(time: Double, data: Data)] = []
        func flush() async {
            guard !buffer.isEmpty else { return }
            let pending = buffer
            buffer.removeAll(keepingCapacity: true)
            do {
                try await ScrubFrameCache.shared.storeFrames(videoId: videoId, frames: pending)
                result.stored += pending.count
                await onBatchStored?(pending.count)
            } catch {
                logger.error("Failed to store \(pending.count) scrub frames for \(videoId): \(error.localizedDescription)")
                if result.error == nil { result.error = error.localizedDescription }
            }
        }
        do {
            for try await (time, data) in frameStream(videoPath: videoPath, times: times) {
                if Task.isCancelled { break }
                buffer.append((time: time, data: data))
                if buffer.count >= flushEvery { await flush() }
            }
        } catch {
            logger.error("Scrub frame stream failed for \(videoId): \(error.localizedDescription)")
            if result.error == nil { result.error = error.localizedDescription }
        }
        await flush()
        return result
    }

    private nonisolated static func encodeToJPEG(_ cgImage: CGImage) -> Data? {
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: Self.frameWidth, height: Self.frameHeight))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: Self.compressionQuality]) else {
            return nil
        }
        return jpegData
    }

    func roundTime(_ time: Double) -> Double {
        (time / Self.frameInterval).rounded() * Self.frameInterval
    }
}

/// Outcome of a single `generateAndStore` pass, used for failure tracking.
nonisolated struct ScrubGenerationResult: Sendable {
    var stored: Int = 0
    var error: String?
}

nonisolated extension ScrubFrameGenerator {
    /// A video is flagged `scrub_failed` after this many consecutive incomplete passes.
    static let maxScrubAttempts = 4

    private static let outcomeLogger = Logger(subsystem: "com.gridstream.macos", category: "ScrubOutcome")

    /// Records the outcome of one generation pass for failure tracking. `expected` is the
    /// number of frames requested this pass: a pass that stores them all with no error clears
    /// the failure state; otherwise it counts as one failed attempt and stores the reason.
    /// Callers must invoke this only when the work was **not** cancelled.
    func recordOutcome(fileId: String, expected: Int, result: ScrubGenerationResult) async {
        let complete = result.error == nil && result.stored >= expected
        let now = Date().timeIntervalSince1970
        do {
            try await databaseManager.write { db in
                if complete {
                    try VideoFileRecord.recordScrubSuccess(fileId: fileId, in: db)
                } else {
                    let message = result.error
                        ?? "\(expected - result.stored) of \(expected) frames could not be decoded"
                    try VideoFileRecord.recordScrubFailure(
                        fileId: fileId, error: message, now: now,
                        maxAttempts: Self.maxScrubAttempts, in: db)
                }
            }
        } catch {
            Self.outcomeLogger.error("Failed to record scrub outcome for \(fileId): \(error.localizedDescription)")
        }
    }
}

nonisolated enum ScrubFrameError: Error, LocalizedError {
    case videoNotFound
    case frameExtractionFailed
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .videoNotFound:
            return "Video not found in database"
        case .frameExtractionFailed:
            return "Failed to extract frame from video"
        case .compressionFailed:
            return "Failed to compress frame to JPEG"
        }
    }
}

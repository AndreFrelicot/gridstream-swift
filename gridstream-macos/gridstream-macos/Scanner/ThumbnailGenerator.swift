import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import OSLog

actor ThumbnailGenerator {
    private let logger = Logger(subsystem: "com.gridstream.macos", category: "ThumbnailGenerator")

    /// Target thumbnail dimensions (16:9 aspect ratio)
    private static let thumbnailWidth: CGFloat = 320
    private static let thumbnailHeight: CGFloat = 180

    /// Time threshold for determining capture time strategy
    private static let captureTimeThreshold: Double = 20.0

    /// JPEG compression quality (0.0 - 1.0)
    private static let jpegCompressionQuality: CGFloat = 0.8

    /// Minimum brightness threshold (0-255). Frames below this are considered too dark.
    private static let minBrightnessThreshold: Double = 20.0

    /// Time step to try when a dark frame is detected (seconds)
    private static let darkFrameTimeStep: Double = 10.0

    /// Maximum retries when encountering dark frames
    private static let maxDarkFrameRetries: Int = 5

    /// Calculates the optimal capture time for thumbnail generation.
    /// - Parameter duration: The video duration in seconds
    /// - Returns: The time in seconds at which to capture the thumbnail
    nonisolated func calculateCaptureTime(for duration: Double) -> Double {
        if duration >= Self.captureTimeThreshold {
            return Self.captureTimeThreshold
        } else {
            return duration * 0.5
        }
    }

    /// Generates a thumbnail image from a video file at a specific time.
    /// Used when the user explicitly chooses a frame — no dark-frame retry logic.
    /// - Parameters:
    ///   - url: The URL of the video file
    ///   - time: The time in seconds at which to capture the frame
    /// - Returns: JPEG image data for the thumbnail, or nil if generation fails
    func generateThumbnail(from url: URL, at time: Double) async -> Data? {
        let asset = AVURLAsset(url: url)

        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(
            width: Self.thumbnailWidth,
            height: Self.thumbnailHeight
        )
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero

        let cmTime = CMTime(seconds: time, preferredTimescale: 600)

        do {
            let cgImage = try await generateImage(from: imageGenerator, at: cmTime)
            guard let jpegData = convertToJPEG(cgImage: cgImage) else {
                logger.warning("Failed to convert CGImage to JPEG for \(url.lastPathComponent) at \(time)s")
                return nil
            }
            logger.debug("Generated thumbnail for \(url.lastPathComponent) at explicit time \(time)s")
            return jpegData
        } catch {
            logger.warning("Failed to generate thumbnail for \(url.lastPathComponent) at \(time)s: \(error.localizedDescription)")
            return nil
        }
    }

    /// Generates a thumbnail image from a video file.
    /// Automatically retries at different timestamps if the captured frame is too dark.
    /// - Parameter url: The URL of the video file
    /// - Returns: JPEG image data for the thumbnail, or nil if generation fails
    func generateThumbnail(from url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)

        do {
            let duration = try await loadDuration(from: asset)
            let initialCaptureTime = calculateCaptureTime(for: duration)

            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(
                width: Self.thumbnailWidth,
                height: Self.thumbnailHeight
            )

            // Try to capture a non-dark frame
            var captureTime = initialCaptureTime
            var bestImage: CGImage?
            var bestBrightness: Double = 0
            var attempts = 0

            while attempts < Self.maxDarkFrameRetries {
                let time = CMTime(seconds: captureTime, preferredTimescale: 600)

                do {
                    let cgImage = try await generateImage(from: imageGenerator, at: time)
                    let brightness = calculateAverageBrightness(of: cgImage)

                    // Keep track of the best (brightest) frame we've found
                    if brightness > bestBrightness {
                        bestBrightness = brightness
                        bestImage = cgImage
                    }

                    // If brightness is acceptable, use this frame
                    if brightness >= Self.minBrightnessThreshold {
                        logger.debug("Thumbnail for \(url.lastPathComponent) at \(captureTime)s - brightness: \(String(format: "%.1f", brightness))")
                        break
                    }

                    // Frame is too dark, try a different time
                    logger.debug("Dark frame detected at \(captureTime)s (brightness: \(String(format: "%.1f", brightness))), trying next position")
                    captureTime += Self.darkFrameTimeStep

                    // Don't go past 90% of the video duration
                    if captureTime > duration * 0.9 {
                        // Try earlier in the video instead
                        captureTime = max(1.0, initialCaptureTime - Self.darkFrameTimeStep * Double(attempts + 1))
                    }

                    attempts += 1
                } catch {
                    // If we can't generate at this time, try the next
                    logger.debug("Failed to generate at \(captureTime)s, trying next position")
                    captureTime += Self.darkFrameTimeStep
                    attempts += 1
                }
            }

            // Use the best image we found (or nil if none worked)
            guard let finalImage = bestImage else {
                logger.warning("Failed to capture any valid frame for \(url.lastPathComponent)")
                return nil
            }

            guard let jpegData = convertToJPEG(cgImage: finalImage) else {
                logger.warning("Failed to convert CGImage to JPEG for \(url.lastPathComponent)")
                return nil
            }

            if bestBrightness < Self.minBrightnessThreshold {
                logger.info("Using best available frame for \(url.lastPathComponent) despite low brightness (\(String(format: "%.1f", bestBrightness)))")
            }

            return jpegData

        } catch {
            logger.warning("Failed to generate thumbnail for \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    private func loadDuration(from asset: AVURLAsset) async throws -> Double {
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }

    private func generateImage(from generator: AVAssetImageGenerator, at time: CMTime) async throws -> CGImage {
        return try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let image = image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: ThumbnailError.imageGenerationFailed)
                }
            }
        }
    }

    /// Calculates the average brightness of an image by sampling pixels.
    /// Uses a fast sampling strategy (every 8th pixel) for performance.
    /// - Parameter cgImage: The image to analyze
    /// - Returns: Average brightness value (0-255)
    private nonisolated func calculateAverageBrightness(of cgImage: CGImage) -> Double {
        let width = cgImage.width
        let height = cgImage.height

        // Create a bitmap context to access pixel data
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return 0
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            return 0
        }

        let pixelData = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        // Sample every 8th pixel for speed (still analyzes ~1500+ pixels for 320x180)
        let sampleStep = 8
        var totalLuminance: Double = 0
        var sampleCount: Int = 0

        for y in stride(from: 0, to: height, by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                let offset = (y * width + x) * 4
                let r = Double(pixelData[offset])
                let g = Double(pixelData[offset + 1])
                let b = Double(pixelData[offset + 2])

                // Calculate luminance using standard coefficients (ITU-R BT.601)
                let luminance = 0.299 * r + 0.587 * g + 0.114 * b
                totalLuminance += luminance
                sampleCount += 1
            }
        }

        return sampleCount > 0 ? totalLuminance / Double(sampleCount) : 0
    }

    private func convertToJPEG(cgImage: CGImage) -> Data? {
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(
            using: .jpeg,
            properties: [.compressionFactor: Self.jpegCompressionQuality]
        )
    }
}

nonisolated enum ThumbnailError: Error, LocalizedError {
    case imageGenerationFailed
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .imageGenerationFailed:
            return "Failed to generate image from video"
        case .conversionFailed:
            return "Failed to convert image to JPEG format"
        }
    }
}

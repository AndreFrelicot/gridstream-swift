import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import OSLog

actor FrameCaptureService {
    private let logger = Logger(subsystem: "com.gridstream.macos", category: "FrameCaptureService")

    /// JPEG compression quality for captures (high quality)
    private static let jpegCompressionQuality: CGFloat = 0.90

    /// Captures a full-resolution frame from a video file.
    func captureFrame(from url: URL, at time: Double) async throws -> (imageData: Data, width: Int, height: Int) {
        let asset = AVURLAsset(url: url)

        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        // Do NOT set maximumSize — capture at full native resolution
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero

        let cmTime = CMTime(seconds: time, preferredTimescale: 600)

        let cgImage = try await generateImage(from: imageGenerator, at: cmTime)
        let width = cgImage.width
        let height = cgImage.height

        guard let jpegData = convertToJPEG(cgImage: cgImage) else {
            throw FrameCaptureError.conversionFailed
        }

        logger.info("Captured frame at \(time)s from \(url.lastPathComponent): \(width)x\(height), \(jpegData.count) bytes")

        return (imageData: jpegData, width: width, height: height)
    }

    private func generateImage(from generator: AVAssetImageGenerator, at time: CMTime) async throws -> CGImage {
        return try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let image = image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: FrameCaptureError.imageGenerationFailed)
                }
            }
        }
    }

    private nonisolated func convertToJPEG(cgImage: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: Self.jpegCompressionQuality
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return mutableData as Data
    }
}

nonisolated enum FrameCaptureError: Error, LocalizedError {
    case imageGenerationFailed
    case conversionFailed
    case videoNotFound

    var errorDescription: String? {
        switch self {
        case .imageGenerationFailed:
            return "Failed to generate image from video"
        case .conversionFailed:
            return "Failed to convert image to JPEG format"
        case .videoNotFound:
            return "Video file not found"
        }
    }
}

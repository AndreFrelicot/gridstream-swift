import AVFoundation
import Foundation
import GridStreamAPI
import UIKit

extension DemoServer {
    func routeScrub(_ request: DemoRequest) async throws -> DemoResponse? {
        // Scrub frames: generated on request, nothing runs in the background.
        if let params = request.on("GET", "videos/:fileId/scrub/frame") {
            let fileId = params[0]
            return .jpeg(try await scrubFrame(fileId: fileId, query: request.query))
        }
        if let params = request.on("GET", "videos/:fileId/scrub/cached-times") {
            let fileId = params[0]
            let video = try requireVideo(fileId, in: try loadedStore())
            let times = Self.scrubTimes(duration: video.duration)
            return .json(DemoCachedTimes(times: times, cachedCount: times.count, totalFrames: times.count, duration: video.duration))
        }
        if let params = request.on("POST", "videos/:fileId/scrub/generate") {
            let fileId = params[0]
            _ = try requireVideo(fileId, in: try loadedStore())
            return .json(DemoGenerationStatus(status: "started", videoId: fileId))
        }
        if let params = request.on("DELETE", "videos/:fileId/scrub/generate") {
            let fileId = params[0]
            return .json(DemoGenerationStatus(status: "stopped", videoId: fileId))
        }
        if request.on("POST", "scrub/pause-all") != nil {
            return .json(DemoGlobalGenerationStatus(status: "paused", count: 0))
        }
        if request.on("POST", "scrub/resume-all") != nil {
            return .json(DemoGlobalGenerationStatus(status: "resumed", count: 0))
        }
        return nil
    }

    // MARK: - Scrub frames

    private func scrubFrame(fileId: String, query: [String: String]) async throws -> Data {
        guard let time = query["time"].flatMap(Double.init) else {
            throw DemoHTTPError.badRequest("Missing time parameter")
        }
        let exact = Self.bool(query["exact"]) ?? false
        let video = try requireVideo(fileId, in: try loadedStore())
        guard time.isFinite, time >= 0, video.duration <= 0 || time <= video.duration else {
            throw DemoHTTPError.badRequest("time must be between 0 and the video duration")
        }
        guard let clip = clipFile(fileId) else {
            throw DemoHTTPError.notFound("Video file not found")
        }

        let key = "\(fileId)@\(time)"
        if !exact, let cached = frameCache[key] {
            return cached
        }
        let frame = try await Self.jpegFrame(
            from: clip, at: time, exact: exact, maximumSize: CGSize(width: 640, height: 360), quality: 0.7
        )
        if !exact {
            cacheFrame(frame.data, key: key)
        }
        return frame.data
    }

    private func cacheFrame(_ data: Data, key: String) {
        if frameCache.updateValue(data, forKey: key) == nil {
            frameCacheOrder.append(key)
        }
        if frameCacheOrder.count > Self.maxCachedFrames {
            frameCache.removeValue(forKey: frameCacheOrder.removeFirst())
        }
    }

    /// The times the server would have cached: every 2 s of the video.
    static func scrubTimes(duration: Double) -> [Double] {
        guard duration.isFinite, duration > 0 else { return [] }
        let count = Int(duration / scrubFrameInterval)
        return (0..<count).map { Double($0) * scrubFrameInterval }
    }

    /// A JPEG of the frame at `time`. Exact frames have no tolerance; others
    /// may come from the nearest keyframe within 1 s, as server frames do.
    nonisolated static func jpegFrame(
        from url: URL,
        at time: Double,
        exact: Bool,
        maximumSize: CGSize?,
        quality: CGFloat
    ) async throws -> (data: Data, width: Int, height: Int) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        if let maximumSize {
            generator.maximumSize = maximumSize
        }
        let tolerance = exact ? CMTime.zero : CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let (image, _) = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
        guard let data = UIImage(cgImage: image).jpegData(compressionQuality: quality) else {
            throw DemoHTTPError(status: 500, reason: "Failed to encode the frame")
        }
        return (data, image.width, image.height)
    }
}

// MARK: - Scrub route bodies (server-only types on macOS)

nonisolated struct DemoCachedTimes: Codable, Sendable {
    let times: [Double]
    let cachedCount: Int
    let totalFrames: Int
    let duration: Double
}

nonisolated struct DemoGenerationStatus: Codable, Sendable {
    let status: String
    let videoId: String
}

nonisolated struct DemoGlobalGenerationStatus: Codable, Sendable {
    let status: String
    let count: Int
}

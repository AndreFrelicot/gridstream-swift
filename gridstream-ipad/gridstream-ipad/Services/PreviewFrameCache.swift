//
//  PreviewFrameCache.swift
//  gridstream-ipad
//

import CoreMedia
import Foundation
import ImageIO
import OSLog

/// A cache service for storing preview frame CGImages indexed by video URL and time position.
/// Uses NSCache for automatic memory management and eviction under memory pressure.
@Observable
final class PreviewFrameCache {

    /// Shared singleton instance
    static let shared = PreviewFrameCache()

    /// Underlying cache storage using NSCache for automatic memory management
    private let cache: NSCache<NSString, CGImage>

    /// Memory allocation: 400MB for iPad (approximately 1778 frames at 320x180 RGBA, ~59 min at 2s intervals)
    private static let totalCostLimit = 400 * 1024 * 1024

    /// Tracks cached frame times per video for UI visualization
    private var cachedTimesPerVideo: [String: Set<Double>] = [:]

    /// Video file ID for each stream URL (token stripped), so a frame is
    /// recorded under the video it was taken from, whichever tile is scrubbing.
    private var videoIdByURL: [URL: String] = [:]

    /// Merged ranges per video, rebuilt only after that video's times change
    /// (not re-sorted on every frame).
    @ObservationIgnored private var cachedRangesMemo: [String: [ClosedRange<Double>]] = [:]

    init() {
        cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = Self.totalCostLimit
        AppLogger.video.debug("PreviewFrameCache initialized with \(Self.totalCostLimit / 1024 / 1024)MB limit")
    }

    // MARK: - Public API

    /// Stores a preview frame in the cache for a given video URL and time position.
    /// - Parameters:
    ///   - frame: The CGImage to cache
    ///   - url: The video URL used as part of the cache key
    ///   - time: The CMTime position in the video
    func setFrame(_ frame: CGImage, forURL url: URL, atTime time: CMTime) {
        let key = Self.cacheKey(forURL: url, atTime: time) as NSString
        let cost = estimatedCost(for: frame)
        cache.setObject(frame, forKey: key, cost: cost)

        if let videoId = videoIdByURL[VideoURLBuilder.removingToken(from: url)] {
            let roundedTime = Self.roundToNearestTenth(time.seconds)
            if cachedTimesPerVideo[videoId, default: []].insert(roundedTime).inserted {
                cachedRangesMemo[videoId] = nil
            }
        }
    }

    /// Associates a stream URL with its video file ID for range tracking.
    /// - Parameters:
    ///   - id: The video file ID
    ///   - url: The video URL used in cache keys
    func registerVideo(id: String, url: URL) {
        videoIdByURL[VideoURLBuilder.removingToken(from: url)] = id
    }

    /// Ranges of cached frames for a video (for slider visualization).
    func cachedRanges(forVideoId videoId: String) -> [ClosedRange<Double>] {
        if let memo = cachedRangesMemo[videoId] {
            return memo
        }
        let ranges = mergeTimesIntoRanges((cachedTimesPerVideo[videoId] ?? []).sorted())
        cachedRangesMemo[videoId] = ranges
        return ranges
    }

    /// Clears cached time tracking for a specific video.
    func clearCachedTimes(for videoId: String) {
        cachedTimesPerVideo.removeValue(forKey: videoId)
        cachedRangesMemo[videoId] = nil
    }

    /// Updates cached times from server response (bulk update).
    /// - Parameters:
    ///   - videoId: The video file ID
    ///   - times: Array of cached timestamps from server
    func updateFromServerTimes(videoId: String, times: [Double]) {
        cachedTimesPerVideo[videoId] = Set(times)
        cachedRangesMemo[videoId] = nil
    }

    /// Retrieves a cached preview frame for a given video URL and time position.
    /// - Parameters:
    ///   - url: The video URL used as part of the cache key
    ///   - time: The CMTime position in the video
    /// - Returns: The cached CGImage if available, nil otherwise
    func frame(forURL url: URL, atTime time: CMTime) -> CGImage? {
        let key = Self.cacheKey(forURL: url, atTime: time) as NSString
        return cache.object(forKey: key)
    }

    /// Preloads all frames for a video from the server into NSCache.
    /// - Parameters:
    ///   - times: Array of timestamps to preload
    ///   - videoURL: The video URL for cache key generation
    ///   - serverURL: The server base URL
    ///   - videoId: The video file ID
    /// - Returns: Number of frames successfully preloaded
    @discardableResult
    func preloadAllFrames(
        times: [Double],
        videoURL: URL,
        serverURL: URL,
        videoId: String
    ) async -> Int {
        var loadedCount = 0

        for time in times {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            let key = Self.cacheKey(forURL: videoURL, atTime: cmTime) as NSString

            // Skip if already in cache
            if cache.object(forKey: key) != nil {
                continue
            }

            // Fetch from server
            guard let frameURL = VideoURLBuilder.buildScrubFrameURL(from: serverURL, videoId: videoId, time: time) else {
                AppLogger.video.warning("Failed to build scrub frame URL")
                continue
            }

            do {
                let (data, response) = try await ServerSessionManager.shared.urlSession.data(from: frameURL)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else { continue }

                // Decode image data (handles JPEG and HEIF)
                guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                    continue
                }

                // Store in cache
                let cost = estimatedCost(for: cgImage)
                cache.setObject(cgImage, forKey: key, cost: cost)
                loadedCount += 1

                // Small delay to avoid overwhelming the network
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            } catch {
                AppLogger.video.debug("Failed to preload frame at \(time): \(error.localizedDescription)")
            }
        }

        AppLogger.video.info("Preloaded \(loadedCount) frames for \(videoId)")
        return loadedCount
    }

    // MARK: - Cache Key Generation

    /// Generates a consistent cache key from a video URL and time position.
    /// Time is rounded to the nearest 0.1 seconds for cache hit optimization.
    /// - Parameters:
    ///   - url: The video URL
    ///   - time: The CMTime position
    /// - Returns: A string suitable for use as a cache key
    static func cacheKey(forURL url: URL, atTime time: CMTime) -> String {
        let roundedSeconds = roundToNearestTenth(time.seconds)
        // Without the session token, so a re-login keeps the cached frames
        return "\(VideoURLBuilder.removingToken(from: url).absoluteString):\(roundedSeconds)"
    }

    // MARK: - Private Helpers

    /// Rounds a time value to the nearest 0.1 seconds for cache key generation.
    /// This improves cache hit rates during scrubbing.
    private static func roundToNearestTenth(_ seconds: Double) -> Double {
        return (seconds * 10).rounded() / 10
    }

    /// Estimates the memory cost of a CGImage for NSCache cost tracking.
    private func estimatedCost(for image: CGImage) -> Int {
        return image.bytesPerRow * image.height
    }

    /// Merges sorted times into contiguous ranges for UI display.
    /// Uses frame interval (5s) plus tolerance for merging adjacent frames.
    /// Extends ranges to fill visually: first range starts at 0, last extends by one interval.
    private func mergeTimesIntoRanges(_ times: [Double]) -> [ClosedRange<Double>] {
        guard !times.isEmpty else { return [] }

        // Frame interval from server (2 seconds) plus tolerance for floating point variance
        let frameInterval: Double = 2.0
        let mergeTolerance: Double = frameInterval + 0.5

        var ranges: [ClosedRange<Double>] = []
        var rangeStart = times[0]
        var rangeEnd = times[0]

        for time in times.dropFirst() {
            if time - rangeEnd <= mergeTolerance {
                rangeEnd = time
            } else {
                ranges.append(rangeStart...rangeEnd)
                rangeStart = time
                rangeEnd = time
            }
        }
        ranges.append(rangeStart...rangeEnd)

        // Visual adjustments for better UX:
        // 1. If first range starts near 0 (within one interval), extend to 0
        if !ranges.isEmpty && ranges[0].lowerBound <= frameInterval {
            let first = ranges.removeFirst()
            ranges.insert(0...first.upperBound, at: 0)
        }

        // 2. Extend the last range by one frame interval for visual completeness
        //    This accounts for the fact that frame at time T covers T to T+interval
        if !ranges.isEmpty {
            let last = ranges.removeLast()
            ranges.append(last.lowerBound...(last.upperBound + frameInterval))
        }

        return ranges
    }
}

import Foundation
import GridStreamAPI
import Vapor

nonisolated struct ScrubRoutes: RouteCollection {
    enum Mode {
        case publicRead
        case authenticatedWrite
    }

    private let videos: VideoRepository
    private let mode: Mode

    init(databaseManager: DatabaseManager, mode: Mode = .publicRead) {
        self.videos = VideoRepository(database: databaseManager)
        self.mode = mode
    }

    func boot(routes: RoutesBuilder) throws {
        let api = routes.grouped("api", "v1")
        let videos = api.grouped("videos")

        switch mode {
        case .publicRead:
            videos.get(":id", "scrub", "frame", use: getFrame)
            videos.get(":id", "scrub", "cached-times", use: getCachedTimes)
        case .authenticatedWrite:
            videos.post(":id", "scrub", "generate", use: startGeneration)
            videos.delete(":id", "scrub", "generate", use: stopGeneration)

            let scrub = api.grouped("scrub")
            scrub.post("pause-all", use: pauseAllGeneration)
            scrub.post("resume-all", use: resumeAllGeneration)
            scrub.get("blocked", use: listBlocked)
            videos.post(":id", "scrub", "reset", use: resetScrubFailure)
        }
    }

    @Sendable
    private func getFrame(req: Request) async throws -> Response {
        let fileId = try req.requireFileId()

        guard let time = req.query[Double.self, at: "time"] else {
            throw Abort(.badRequest, reason: "Missing time parameter")
        }

        let exact = req.query[Bool.self, at: "exact"] ?? false

        // Exact frames bypass the cache and force a decode: sessions only
        if exact, req.application.serverAuthManager.authenticatedSession(from: req, allowQueryToken: true) == nil {
            throw Abort(.unauthorized, reason: "Authentication required")
        }

        let duration = try await videos.find(fileId: fileId)?.duration

        guard let duration else {
            throw Abort(.notFound, reason: "Video not found")
        }

        guard Self.isValidFrameTime(time, duration: duration) else {
            throw Abort(.badRequest, reason: "time must be between 0 and the video duration")
        }

        // In exact mode (precision scrubbing), skip cache lookup
        if !exact {
            if let cachedFrame = try await ScrubFrameCache.shared.getFrame(videoId: fileId, time: time) {
                var headers = HTTPHeaders()
                headers.contentType = HTTPMediaType(type: "image", subType: "jpeg")
                headers.add(name: "X-Cache", value: "HIT")
                return Response(status: .ok, headers: headers, body: .init(data: cachedFrame))
            }
        }

        do {
            let frameData = try await ScrubFrameGenerator.shared.generateFrame(videoId: fileId, time: time, exact: exact)

            // In exact mode, skip cache store (precision frames are volatile)
            if !exact {
                try await ScrubFrameCache.shared.storeFrame(videoId: fileId, time: time, data: frameData)
            }

            // New frames are already JPEG, no conversion needed
            var headers = HTTPHeaders()
            headers.contentType = HTTPMediaType(type: "image", subType: "jpeg")
            headers.add(name: "X-Cache", value: exact ? "EXACT" : "MISS")
            return Response(status: .ok, headers: headers, body: .init(data: frameData))
        } catch ScrubFrameError.videoNotFound {
            throw Abort(.notFound, reason: "Video not found")
        } catch {
            throw Abort(.internalServerError, reason: "Failed to generate frame: \(error.localizedDescription)")
        }
    }

    /// `0 ≤ time ≤ duration`, finite. Durations of 0 (unknown) accept any finite non-negative time.
    nonisolated static func isValidFrameTime(_ time: Double, duration: Double) -> Bool {
        guard time.isFinite, time >= 0 else { return false }
        guard duration.isFinite, duration > 0 else { return true }
        return time <= duration
    }

    @Sendable
    private func getCachedTimes(req: Request) async throws -> Response {
        let fileId = try req.requireFileId()
        let videoRecord = try await videos.require(fileId: fileId)

        let cachedTimes = try await ScrubFrameCache.shared.getCachedTimes(videoId: fileId)
        let totalFrames = Int(videoRecord.duration / ScrubFrameGenerator.frameInterval)

        let response = CachedTimesResponse(
            times: cachedTimes,
            cachedCount: cachedTimes.count,
            totalFrames: totalFrames,
            duration: videoRecord.duration
        )

        return try await response.encodeResponse(for: req)
    }

    @Sendable
    private func startGeneration(req: Request) async throws -> Response {
        let fileId = try req.requireFileId()
        _ = try await videos.require(fileId: fileId)

        await BackgroundFrameManager.shared.startGeneration(videoId: fileId)

        let response = GenerationStatusResponse(status: "started", videoId: fileId)
        return try await response.encodeResponse(for: req)
    }

    @Sendable
    private func stopGeneration(req: Request) async throws -> Response {
        let fileId = try req.requireFileId()

        await BackgroundFrameManager.shared.stopGeneration(videoId: fileId)

        let response = GenerationStatusResponse(status: "stopped", videoId: fileId)
        return try await response.encodeResponse(for: req)
    }

    @Sendable
    private func pauseAllGeneration(req: Request) async throws -> Response {
        let pausedCount = await BackgroundFrameManager.shared.pauseAll()
        let response = GlobalGenerationStatusResponse(status: "paused", count: pausedCount)
        return try await response.encodeResponse(for: req)
    }

    @Sendable
    private func resumeAllGeneration(req: Request) async throws -> Response {
        let resumedCount = await BackgroundFrameManager.shared.resumeAll()
        let response = GlobalGenerationStatusResponse(status: "resumed", count: resumedCount)
        return try await response.encodeResponse(for: req)
    }

    @Sendable
    private func listBlocked(req: Request) async throws -> [BlockedVideoResponse] {
        try await videos.scrubBlocked().map { record in
            // Minimal VideoItem so the web player can stream by fileId; the absolute
            // `path` is exposed separately for locating the file on disk.
            let video = VideoItem.api(record: record, sourceDirectory: nil)
            return BlockedVideoResponse(
                video: video,
                path: record.path,
                attemptCount: record.scrubAttemptCount,
                lastError: record.scrubLastError,
                lastAttemptAt: record.scrubLastAttemptAt,
                frameCount: record.scrubFrameCount,
                expectedFrames: Int(record.duration / ScrubFrameGenerator.frameInterval)
            )
        }
    }

    @Sendable
    private func resetScrubFailure(req: Request) async throws -> Response {
        let fileId = try req.requireFileId()
        try await videos.resetScrubFailure(fileId: fileId)
        let response = GenerationStatusResponse(status: "reset", videoId: fileId)
        return try await response.encodeResponse(for: req)
    }
}

nonisolated struct CachedTimesResponse: Content {
    let times: [Double]
    let cachedCount: Int
    let totalFrames: Int
    let duration: Double
}

nonisolated struct GenerationStatusResponse: Content {
    let status: String
    let videoId: String
}

nonisolated struct GlobalGenerationStatusResponse: Content {
    let status: String
    let count: Int
}

nonisolated struct BlockedVideoResponse: Content {
    let video: VideoItem
    let path: String
    let attemptCount: Int
    let lastError: String?
    let lastAttemptAt: Double?
    let frameCount: Int
    let expectedFrames: Int
}

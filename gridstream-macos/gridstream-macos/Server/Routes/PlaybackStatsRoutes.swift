import Foundation
import GridStreamAPI
import OSLog
import Vapor

nonisolated struct PlaybackStatsRoutes: RouteCollection {
    private let logger = Logger(subsystem: "com.gridstream.macos", category: "PlaybackStatsRoutes")
    private let videos: VideoRepository

    init(databaseManager: DatabaseManager) {
        self.videos = VideoRepository(database: databaseManager)
    }

    func boot(routes: RoutesBuilder) throws {
        let api = routes.grouped("api", "v1")
        let videos = api.grouped("videos")

        videos.post(":id", "playback-stats", use: updatePlaybackStats)
    }

    // MARK: - POST /api/v1/videos/:id/playback-stats

    /// Applies a playback report with targeted, overflow-safe column updates.
    /// `addViewTime` is clamped to 0…86_400 seconds per report.
    @Sendable
    private func updatePlaybackStats(req: Request) async throws -> PlaybackStatsDTO {
        let fileId = try req.requireFileId()

        let statsRequest = try req.content.decode(PlaybackStatsRequest.self)
        logger.info("updatePlaybackStats: fileId=\(fileId), incrementPlayCount=\(statsRequest.incrementPlayCount), addViewTime=\(statsRequest.addViewTime)")

        let stats = try await videos.applyPlaybackReport(
            fileId: fileId,
            incrementPlayCount: statsRequest.incrementPlayCount,
            addViewTime: statsRequest.addViewTime
        )

        logger.info("updatePlaybackStats: Updated video \(fileId) - playCount=\(stats.playCount), totalViewTime=\(stats.totalViewTime)")

        return PlaybackStatsDTO(playCount: stats.playCount, totalViewTime: stats.totalViewTime)
    }
}

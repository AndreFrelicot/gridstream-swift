import Foundation
import Vapor

nonisolated struct ThumbnailRoutes: RouteCollection {
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
            videos.get(":id", "thumbnail", use: getThumbnail)
        case .authenticatedWrite:
            videos.put(":id", "thumbnail", use: setThumbnail)
        }
    }

    // MARK: - GET /api/v1/videos/:id/thumbnail

    @Sendable
    private func getThumbnail(req: Request) async throws -> Response {
        let fileId = try req.requireFileId()
        let imageData = try await videos.thumbnail(fileId: fileId)

        // JPEG with a long-lived cache: the URL carries the thumbnail version
        var headers = HTTPHeaders()
        headers.contentType = .jpeg
        headers.add(name: "Cache-Control", value: "public, max-age=31536000, immutable")

        return Response(
            status: .ok,
            headers: headers,
            body: .init(data: imageData)
        )
    }

    // MARK: - PUT /api/v1/videos/:id/thumbnail

    struct SetThumbnailRequest: Content, Sendable {
        let time: Double
    }

    struct SetThumbnailResponse: Content, Sendable {
        let updatedAt: Double
    }

    @Sendable
    private func setThumbnail(req: Request) async throws -> SetThumbnailResponse {
        let fileId = try req.requireFileId()
        let body = try req.content.decode(SetThumbnailRequest.self)

        guard body.time >= 0 else {
            throw Abort(.badRequest, reason: "Time must be non-negative")
        }

        let video = try await videos.require(fileId: fileId)

        // Generate thumbnail at the requested time
        guard let imageData = await ThumbnailGenerator().generateThumbnail(
            from: URL(fileURLWithPath: video.path),
            at: body.time
        ) else {
            throw Abort(.internalServerError, reason: "Failed to generate thumbnail at requested time")
        }

        // The thumbnail and the catalog version change in one transaction
        let updatedAt = try await videos.saveThumbnail(imageData, fileId: fileId)
        return SetThumbnailResponse(updatedAt: updatedAt)
    }
}

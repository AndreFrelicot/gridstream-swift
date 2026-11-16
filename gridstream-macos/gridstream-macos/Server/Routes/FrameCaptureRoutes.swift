import Foundation
import GridStreamAPI
import OSLog
import Vapor

nonisolated struct FrameCaptureRoutes: RouteCollection {
    private let logger = Logger(subsystem: "com.gridstream.macos", category: "FrameCaptureRoutes")
    private let captures: CaptureRepository
    private let videos: VideoRepository

    init(databaseManager: DatabaseManager) {
        let database = databaseManager
        self.captures = CaptureRepository(database: database)
        self.videos = VideoRepository(database: database)
    }

    func boot(routes: RoutesBuilder) throws {
        let api = routes.grouped("api", "v1")

        // Video-scoped capture routes
        let videoCaptures = api.grouped("videos", ":id", "captures")
        videoCaptures.on(.POST, body: .collect(maxSize: "1mb"), use: createCapture)
        videoCaptures.get(use: listCapturesForVideo)

        // Global capture routes
        let captures = api.grouped("captures")
        captures.get(use: listAllCaptures)
        captures.delete(":captureId", use: deleteCapture)
    }

    // MARK: - POST /api/v1/videos/:id/captures

    @Sendable
    private func createCapture(req: Request) async throws -> Response {
        let fileId = try req.requireFileId()
        let createRequest = try req.content.decode(CreateFrameCaptureRequest.self)

        guard createRequest.timestamp >= 0 else {
            throw Abort(.badRequest, reason: "Timestamp must be non-negative")
        }

        let video = try await videos.require(fileId: fileId)

        // Capture frame at full resolution
        let (imageData, width, height) = try await FrameCaptureService()
            .captureFrame(from: URL(fileURLWithPath: video.path), at: createRequest.timestamp)

        let record = FrameCaptureRecord(
            id: UUID().uuidString,
            fileId: fileId,
            timestamp: createRequest.timestamp,
            imageData: imageData,
            width: width,
            height: height,
            fileSize: imageData.count
        )
        try await captures.insert(record)
        logger.info("Created frame capture \(record.id) for video \(fileId) at \(createRequest.timestamp)s")

        let response = Response(status: .created)
        try response.content.encode(FrameCaptureDTO(from: record, filename: video.filename))
        return response
    }

    // MARK: - GET /api/v1/videos/:id/captures

    @Sendable
    private func listCapturesForVideo(req: Request) async throws -> FrameCaptureListResponse {
        let fileId = try req.requireFileId()
        let result = try await captures.captures(ofVideo: fileId)
        let dtos = result.records.map { FrameCaptureDTO(from: $0, filename: result.filename) }
        return FrameCaptureListResponse(captures: dtos, total: dtos.count)
    }

    // MARK: - GET /api/v1/captures

    @Sendable
    private func listAllCaptures(req: Request) async throws -> FrameCaptureListResponse {
        let filterFileId = req.query[String.self, at: "fileId"]
        let criteriaJSON = req.query[String.self, at: "criteria"]
        let pagination = try req.pagination(defaultLimit: 50)
        let criteria = try criteriaJSON.map { try QueryValidation.criteria(json: $0) }

        let page = try await captures.page(fileId: filterFileId, criteria: criteria, pagination: pagination)

        let dtos = page.records.map { FrameCaptureDTO(from: $0, filename: page.filenames[$0.fileId]) }
        return FrameCaptureListResponse(captures: dtos, total: page.total)
    }

    // MARK: - DELETE /api/v1/captures/:captureId

    @Sendable
    private func deleteCapture(req: Request) async throws -> Response {
        let captureId = try req.requireParameter("captureId", reason: "Missing capture ID")
        try await captures.delete(id: captureId)
        logger.info("Deleted frame capture \(captureId)")
        return Response(status: .noContent)
    }
}

nonisolated struct FrameCaptureImageRoutes: RouteCollection {
    private let captures: CaptureRepository

    init(databaseManager: DatabaseManager) {
        self.captures = CaptureRepository(database: databaseManager)
    }

    func boot(routes: RoutesBuilder) throws {
        let api = routes.grouped("api", "v1")
        api.get("captures", ":captureId", "image", use: getCaptureImage)
    }

    // MARK: - GET /api/v1/captures/:captureId/image

    @Sendable
    private func getCaptureImage(req: Request) async throws -> Response {
        let captureId = try req.requireParameter("captureId", reason: "Missing capture ID")
        let capture = try await captures.find(id: captureId)

        var headers = HTTPHeaders()
        headers.contentType = .jpeg
        headers.add(name: "Cache-Control", value: "public, max-age=31536000, immutable")

        return Response(
            status: .ok,
            headers: headers,
            body: .init(data: capture.imageData)
        )
    }
}

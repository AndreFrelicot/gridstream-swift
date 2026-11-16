import Foundation
import GridStreamAPI
import OSLog
import Vapor

nonisolated struct AnnotationRoutes: RouteCollection {
    private let logger = Logger(subsystem: "com.gridstream.macos", category: "AnnotationRoutes")
    private let annotations: AnnotationRepository

    init(databaseManager: DatabaseManager) {
        self.annotations = AnnotationRepository(database: databaseManager)
    }

    func boot(routes: RoutesBuilder) throws {
        let api = routes.grouped("api", "v1")
        let annotations = api.grouped("videos", ":id", "annotations")

        annotations.get(use: listAnnotations)
        annotations.get("times", use: listAnnotationTimes)
        annotations.on(.PUT, body: .collect(maxSize: "5mb"), use: upsertAnnotation)
        annotations.delete(":annotationId", use: deleteAnnotation)
    }

    // MARK: - GET /api/v1/videos/:id/annotations

    @Sendable
    private func listAnnotations(req: Request) async throws -> AnnotationListResponse {
        let fileId = try req.requireFileId()
        let dtos = try await annotations.annotations(ofVideo: fileId).map { AnnotationDTO(from: $0) }
        return AnnotationListResponse(annotations: dtos, total: dtos.count)
    }

    // MARK: - GET /api/v1/videos/:id/annotations/times

    @Sendable
    private func listAnnotationTimes(req: Request) async throws -> AnnotationTimesResponse {
        let fileId = try req.requireFileId()
        return AnnotationTimesResponse(times: try await annotations.frameTimes(ofVideo: fileId))
    }

    // MARK: - PUT /api/v1/videos/:id/annotations

    @Sendable
    private func upsertAnnotation(req: Request) async throws -> Response {
        let fileId = try req.requireFileId()
        let upsertRequest = try req.content.decode(UpsertAnnotationRequest.self)

        guard upsertRequest.frameRate > 0 else {
            throw Abort(.badRequest, reason: "Frame rate must be positive")
        }

        let result = try await annotations.upsert(
            fileId: fileId,
            frameTime: upsertRequest.frameTime,
            frameRate: upsertRequest.frameRate,
            strokesJSON: upsertRequest.strokesJSON,
            text: upsertRequest.text.flatMap { $0.isEmpty ? nil : $0 }
        )
        if result.created {
            logger.info("Created annotation \(result.record.id) for video \(fileId) at frame \(upsertRequest.frameTime)")
        } else {
            logger.info("Updated annotation \(result.record.id) for video \(fileId) at frame \(upsertRequest.frameTime)")
        }

        let response = Response(status: .ok)
        try response.content.encode(AnnotationDTO(from: result.record))
        return response
    }

    // MARK: - DELETE /api/v1/videos/:id/annotations/:annotationId

    @Sendable
    private func deleteAnnotation(req: Request) async throws -> Response {
        let fileId = try req.requireFileId()
        let annotationId = try req.requireUUID("annotationId", label: "annotation")

        try await annotations.delete(id: annotationId, ofVideo: fileId)

        logger.info("Deleted annotation \(annotationId) for video \(fileId)")
        return Response(status: .noContent)
    }
}

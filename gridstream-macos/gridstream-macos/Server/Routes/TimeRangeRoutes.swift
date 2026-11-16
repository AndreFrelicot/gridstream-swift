import Foundation
import GridStreamAPI
import OSLog
import Vapor

nonisolated struct TimeRangeRoutes: RouteCollection {
    private let logger = Logger(subsystem: "com.gridstream.macos", category: "TimeRangeRoutes")
    private let timeRanges: TimeRangeRepository

    init(databaseManager: DatabaseManager) {
        self.timeRanges = TimeRangeRepository(database: databaseManager)
    }

    func boot(routes: RoutesBuilder) throws {
        let api = routes.grouped("api", "v1")
        let timeRanges = api.grouped("videos", ":id", "time-ranges")

        timeRanges.get(use: listTimeRanges)
        timeRanges.post(use: createTimeRange)
        timeRanges.put(":rangeId", use: updateTimeRange)
        timeRanges.delete(":rangeId", use: deleteTimeRange)
    }

    // MARK: - GET /api/v1/videos/:id/time-ranges

    @Sendable
    private func listTimeRanges(req: Request) async throws -> TimeRangeListResponse {
        let fileId = try req.requireFileId()
        let dtos = try await timeRanges.ranges(ofVideo: fileId).map { TimeRangeDTO(from: $0) }
        return TimeRangeListResponse(timeRanges: dtos, total: dtos.count)
    }

    // MARK: - POST /api/v1/videos/:id/time-ranges

    @Sendable
    private func createTimeRange(req: Request) async throws -> Response {
        let fileId = try req.requireFileId()
        let createRequest = try req.content.decode(CreateTimeRangeRequest.self)
        try Self.validate(createRequest)

        let record = try await timeRanges.create(TimeRangeRecord(
            videoFileId: fileId,
            startTime: createRequest.startTime,
            endTime: createRequest.endTime,
            label: createRequest.label
        ))

        logger.info("Created time range \(record.id) for video \(fileId): \(createRequest.startTime)-\(createRequest.endTime)")

        let response = Response(status: .created)
        try response.content.encode(TimeRangeDTO(from: record))
        return response
    }

    // MARK: - PUT /api/v1/videos/:id/time-ranges/:rangeId

    @Sendable
    private func updateTimeRange(req: Request) async throws -> Response {
        let fileId = try req.requireFileId()
        let rangeId = try req.requireUUID("rangeId", label: "range")
        let updateRequest = try req.content.decode(CreateTimeRangeRequest.self)
        try Self.validate(updateRequest)

        let record = try await timeRanges.update(
            id: rangeId,
            ofVideo: fileId,
            startTime: updateRequest.startTime,
            endTime: updateRequest.endTime,
            label: updateRequest.label
        )

        logger.info("Updated time range \(rangeId) for video \(fileId): \(updateRequest.startTime)-\(updateRequest.endTime)")

        let response = Response(status: .ok)
        try response.content.encode(TimeRangeDTO(from: record))
        return response
    }

    // MARK: - DELETE /api/v1/videos/:id/time-ranges/:rangeId

    @Sendable
    private func deleteTimeRange(req: Request) async throws -> Response {
        let fileId = try req.requireFileId()
        let rangeId = try req.requireUUID("rangeId", label: "range")

        try await timeRanges.delete(id: rangeId, ofVideo: fileId)

        logger.info("Deleted time range \(rangeId) for video \(fileId)")
        return Response(status: .noContent)
    }

    private static func validate(_ request: CreateTimeRangeRequest) throws {
        guard request.startTime < request.endTime else {
            throw Abort(.badRequest, reason: "Start time must be less than end time")
        }
        guard request.startTime >= 0 else {
            throw Abort(.badRequest, reason: "Start time must be non-negative")
        }
    }
}

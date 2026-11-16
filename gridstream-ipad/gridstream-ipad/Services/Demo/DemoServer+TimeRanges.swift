import Foundation
import GridStreamAPI

extension DemoServer {
    func routeTimeRanges(_ request: DemoRequest) throws -> DemoResponse? {
        // Time ranges
        if let params = request.on("GET", "videos/:fileId/time-ranges") {
            let fileId = params[0]
            let ranges = try loadedStore().timeRanges
                .filter { $0.videoFileId == fileId }
                .sorted { $0.startTime < $1.startTime }
            return .json(TimeRangeListResponse(timeRanges: ranges, total: ranges.count))
        }
        if let params = request.on("POST", "videos/:fileId/time-ranges") {
            let fileId = params[0]
            return .json(try createTimeRange(fileId: fileId, try decode(CreateTimeRangeRequest.self, request.body)), status: 201)
        }
        if let params = request.on("PUT", "videos/:fileId/time-ranges/:rangeId") {
            let fileId = params[0]
            let rangeId = params[1]
            return .json(try updateTimeRange(try Self.uuid(rangeId, label: "range"), fileId: fileId, try decode(CreateTimeRangeRequest.self, request.body)))
        }
        if let params = request.on("DELETE", "videos/:fileId/time-ranges/:rangeId") {
            let fileId = params[0]
            let rangeId = params[1]
            try deleteTimeRange(try Self.uuid(rangeId, label: "range"), fileId: fileId)
            return .empty(204)
        }
        return nil
    }

    // MARK: - Time ranges

    private func createTimeRange(fileId: String, _ request: CreateTimeRangeRequest) throws -> TimeRangeDTO {
        try Self.validate(request)
        return try write { store in
            _ = try requireVideo(fileId, in: store)
            let now = Date()
            let range = TimeRangeDTO(
                id: UUID(), videoFileId: fileId, startTime: request.startTime, endTime: request.endTime,
                label: request.label, createdAt: now, updatedAt: now
            )
            store.timeRanges.append(range)
            return range
        }
    }

    private func updateTimeRange(_ id: UUID, fileId: String, _ request: CreateTimeRangeRequest) throws -> TimeRangeDTO {
        try Self.validate(request)
        return try write { store in
            guard let index = store.timeRanges.firstIndex(where: { $0.id == id && $0.videoFileId == fileId }) else {
                throw DemoHTTPError.notFound("Time range not found")
            }
            let existing = store.timeRanges[index]
            let updated = TimeRangeDTO(
                id: id, videoFileId: fileId, startTime: request.startTime, endTime: request.endTime,
                label: request.label ?? existing.label, createdAt: existing.createdAt, updatedAt: Date()
            )
            store.timeRanges[index] = updated
            return updated
        }
    }

    private func deleteTimeRange(_ id: UUID, fileId: String) throws {
        try write { store in
            guard store.timeRanges.contains(where: { $0.id == id && $0.videoFileId == fileId }) else {
                throw DemoHTTPError.notFound("Time range not found")
            }
            store.timeRanges.removeAll { $0.id == id }
        }
    }

    private static func validate(_ request: CreateTimeRangeRequest) throws {
        guard request.startTime < request.endTime else {
            throw DemoHTTPError.badRequest("Start time must be less than end time")
        }
        guard request.startTime >= 0 else {
            throw DemoHTTPError.badRequest("Start time must be non-negative")
        }
    }
}

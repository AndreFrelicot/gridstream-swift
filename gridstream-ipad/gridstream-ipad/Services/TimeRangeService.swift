import Foundation
import GridStreamAPI
import OSLog

@MainActor
final class TimeRangeService {
    private let sessionManager: ServerSessionManager

    init(sessionManager: ServerSessionManager? = nil) {
        self.sessionManager = sessionManager ?? .shared
    }

    // Explicit teardown avoids the isolated-deinit back-deploy shim when
    // SwiftUI releases this service outside a Swift task.
    deinit {}

    private func api(_ serverURL: URL) -> APIClient {
        APIClient(serverURL: serverURL, session: sessionManager)
    }

    // MARK: - Fetch Time Ranges

    func fetchTimeRanges(forFileId fileId: String, serverURL: URL) async throws -> [TimeRangeDTO] {
        try await api(serverURL).fetch(TimeRangeListResponse.self, "videos/\(fileId)/time-ranges").timeRanges
    }

    // MARK: - Create Time Range

    func createTimeRange(
        forFileId fileId: String,
        startTime: Double,
        endTime: Double,
        label: String?,
        serverURL: URL
    ) async throws -> TimeRangeDTO {
        try await api(serverURL).fetch(
            TimeRangeDTO.self, .post, "videos/\(fileId)/time-ranges",
            body: CreateTimeRangeRequest(startTime: startTime, endTime: endTime, label: label),
            expecting: [201]
        )
    }

    // MARK: - Update Time Range

    func updateTimeRange(
        forFileId fileId: String,
        rangeId: UUID,
        startTime: Double,
        endTime: Double,
        serverURL: URL
    ) async throws -> TimeRangeDTO {
        try await api(serverURL).fetch(
            TimeRangeDTO.self, .put, "videos/\(fileId)/time-ranges/\(rangeId.uuidString.lowercased())",
            body: CreateTimeRangeRequest(startTime: startTime, endTime: endTime, label: nil)
        )
    }

    // MARK: - Delete Time Range

    func deleteTimeRange(forFileId fileId: String, rangeId: UUID, serverURL: URL) async throws {
        try await api(serverURL).send(
            .delete, "videos/\(fileId)/time-ranges/\(rangeId.uuidString.lowercased())", expecting: [204]
        )
    }
}

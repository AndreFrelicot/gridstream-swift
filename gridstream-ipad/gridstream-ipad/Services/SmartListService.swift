//
//  SmartListService.swift
//  gridstream-ipad
//

import Foundation
import GridStreamAPI
import OSLog

/// Service for managing Smart Lists via the server API.
/// Provides methods for CRUD operations and preview count functionality.
@MainActor
final class SmartListService {
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

    // MARK: - Fetch Smart Lists

    /// Fetches all smart lists from the server.
    /// - Parameter serverURL: The base server URL
    /// - Returns: Array of SmartListInfo
    func fetchSmartLists(from serverURL: URL) async throws -> [SmartListInfo] {
        let smartListsResponse = try await api(serverURL).fetch(SLSmartListsResponse.self, "smart-lists")
        return smartListsResponse.smartLists.elements.compactMap { dto in
            convertDTOToSmartListInfo(dto)
        }
    }

    /// Fetches a single smart list by ID from the server.
    /// - Parameters:
    ///   - id: The UUID of the smart list
    ///   - serverURL: The base server URL
    /// - Returns: SmartListInfo if found, nil otherwise
    func fetchSmartList(id: UUID, from serverURL: URL) async throws -> SmartListInfo? {
        guard let dto = try await api(serverURL).fetchIfPresent(SmartListDTO.self, "smart-lists/\(id.uuidString)") else {
            return nil
        }
        return convertDTOToSmartListInfo(dto)
    }

    // MARK: - Fetch Memberships

    /// Fetches the smart-list membership map (`fileId` -> smart list IDs),
    /// evaluated server-side from each list's criteria.
    /// - Parameter serverURL: The base server URL
    /// - Returns: Map of fileId to the smart list IDs it belongs to
    func fetchMemberships(from serverURL: URL) async throws -> [String: [UUID]] {
        try await api(serverURL).fetch(SmartListMembershipsResponse.self, "smart-lists/memberships").memberships
    }

    // MARK: - Create Smart List

    /// Creates a new smart list on the server.
    /// - Parameters:
    ///   - name: The name of the smart list
    ///   - criteriaJSON: Pre-encoded JSON string of SmartListCriteria (avoids actor boundary issues)
    ///   - serverURL: The base server URL
    /// - Returns: The created SmartListInfo
    func createSmartList(
        name: String,
        criteriaJSON: String,
        serverURL: URL
    ) async throws -> SmartListInfo {
        let dto = try await api(serverURL).fetch(
            SmartListDTO.self, .post, "smart-lists",
            body: CreateSmartListRequest(name: name, criteria: criteriaJSON), expecting: [201]
        )
        guard let smartList = convertDTOToSmartListInfo(dto) else {
            throw APIError.decodingError
        }

        AppLogger.video.info("Created smart list: \(name)")
        return smartList
    }

    // MARK: - Update Smart List

    /// Updates an existing smart list on the server.
    /// - Parameters:
    ///   - id: The UUID of the smart list to update
    ///   - name: The new name (optional, pass current name to keep unchanged)
    ///   - criteriaJSON: Pre-encoded JSON string of SmartListCriteria (optional, avoids actor boundary issues)
    ///   - serverURL: The base server URL
    /// - Returns: The updated SmartListInfo
    func updateSmartList(
        id: UUID,
        name: String?,
        criteriaJSON: String?,
        serverURL: URL
    ) async throws -> SmartListInfo {
        let dto = try await api(serverURL).fetch(
            SmartListDTO.self, .put, "smart-lists/\(id.uuidString)",
            body: UpdateSmartListRequest(name: name, criteria: criteriaJSON)
        )
        guard let smartList = convertDTOToSmartListInfo(dto) else {
            throw APIError.decodingError
        }

        AppLogger.video.info("Updated smart list: \(smartList.name)")
        return smartList
    }

    // MARK: - Delete Smart List

    /// Deletes a smart list from the server.
    /// - Parameters:
    ///   - id: The UUID of the smart list to delete
    ///   - serverURL: The base server URL
    func deleteSmartList(id: UUID, serverURL: URL) async throws {
        try await api(serverURL).send(.delete, "smart-lists/\(id.uuidString)")
        AppLogger.video.info("Deleted smart list: \(id.uuidString)")
    }

    // MARK: - Preview Count

    /// Gets the count of videos matching the given criteria.
    /// Used to preview how many videos a smart list will match before saving.
    /// - Parameters:
    ///   - queryParams: Pre-built query parameters as simple strings (avoids actor boundary issues)
    ///   - serverURL: The base server URL
    /// - Returns: The count of matching videos
    func previewCount(queryParams: [String: String], serverURL: URL) async throws -> Int {
        // Convert dictionary to query items - no complex types involved
        var queryItems: [URLQueryItem] = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }

        // Only get count, not full results
        queryItems.append(URLQueryItem(name: "limit", value: "1"))
        queryItems.append(URLQueryItem(name: "offset", value: "0"))

        let videosResponse = try await api(serverURL).fetch(SLVideosCountResponse.self, "videos", query: queryItems)

        let count = videosResponse.total ?? videosResponse.videos.count
        AppLogger.video.debug("Smart List preview count result: \(count)")

        return count
    }

    // MARK: - Private Helpers

    /// Converts a server DTO to SmartListInfo
    private func convertDTOToSmartListInfo(_ dto: SmartListDTO) -> SmartListInfo? {
        guard let criteriaData = dto.criteria.data(using: .utf8) else {
            return nil
        }

        do {
            let criteria = try JSONDecoder.gridStream().decode(SmartListCriteria.self, from: criteriaData)
            return SmartListInfo(
                id: dto.id,
                name: dto.name,
                criteria: criteria,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt
            )
        } catch {
            AppLogger.video.error("Failed to decode smart list criteria: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Request/Response Models

/// Response model for the smart lists endpoint
/// Lossy: one list the client cannot decode never hides the others.
private struct SLSmartListsResponse: Decodable, Sendable {
    let smartLists: LossyArray<SmartListDTO>
}

/// Response for counting videos
private struct SLVideosCountResponse: Codable, Sendable {
    let videos: [SLVideoStub]
    let total: Int?

    struct SLVideoStub: Codable, Sendable {
        let id: String?
    }
}


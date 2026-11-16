//
//  SimpleListService.swift
//  gridstream-ipad
//

import Foundation
import GridStreamAPI
import OSLog

@MainActor
final class SimpleListService {
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

    // MARK: - Fetch Simple Lists

    func fetchSimpleLists(from serverURL: URL) async throws -> [SimpleListDTO] {
        try await api(serverURL).fetch(LossySimpleListsResponse.self, "simple-lists").simpleLists.elements
    }

    func fetchSimpleList(id: UUID, from serverURL: URL) async throws -> SimpleListDTO? {
        try await api(serverURL).fetchIfPresent(SimpleListDTO.self, "simple-lists/\(id.uuidString)")
    }

    // MARK: - Create Simple List

    func createSimpleList(name: String, serverURL: URL) async throws -> SimpleListDTO {
        let simpleList = try await api(serverURL).fetch(
            SimpleListDTO.self, .post, "simple-lists",
            body: CreateSimpleListRequest(name: name), expecting: [201]
        )
        AppLogger.video.info("Created simple list: \(name)")
        return simpleList
    }

    // MARK: - Update Simple List

    func updateSimpleList(
        id: UUID,
        name: String?,
        sortOrder: SimpleListSortOrder?,
        serverURL: URL
    ) async throws -> SimpleListDTO {
        let simpleList = try await api(serverURL).fetch(
            SimpleListDTO.self, .put, "simple-lists/\(id.uuidString)",
            body: UpdateSimpleListRequest(name: name, sortOrder: sortOrder?.rawValue)
        )
        AppLogger.video.info("Updated simple list: \(simpleList.name)")
        return simpleList
    }

    // MARK: - Delete Simple List

    func deleteSimpleList(id: UUID, serverURL: URL) async throws {
        try await api(serverURL).send(.delete, "simple-lists/\(id.uuidString)")
        AppLogger.video.info("Deleted simple list: \(id.uuidString)")
    }

    // MARK: - Add Videos to List

    func addVideosToList(videoIds: [String], listId: UUID, serverURL: URL) async throws -> SimpleListDTO {
        let simpleList = try await api(serverURL).fetch(
            SimpleListDTO.self, .post, "simple-lists/\(listId.uuidString)/videos",
            body: AddVideosRequest(videoIds: videoIds)
        )
        AppLogger.video.info("Added \(videoIds.count) video(s) to simple list \(listId.uuidString)")
        return simpleList
    }

    // MARK: - Pick Random Video from List

    /// Picks a random video ID from a simple list
    /// - Parameters:
    ///   - simpleListId: The UUID of the simple list
    ///   - simpleLists: Cached list of SimpleListDTO to find video IDs
    /// - Returns: A random video ID from the list, or nil if the list is empty
    func pickRandomVideoFromSimpleList(
        simpleListId: UUID,
        simpleLists: [SimpleListDTO]
    ) -> String? {
        guard let simpleList = simpleLists.first(where: { $0.id == simpleListId }),
              !simpleList.videoIds.isEmpty else {
            return nil
        }
        return simpleList.videoIds.randomElement()
    }
}

// MARK: - Request/Response Models

/// Lossy: one list the client cannot decode never hides the others.
private struct LossySimpleListsResponse: Decodable, Sendable {
    let simpleLists: LossyArray<SimpleListDTO>
}

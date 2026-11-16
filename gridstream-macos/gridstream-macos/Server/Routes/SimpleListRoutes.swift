import Foundation
import GridStreamAPI
import Vapor

nonisolated struct SimpleListRoutes: RouteCollection {
    private let simpleLists: SimpleListRepository

    init(databaseManager: DatabaseManager) {
        self.simpleLists = SimpleListRepository(database: databaseManager)
    }

    func boot(routes: RoutesBuilder) throws {
        let api = routes.grouped("api", "v1")
        let simpleLists = api.grouped("simple-lists")

        simpleLists.get(use: listSimpleLists)
        simpleLists.post(use: createSimpleList)
        simpleLists.get(":id", use: getSimpleList)
        simpleLists.put(":id", use: updateSimpleList)
        simpleLists.delete(":id", use: deleteSimpleList)

        simpleLists.post(":id", "videos", use: addVideosToList)
        simpleLists.delete(":id", "videos", ":videoId", use: removeVideoFromList)
    }

    // MARK: - GET /api/v1/simple-lists

    @Sendable
    private func listSimpleLists(req: Request) async throws -> SimpleListsResponse {
        let lists = try await simpleLists.all()
        return SimpleListsResponse(simpleLists: lists.map(SimpleListDTO.init))
    }

    // MARK: - POST /api/v1/simple-lists

    @Sendable
    private func createSimpleList(req: Request) async throws -> Response {
        let createRequest = try req.content.decode(CreateSimpleListRequest.self)
        let name = try Self.normalizedName(createRequest.name)
        let sortOrder = try Self.canonicalSortOrder(createRequest.sortOrder ?? SimpleListSortOrder.defaultValue)

        let list = try await simpleLists.create(name: name, displayName: createRequest.name, sortOrder: sortOrder)

        let response = Response(status: .created)
        try response.content.encode(SimpleListDTO(from: list, videoIds: []))
        return response
    }

    // MARK: - GET /api/v1/simple-lists/:id

    @Sendable
    private func getSimpleList(req: Request) async throws -> SimpleListDTO {
        let id = try req.requireUUID("id", label: "simple list")
        return SimpleListDTO(try await simpleLists.find(id: id))
    }

    // MARK: - PUT /api/v1/simple-lists/:id

    @Sendable
    private func updateSimpleList(req: Request) async throws -> SimpleListDTO {
        let id = try req.requireUUID("id", label: "simple list")
        let updateRequest = try req.content.decode(UpdateSimpleListRequest.self)
        let name = try updateRequest.name.map(Self.normalizedName)
        let sortOrder = try updateRequest.sortOrder.map(Self.canonicalSortOrder)

        let list = try await simpleLists.update(id: id, name: name, displayName: updateRequest.name, sortOrder: sortOrder)
        return SimpleListDTO(list)
    }

    /// Maps a client sortOrder to its canonical snake_case value; unknown → 400.
    static func canonicalSortOrder(_ value: String) throws -> String {
        guard let canonical = SimpleListSortOrder.canonical(value) else {
            throw Abort(.badRequest, reason: "Invalid sortOrder '\(value)'. Must be one of: \(SimpleListSortOrder.canonicalValues.joined(separator: ", "))")
        }
        return canonical
    }

    /// Trimmed, lowercased list name; empty → 400.
    private static func normalizedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Abort(.badRequest, reason: "Simple list name cannot be empty.")
        }
        return trimmed.lowercased()
    }

    // MARK: - DELETE /api/v1/simple-lists/:id

    @Sendable
    private func deleteSimpleList(req: Request) async throws -> SimpleListDeleteResponse {
        let id = try req.requireUUID("id", label: "simple list")
        let list = try await simpleLists.delete(id: id)
        return SimpleListDeleteResponse(success: true, message: "Simple list '\(list.name)' deleted successfully")
    }

    // MARK: - POST /api/v1/simple-lists/:id/videos

    @Sendable
    private func addVideosToList(req: Request) async throws -> SimpleListDTO {
        let id = try req.requireUUID("id", label: "simple list")
        let addRequest = try req.content.decode(AddVideosRequest.self)
        return SimpleListDTO(try await simpleLists.addVideos(addRequest.videoIds, toList: id))
    }

    // MARK: - DELETE /api/v1/simple-lists/:id/videos/:videoId

    @Sendable
    private func removeVideoFromList(req: Request) async throws -> SimpleListDTO {
        let id = try req.requireUUID("id", label: "simple list")
        let videoId = try req.requireParameter("videoId", reason: "Video ID is required")
        return SimpleListDTO(try await simpleLists.removeVideo(videoId, fromList: id))
    }
}

nonisolated extension SimpleListDTO {
    init(_ list: SimpleListWithVideos) {
        self.init(from: list.list, videoIds: list.videoFileIds)
    }
}

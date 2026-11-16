import Foundation
import GridStreamAPI
import Vapor

nonisolated struct SmartListRoutes: RouteCollection {
    private let smartLists: SmartListRepository

    init(databaseManager: DatabaseManager) {
        self.smartLists = SmartListRepository(database: databaseManager)
    }

    func boot(routes: RoutesBuilder) throws {
        let api = routes.grouped("api", "v1")
        let smartLists = api.grouped("smart-lists")

        smartLists.get(use: listSmartLists)
        smartLists.get("memberships", use: listSmartListMemberships)
        smartLists.post(use: createSmartList)
        smartLists.get(":id", use: getSmartList)
        smartLists.put(":id", use: updateSmartList)
        smartLists.delete(":id", use: deleteSmartList)
    }

    // MARK: - GET /api/v1/smart-lists

    @Sendable
    private func listSmartLists(req: Request) async throws -> SmartListsResponse {
        SmartListsResponse(smartLists: try await smartLists.all().map { SmartListDTO(from: $0) })
    }

    // MARK: - GET /api/v1/smart-lists/memberships

    @Sendable
    private func listSmartListMemberships(req: Request) async throws -> SmartListMembershipsResponse {
        SmartListMembershipsResponse(memberships: try await smartLists.memberships())
    }

    // MARK: - POST /api/v1/smart-lists

    @Sendable
    private func createSmartList(req: Request) async throws -> Response {
        let createRequest = try req.content.decode(CreateSmartListRequest.self)
        let name = try Self.normalizedName(createRequest.name)
        let criteria = try Self.canonicalCriteria(createRequest.criteria)

        let smartList = try await smartLists.create(name: name, displayName: createRequest.name, criteria: criteria)

        let response = Response(status: .created)
        try response.content.encode(SmartListDTO(from: smartList))
        return response
    }

    // MARK: - GET /api/v1/smart-lists/:id

    @Sendable
    private func getSmartList(req: Request) async throws -> SmartListDTO {
        let smartListId = try req.requireUUID("id", label: "smart list")
        return SmartListDTO(from: try await smartLists.find(id: smartListId))
    }

    // MARK: - PUT /api/v1/smart-lists/:id

    @Sendable
    private func updateSmartList(req: Request) async throws -> SmartListDTO {
        let smartListId = try req.requireUUID("id", label: "smart list")
        let updateRequest = try req.content.decode(UpdateSmartListRequest.self)
        let name = try updateRequest.name.map(Self.normalizedName)
        let criteria = try updateRequest.criteria.map(Self.canonicalCriteria)

        let smartList = try await smartLists.update(
            id: smartListId,
            name: name,
            displayName: updateRequest.name,
            criteria: criteria
        )
        return SmartListDTO(from: smartList)
    }

    /// Validates client criteria and returns its canonical stored form; invalid → 400.
    static func canonicalCriteria(_ json: String) throws -> String {
        let criteria = try QueryValidation.criteria(json: json)
        return try criteria.canonicalJSON()
    }

    /// Trimmed, lowercased list name; empty → 400.
    private static func normalizedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Abort(.badRequest, reason: "Smart list name cannot be empty.")
        }
        return trimmed.lowercased()
    }

    // MARK: - DELETE /api/v1/smart-lists/:id

    @Sendable
    private func deleteSmartList(req: Request) async throws -> SmartListDeleteResponse {
        let smartListId = try req.requireUUID("id", label: "smart list")
        let smartList = try await smartLists.delete(id: smartListId)
        return SmartListDeleteResponse(
            success: true,
            message: "Smart list '\(smartList.name)' deleted successfully"
        )
    }
}

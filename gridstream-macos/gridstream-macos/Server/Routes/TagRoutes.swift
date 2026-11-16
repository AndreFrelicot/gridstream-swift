import Foundation
import GridStreamAPI
import Vapor

nonisolated struct TagRoutes: RouteCollection {
    private let tags: TagRepository

    init(databaseManager: DatabaseManager) {
        self.tags = TagRepository(database: databaseManager)
    }

    func boot(routes: RoutesBuilder) throws {
        let api = routes.grouped("api", "v1")
        let tags = api.grouped("tags")

        tags.get(use: listTags)
        tags.post(use: createTag)
        tags.get(":id", use: getTag)
        tags.put(":id", use: updateTag)
        tags.delete(":id", use: deleteTag)
    }

    // MARK: - GET /api/v1/tags

    @Sendable
    private func listTags(req: Request) async throws -> TagsResponse {
        let all = try await tags.allWithVideoCounts()
        return TagsResponse(tags: all.map { TagDTO(from: $0.tag, videoCount: $0.videoCount) })
    }

    // MARK: - POST /api/v1/tags

    @Sendable
    private func createTag(req: Request) async throws -> Response {
        let createRequest = try req.content.decode(CreateTagRequest.self)
        try Self.validateColor(createRequest.color)

        let tag = try await tags.create(
            name: createRequest.name.lowercased(),
            displayName: createRequest.name,
            color: createRequest.color,
            description: createRequest.description,
            ratingEnabled: createRequest.ratingEnabled ?? false
        )

        let response = Response(status: .created)
        try response.content.encode(TagDTO(from: tag, videoCount: 0))
        return response
    }

    // MARK: - GET /api/v1/tags/:id

    @Sendable
    private func getTag(req: Request) async throws -> TagDTO {
        let tagId = try req.requireUUID("id", label: "tag")
        let found = try await tags.findWithVideoCount(id: tagId)
        return TagDTO(from: found.tag, videoCount: found.videoCount)
    }

    // MARK: - PUT /api/v1/tags/:id

    @Sendable
    private func updateTag(req: Request) async throws -> TagDTO {
        let tagId = try req.requireUUID("id", label: "tag")
        let updateRequest = try req.content.decode(UpdateTagRequest.self)
        if let color = updateRequest.color {
            try Self.validateColor(color)
        }

        let updated = try await tags.update(id: tagId, changes: TagChanges(
            name: updateRequest.name,
            color: updateRequest.color,
            description: updateRequest.description,
            ratingEnabled: updateRequest.ratingEnabled
        ))
        return TagDTO(from: updated.tag, videoCount: updated.videoCount)
    }

    // MARK: - DELETE /api/v1/tags/:id

    @Sendable
    private func deleteTag(req: Request) async throws -> TagDeleteResponse {
        let tagId = try req.requireUUID("id", label: "tag")
        let deleted = try await tags.delete(id: tagId)
        return TagDeleteResponse(
            success: true,
            message: "Tag '\(deleted.tag.name)' deleted successfully",
            affectedVideoCount: deleted.affectedVideoCount
        )
    }

    private static func validateColor(_ color: String) throws {
        guard TagColorPalette.isValidColor(color) else {
            throw Abort(.badRequest, reason: "Invalid color. Must be one of: \(TagColorPalette.allColors.joined(separator: ", "))")
        }
    }
}

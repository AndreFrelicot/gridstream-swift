import Foundation
import GridStreamAPI
import Vapor

nonisolated struct VideoTagRoutes: RouteCollection {
    /// Maximum number of videos accepted by `POST /tags/apply`.
    static let maxBulkFileIds = 10_000

    private let tags: TagRepository

    init(databaseManager: DatabaseManager) {
        self.tags = TagRepository(database: databaseManager)
    }

    func boot(routes: RoutesBuilder) throws {
        let api = routes.grouped("api", "v1")

        // Video tag endpoints
        let videos = api.grouped("videos")
        videos.get(":id", "tags", use: getVideoTags)
        videos.post(":id", "tags", use: applyTagsToVideo)
        videos.post(":id", "tags", ":tagId", use: attachTagToVideo)
        videos.delete(":id", "tags", ":tagId", use: removeTagFromVideo)

        // Bulk add/remove tags across many videos
        api.post("tags", "apply", use: applyTagsInBulk)

        // Source directory bulk tag endpoint
        let sourceDirectories = api.grouped("source-directories")
        sourceDirectories.post(":id", "tags", use: bulkApplyTagsToSourceDirectory)
    }

    // MARK: - GET /api/v1/videos/:id/tags

    @Sendable
    private func getVideoTags(req: Request) async throws -> VideoTagsResponse {
        let fileId = try req.requireFileId()
        return VideoTagsResponse(tags: try await tags.tags(ofVideo: fileId))
    }

    // MARK: - POST /api/v1/videos/:id/tags

    /// Replaces the video's tag set.
    @Sendable
    private func applyTagsToVideo(req: Request) async throws -> VideoTagsResponse {
        let fileId = try req.requireFileId()
        let applyRequest = try req.content.decode(ApplyTagsRequest.self)
        return VideoTagsResponse(tags: try await tags.replaceTags(ofVideo: fileId, with: applyRequest.tagIds))
    }

    // MARK: - POST /api/v1/videos/:id/tags/:tagId

    /// Idempotent single-tag attach; returns the video's full tag list.
    @Sendable
    private func attachTagToVideo(req: Request) async throws -> VideoTagsResponse {
        let fileId = try req.requireFileId()
        let tagId = try req.requireUUID("tagId", label: "tag")
        return VideoTagsResponse(tags: try await tags.attachTag(tagId, toVideo: fileId))
    }

    // MARK: - POST /api/v1/tags/apply

    /// Adds and removes tags on many videos in one transaction with a single
    /// catalog-version bump. Unknown fileIds or tagIds → 400.
    @Sendable
    private func applyTagsInBulk(req: Request) async throws -> BulkTagApplyResponse {
        let applyRequest = try req.content.decode(BulkTagApplyRequest.self)
        let fileIds = Array(Set(applyRequest.fileIds))
        let addTagIds = Set(applyRequest.addTagIds ?? [])
        let removeTagIds = Set(applyRequest.removeTagIds ?? [])

        guard fileIds.count <= Self.maxBulkFileIds else {
            throw Abort(.badRequest, reason: "At most \(Self.maxBulkFileIds) fileIds per request")
        }
        guard addTagIds.isDisjoint(with: removeTagIds) else {
            throw Abort(.badRequest, reason: "A tag cannot be both added and removed")
        }

        let updated = try await tags.applyInBulk(fileIds: fileIds, add: addTagIds, remove: removeTagIds)
        return BulkTagApplyResponse(updated: updated)
    }

    // MARK: - DELETE /api/v1/videos/:id/tags/:tagId

    @Sendable
    private func removeTagFromVideo(req: Request) async throws -> Response {
        let fileId = try req.requireFileId()
        let tagId = try req.requireUUID("tagId", label: "tag")
        try await tags.detachTag(tagId, fromVideo: fileId)
        return Response(status: .noContent)
    }

    // MARK: - POST /api/v1/source-directories/:id/tags

    @Sendable
    private func bulkApplyTagsToSourceDirectory(req: Request) async throws -> BulkApplyTagsResponse {
        let sourceDirectoryId = try req.requireUUID("id", label: "source directory")
        let applyRequest = try req.content.decode(ApplyTagsRequest.self)

        let result = try await tags.addTags(applyRequest.tagIds, toSourceDirectory: sourceDirectoryId)

        return BulkApplyTagsResponse(
            success: true,
            message: "Tags applied successfully",
            videosAffected: result.affected,
            totalVideosInDirectory: result.total
        )
    }
}

// MARK: - Request/Response Models

nonisolated struct BulkApplyTagsResponse: Content, Sendable {
    let success: Bool
    let message: String
    let videosAffected: Int
    let totalVideosInDirectory: Int
}

import Foundation
import GridStreamAPI
import OSLog
import Vapor

nonisolated struct RatingRoutes: RouteCollection {
    private let logger = Logger(subsystem: "com.gridstream.macos", category: "RatingRoutes")
    private let videos: VideoRepository
    private let tags: TagRepository

    init(databaseManager: DatabaseManager) {
        let database = databaseManager
        self.videos = VideoRepository(database: database)
        self.tags = TagRepository(database: database)
    }

    func boot(routes: RoutesBuilder) throws {
        let api = routes.grouped("api", "v1")

        // Global video rating endpoints
        let videos = api.grouped("videos")
        videos.get(":id", "rating", use: getVideoRating)
        videos.put(":id", "rating", use: setVideoRating)

        // Per-tag rating endpoints
        videos.get(":id", "tags", ":tagId", "rating", use: getPerTagRating)
        videos.put(":id", "tags", ":tagId", "rating", use: setPerTagRating)

        // Bulk rating endpoints for source directories
        let sourceDirectories = api.grouped("source-directories")
        sourceDirectories.post(":id", "ratings", use: bulkSetRating)
        sourceDirectories.post(":id", "tag-ratings", use: bulkSetTagRating)
    }

    // MARK: - GET /api/v1/videos/:id/rating

    @Sendable
    private func getVideoRating(req: Request) async throws -> RatingDTO {
        let fileId = try req.requireFileId()
        return RatingDTO(rating: try await videos.require(fileId: fileId).rating)
    }

    // MARK: - PUT /api/v1/videos/:id/rating

    @Sendable
    private func setVideoRating(req: Request) async throws -> RatingDTO {
        let fileId = try req.requireFileId()
        let ratingRequest = try req.content.decode(RatingRequest.self)
        logger.info("setVideoRating: Setting rating \(ratingRequest.rating) for fileId: \(fileId)")

        guard Self.isValid(ratingRequest.rating) else {
            logger.error("setVideoRating: Invalid rating \(ratingRequest.rating)")
            throw Self.invalidRating
        }

        try await videos.setRating(ratingRequest.rating, fileId: fileId)

        logger.info("setVideoRating: Updated rating to \(ratingRequest.rating) for fileId: \(fileId)")
        return RatingDTO(rating: ratingRequest.rating)
    }

    // MARK: - GET /api/v1/videos/:id/tags/:tagId/rating

    @Sendable
    private func getPerTagRating(req: Request) async throws -> RatingDTO {
        let fileId = try req.requireFileId()
        let tagId = try req.requireUUID("tagId", label: "tag")
        return RatingDTO(rating: try await tags.rating(ofTag: tagId, onVideo: fileId))
    }

    // MARK: - PUT /api/v1/videos/:id/tags/:tagId/rating

    @Sendable
    private func setPerTagRating(req: Request) async throws -> RatingDTO {
        let fileId = try req.requireFileId()
        let tagId = try req.requireUUID("tagId", label: "tag")
        let ratingRequest = try req.content.decode(RatingRequest.self)

        guard Self.isValid(ratingRequest.rating) else {
            throw Self.invalidRating
        }

        try await tags.setRating(ratingRequest.rating, ofTag: tagId, onVideo: fileId)
        return RatingDTO(rating: ratingRequest.rating)
    }

    // MARK: - POST /api/v1/source-directories/:id/ratings

    @Sendable
    private func bulkSetRating(req: Request) async throws -> BulkRatingDTO {
        let sourceDirectoryId = try req.requireUUID("id", label: "source directory")
        let ratingRequest = try req.content.decode(RatingRequest.self)

        guard Self.isValid(ratingRequest.rating) else {
            throw Self.invalidRating
        }

        let videosAffected = try await videos.setRating(ratingRequest.rating, inSourceDirectory: sourceDirectoryId)

        return BulkRatingDTO(
            success: true,
            message: "Rating applied successfully",
            videosAffected: videosAffected
        )
    }

    // MARK: - POST /api/v1/source-directories/:id/tag-ratings

    @Sendable
    private func bulkSetTagRating(req: Request) async throws -> BulkRatingDTO {
        let sourceDirectoryId = try req.requireUUID("id", label: "source directory")
        let tagRatingRequest = try req.content.decode(TagRatingRequest.self)

        guard Self.isValid(tagRatingRequest.rating) else {
            throw Self.invalidRating
        }

        let associationsAffected = try await tags.setRating(
            tagRatingRequest.rating,
            ofTag: tagRatingRequest.tagId,
            inSourceDirectory: sourceDirectoryId
        )

        return BulkRatingDTO(
            success: true,
            message: "Tag rating applied successfully",
            videosAffected: associationsAffected
        )
    }

    private static func isValid(_ rating: Int) -> Bool {
        (0...10).contains(rating)
    }

    private static let invalidRating = Abort(.badRequest, reason: "Rating must be between 0 and 10")
}

// MARK: - Request/Response Models

nonisolated struct TagRatingRequest: Content, Sendable {
    let tagId: UUID
    let rating: Int
}

nonisolated struct BulkRatingDTO: Content, Sendable {
    let success: Bool
    let message: String
    let videosAffected: Int
}

import Foundation
import Vapor

/// Validated `limit`/`offset` of a paginated list request.
nonisolated struct Pagination: Equatable, Sendable {
    let limit: Int
    let offset: Int
}

/// Path and query parameter parsing shared by the route collections. Every
/// helper throws `Abort(.badRequest)` with the reason the API has always used.
nonisolated extension Request {
    /// The stable `fileId` from the `:id` segment of video-scoped routes.
    func requireFileId() throws -> String {
        try requireParameter("id", reason: "Missing file ID")
    }

    /// A non-empty path parameter; 400 with `reason` when it is missing or empty.
    func requireParameter(_ name: String, reason: String) throws -> String {
        guard let value = parameters.get(name), !value.isEmpty else {
            throw Abort(.badRequest, reason: reason)
        }
        return value
    }

    /// A UUID path parameter; 400 "Invalid <label> ID format" otherwise.
    func requireUUID(_ name: String, label: String) throws -> UUID {
        guard let value = parameters.get(name), let uuid = UUID(uuidString: value) else {
            throw Abort(.badRequest, reason: "Invalid \(label) ID format")
        }
        return uuid
    }

    /// `limit` clamped to 1…10_000 (default `defaultLimit`), negative `offset` → 400.
    func pagination(defaultLimit: Int) throws -> Pagination {
        Pagination(
            limit: QueryValidation.limit(query[Int.self, at: "limit"], default: defaultLimit),
            offset: try QueryValidation.offset(query[Int.self, at: "offset"])
        )
    }

    /// The application's video catalog snapshot provider.
    func catalogProvider() throws -> VideoCatalogProvider {
        guard let catalog = application.storage[VideoCatalogStorageKey.self] else {
            throw Abort(.internalServerError, reason: "Video catalog not configured")
        }
        return catalog
    }
}

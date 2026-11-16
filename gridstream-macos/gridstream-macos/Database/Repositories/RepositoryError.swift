import Vapor

/// Errors raised by repositories for missing or conflicting rows. They conform
/// to `AbortError`, so routes let them propagate and Vapor renders the same
/// status and reason the API has always returned.
nonisolated enum RepositoryError: AbortError, Equatable {
    /// 404 with `reason`.
    case notFound(String)
    /// 400 with `reason` (duplicate names, limits, unknown referenced rows).
    case invalid(String)

    var status: HTTPResponseStatus {
        switch self {
        case .notFound: .notFound
        case .invalid: .badRequest
        }
    }

    var reason: String {
        switch self {
        case .notFound(let reason), .invalid(let reason): reason
        }
    }
}

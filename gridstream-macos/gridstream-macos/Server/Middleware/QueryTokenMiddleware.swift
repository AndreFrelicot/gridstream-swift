import Foundation
import Vapor

/// Removes the `token` query item from the request URL before anything can
/// log it (Vapor's ErrorMiddleware logs the full URL) and keeps it in request
/// storage for `SessionAuthMiddleware(allowQueryToken: true)`.
nonisolated struct QueryTokenMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        if let query = request.url.query, query.contains(ServerAuthManager.queryTokenName) {
            var token: String?
            let kept = query.split(separator: "&", omittingEmptySubsequences: false).filter { item in
                let parts = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.first.map(String.init) == ServerAuthManager.queryTokenName else { return true }
                if token == nil, parts.count == 2 {
                    token = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                }
                return false
            }
            if let token {
                request.storage[QueryTokenStorageKey.self] = token
            }
            request.url.query = kept.isEmpty ? nil : kept.joined(separator: "&")
        }

        return try await next.respond(to: request)
    }
}

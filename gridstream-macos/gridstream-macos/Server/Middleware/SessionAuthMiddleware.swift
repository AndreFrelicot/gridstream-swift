import Foundation
import Vapor

nonisolated struct SessionAuthMiddleware: AsyncMiddleware {
    /// Media routes also accept the `token` query item (AVPlayer/AsyncImage
    /// cannot set headers); metadata routes do not.
    var allowQueryToken = false

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard request.application.serverAuthManager.authenticatedSession(
            from: request,
            allowQueryToken: allowQueryToken
        ) != nil else {
            throw Abort(.unauthorized, reason: "Authentication required")
        }

        return try await next.respond(to: request)
    }
}

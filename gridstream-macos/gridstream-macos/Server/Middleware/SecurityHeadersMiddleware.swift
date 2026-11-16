import Foundation
import Vapor

/// Adds security headers to every response, and a Content-Security-Policy to
/// HTML documents (the web app shell).
nonisolated struct SecurityHeadersMiddleware: AsyncMiddleware {
    static let contentSecurityPolicy = [
        "default-src 'self'",
        "img-src 'self' data: blob:",
        "media-src 'self' blob:",
        "style-src 'self' 'unsafe-inline'",
        "script-src 'self'",
        "connect-src 'self'",
        "frame-ancestors 'none'",
        "base-uri 'self'",
    ].joined(separator: "; ")

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let response = try await next.respond(to: request)
        response.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
        response.headers.replaceOrAdd(name: "Referrer-Policy", value: "no-referrer")
        response.headers.replaceOrAdd(name: "X-Frame-Options", value: "DENY")
        if response.headers.contentType?.subType == "html" {
            response.headers.replaceOrAdd(name: "Content-Security-Policy", value: Self.contentSecurityPolicy)
        }
        return response
    }
}

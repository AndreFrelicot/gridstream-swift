import Vapor

/// Middleware that catches 404 responses on non-API, extensionless paths
/// and serves `index.html` instead, enabling Angular client-side routing.
nonisolated struct SPAFallbackMiddleware: AsyncMiddleware {
    let publicDirectory: String

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        do {
            let response = try await next.respond(to: request)

            // Only intercept 404s
            guard response.status == .notFound else {
                return response
            }

            // Don't intercept API routes — real API 404s should pass through
            guard !request.url.path.hasPrefix("/api/") else {
                return response
            }

            // Don't intercept requests for files with extensions (e.g. .js, .css, .png)
            let lastComponent = request.url.path.split(separator: "/").last.map(String.init) ?? ""
            if lastComponent.contains(".") {
                return response
            }

            // Serve index.html for SPA client-side routes
            let indexPath = publicDirectory + "browser/index.html"
            return try await request.fileio.asyncStreamFile(at: indexPath)
        } catch let error as AbortError where error.status == .notFound {
            // Also handle thrown 404 abort errors for non-API extensionless paths
            guard !request.url.path.hasPrefix("/api/") else {
                throw error
            }

            let lastComponent = request.url.path.split(separator: "/").last.map(String.init) ?? ""
            if lastComponent.contains(".") {
                throw error
            }

            let indexPath = publicDirectory + "browser/index.html"
            return try await request.fileio.asyncStreamFile(at: indexPath)
        }
    }
}

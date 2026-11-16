import Vapor

/// Serves the Angular web app (static files, then the SPA fallback) while
/// `isEnabled` returns true. It is read on every request, so turning the web
/// UI on or off takes effect without restarting the server.
nonisolated struct WebUIMiddleware: AsyncMiddleware {
    let isEnabled: @Sendable () -> Bool
    private let webApp: [any Middleware]

    /// `publicDirectory` holds the Angular build output; the app itself
    /// (index.html and its assets) is in its `browser/` folder.
    init(publicDirectory: String, isEnabled: @escaping @Sendable () -> Bool) {
        self.isEnabled = isEnabled
        self.webApp = [
            FileMiddleware(publicDirectory: publicDirectory + "browser/"),
            SPAFallbackMiddleware(publicDirectory: publicDirectory),
        ]
    }

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard isEnabled() else {
            return try await next.respond(to: request)
        }
        return try await webApp.makeResponder(chainingTo: next).respond(to: request).get()
    }
}

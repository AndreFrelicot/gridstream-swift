import Foundation
import Vapor

nonisolated struct HealthRoutes: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let api = routes.grouped("api", "v1")
        api.get("health", use: healthCheck)
    }

    @Sendable
    private func healthCheck(req: Request) async throws -> HealthResponse {
        HealthResponse(status: "ok", version: "1.0")
    }
}

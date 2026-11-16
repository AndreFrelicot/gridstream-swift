import Foundation
import GridStreamAPI
import OSLog
import Vapor

nonisolated struct CatalogRoutes: RouteCollection {
    private let logger = Logger(subsystem: "com.gridstream.macos", category: "CatalogRoutes")
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func boot(routes: RoutesBuilder) throws {
        let api = routes.grouped("api", "v1")
        let catalog = api.grouped("catalog")

        catalog.get("status", use: getCatalogStatus)
    }

    // MARK: - GET /api/v1/catalog/status

    @Sendable
    private func getCatalogStatus(req: Request) async throws -> CatalogStatusDTO {
        let version = try await databaseManager.fetchCatalogVersion()

        logger.debug("Returning catalog status with version: \(version)")

        return CatalogStatusDTO(version: version)
    }
}

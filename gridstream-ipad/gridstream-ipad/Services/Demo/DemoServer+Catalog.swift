import Foundation
import GridStreamAPI

extension DemoServer {
    func routeCatalog(_ request: DemoRequest) throws -> DemoResponse? {
        if request.on("GET", "health") != nil {
            return .json(["status": "ok", "version": "1.0"])
        }
        if request.on("GET", "auth/session") ?? request.on("POST", "auth/login") ?? request.on("POST", "auth/logout") != nil {
            _ = try loadedStore()
            return .json(AuthSessionResponse(authEnabled: false, authenticated: true, expiresAt: nil, token: nil))
        }
        if request.on("GET", "catalog/status") != nil {
            return .json(CatalogStatusDTO(version: try loadedStore().catalogVersion))
        }
        if request.on("GET", "source-directories") != nil {
            let store = try loadedStore()
            return .json(SourceDirectoriesResponse(directories: [
                SourceDirectoryDTO(id: store.sourceDirectoryId.uuidString, name: store.sourceDirectoryName, path: nil)
            ]))
        }
        return nil
    }
}

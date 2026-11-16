import Foundation

// MARK: - Catalog

/// `GET /api/v1/catalog/status`: bumped on every catalog-affecting write.
public struct CatalogStatusDTO: Codable, Sendable {
    public let version: Int64

    public init(version: Int64) {
        self.version = version
    }
}

// MARK: - Source directories

/// A configured source folder. `id` is a UUID string.
public struct SourceDirectoryDTO: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let path: String?

    public init(id: String, name: String, path: String?) {
        self.id = id
        self.name = name
        self.path = path
    }
}

/// `GET /api/v1/source-directories`.
public struct SourceDirectoriesResponse: Codable, Sendable {
    public let directories: [SourceDirectoryDTO]

    public init(directories: [SourceDirectoryDTO]) {
        self.directories = directories
    }
}

// MARK: - Auth (contract §7)

/// `GET /api/v1/auth/session` and `POST /api/v1/auth/login`.
public struct AuthSessionResponse: Codable, Sendable {
    public let authEnabled: Bool
    public let authenticated: Bool
    public let expiresAt: Date?
    public let token: String?

    public init(authEnabled: Bool, authenticated: Bool, expiresAt: Date?, token: String?) {
        self.authEnabled = authEnabled
        self.authenticated = authenticated
        self.expiresAt = expiresAt
        self.token = token
    }
}

/// Body of `POST /api/v1/auth/login`.
public struct LoginRequest: Codable, Sendable {
    public let pin: String

    public init(pin: String) {
        self.pin = pin
    }
}

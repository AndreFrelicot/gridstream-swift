import Foundation

nonisolated struct ServerConfig: Codable {
    var port: Int
    var sourceDirectories: [SourceDirectory]
    var authEnabled: Bool
    var pinHash: String?
    var pinRevision: Int
    var sessionTTLDays: Int
    var authTokenSecret: String

    init(
        port: Int = 8080,
        sourceDirectories: [SourceDirectory] = [],
        authEnabled: Bool = false,
        pinHash: String? = nil,
        pinRevision: Int = 0,
        sessionTTLDays: Int = 30,
        authTokenSecret: String = UUID().uuidString
    ) {
        self.port = port
        self.sourceDirectories = sourceDirectories
        self.authEnabled = authEnabled
        self.pinHash = pinHash
        self.pinRevision = pinRevision
        self.sessionTTLDays = sessionTTLDays
        self.authTokenSecret = authTokenSecret
    }
}

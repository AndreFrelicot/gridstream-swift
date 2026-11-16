import CryptoKit
import Foundation
import GridStreamAPI
import Vapor

nonisolated struct AuthSessionTokenPayload: Codable, Sendable {
    let exp: TimeInterval
    let revision: Int
    /// Token id, revocable on logout. Absent in tokens minted by older versions.
    var jti: String? = nil
}

/// Key under which `QueryTokenMiddleware` keeps the `token` query item it
/// removed from the request URL.
nonisolated struct QueryTokenStorageKey: StorageKey {
    typealias Value = String
}

nonisolated struct AuthenticatedSession: Sendable {
    let expiresAt: Date
}

// MARK: - Sendable Justification
//
// `ServerAuthManager` holds only an immutable `let store` reference; all
// mutable state lives behind the store's lock. The `@unchecked Sendable`
// is needed because the compiler can't prove that
// `ServerAuthConfigurationStore` is Sendable (it carries `UserDefaults`),
// but the store's own lock guarantees thread safety.
nonisolated final class ServerAuthManager: @unchecked Sendable {
    static let sessionCookieName = "gridstream_session"
    static let queryTokenName = "token"

    private let store: ServerAuthConfigurationStore

    nonisolated init(store: ServerAuthConfigurationStore = .shared) {
        self.store = store
    }

    nonisolated func requiresAuthentication() -> Bool {
        store.load().requiresAuthentication
    }

    nonisolated func sessionStatus(for request: Request) -> AuthSessionResponse {
        let configuration = store.load()

        guard configuration.requiresAuthentication else {
            return AuthSessionResponse(
                authEnabled: false,
                authenticated: true,
                expiresAt: nil,
                token: nil
            )
        }

        guard let session = authenticatedSession(from: request, configuration: configuration) else {
            return AuthSessionResponse(
                authEnabled: true,
                authenticated: false,
                expiresAt: nil,
                token: nil
            )
        }

        return AuthSessionResponse(
            authEnabled: true,
            authenticated: true,
            expiresAt: session.expiresAt,
            token: nil
        )
    }

    nonisolated func login(pin: String, request: Request) async throws -> Response {
        let configuration = store.load()

        guard configuration.requiresAuthentication else {
            let response = Response(status: .ok)
            try response.content.encode(
                AuthSessionResponse(
                    authEnabled: false,
                    authenticated: true,
                    expiresAt: nil,
                    token: nil
                )
            )
            return response
        }

        let limiter = request.application.loginRateLimiter
        let client = Self.clientIdentifier(for: request)
        if let wait = limiter.reserveAttempt(for: client) {
            throw Self.tooManyAttempts(retryAfter: wait)
        }

        var succeeded = false
        defer { limiter.finishAttempt(for: client, succeeded: succeeded) }

        guard let hash = configuration.pinHash else {
            throw Abort(.unauthorized, reason: "Invalid PIN")
        }

        // Bcrypt is deliberately slow: keep it off the event loop and the cooperative pool
        let isValid = try await request.application.threadPool.runIfActive(eventLoop: request.eventLoop) {
            ServerPINSecurity.verify(pin: pin, hash: hash)
        }.get()

        guard isValid else {
            throw Abort(.unauthorized, reason: "Invalid PIN")
        }
        succeeded = true

        let expiresAt = Date().addingTimeInterval(TimeInterval(configuration.sessionTTLDays) * 86_400)
        let token = try signedToken(expiresAt: expiresAt, configuration: configuration)

        let response = Response(status: .ok)
        setSessionCookie(on: response, token: token, expiresAt: expiresAt)
        try response.content.encode(
            AuthSessionResponse(
                authEnabled: true,
                authenticated: true,
                expiresAt: expiresAt,
                token: token
            )
        )
        return response
    }

    /// Clears the session cookie and revokes the presented token (by its jti)
    /// until it expires.
    nonisolated func logoutResponse(for request: Request) -> Response {
        let configuration = store.load()
        if let token = extractToken(from: request, allowQueryToken: false),
           let payload = verifyToken(token, configuration: configuration),
           let tokenId = payload.jti {
            store.revokeTokenId(tokenId, expiresAt: payload.exp)
        }

        let response = Response(status: .ok)
        clearSessionCookie(on: response)
        return response
    }

    /// Rate-limit key: the peer address (forwarding headers are not trusted).
    nonisolated static func clientIdentifier(for request: Request) -> String {
        request.remoteAddress?.ipAddress ?? "unknown"
    }

    nonisolated static func tooManyAttempts(retryAfter wait: TimeInterval) -> Abort {
        let seconds = max(1, Int(wait.rounded(.up)))
        return Abort(
            .tooManyRequests,
            headers: ["Retry-After": String(seconds)],
            reason: "Too many login attempts. Try again in \(seconds) s."
        )
    }

    /// The request's session. `allowQueryToken` additionally accepts the
    /// `token` query item (media routes used by AVPlayer/AsyncImage).
    nonisolated func authenticatedSession(from request: Request, allowQueryToken: Bool = false) -> AuthenticatedSession? {
        authenticatedSession(from: request, configuration: store.load(), allowQueryToken: allowQueryToken)
    }

    private nonisolated func authenticatedSession(
        from request: Request,
        configuration: ServerAuthConfiguration,
        allowQueryToken: Bool = false
    ) -> AuthenticatedSession? {
        guard configuration.requiresAuthentication else {
            return AuthenticatedSession(expiresAt: .distantFuture)
        }

        guard let token = extractToken(from: request, allowQueryToken: allowQueryToken),
              let payload = verifyToken(token, configuration: configuration) else {
            return nil
        }

        return AuthenticatedSession(expiresAt: Date(timeIntervalSince1970: payload.exp))
    }

    private nonisolated func signedToken(expiresAt: Date, configuration: ServerAuthConfiguration) throws -> String {
        let payload = AuthSessionTokenPayload(
            exp: expiresAt.timeIntervalSince1970,
            revision: configuration.pinRevision,
            jti: UUID().uuidString
        )
        let payloadData = try JSONEncoder().encode(payload)
        let secret = SymmetricKey(data: Data(configuration.tokenSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: payloadData, using: secret)

        return "\(base64URLEncode(payloadData)).\(base64URLEncode(Data(signature)))"
    }

    private nonisolated func verifyToken(
        _ token: String,
        configuration: ServerAuthConfiguration
    ) -> AuthSessionTokenPayload? {
        let parts = token.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let payloadData = base64URLDecode(parts[0]),
              let signatureData = base64URLDecode(parts[1]) else {
            return nil
        }

        let secret = SymmetricKey(data: Data(configuration.tokenSecret.utf8))
        guard HMAC<SHA256>.isValidAuthenticationCode(signatureData, authenticating: payloadData, using: secret) else {
            return nil
        }

        guard let payload = try? JSONDecoder().decode(AuthSessionTokenPayload.self, from: payloadData) else {
            return nil
        }

        guard payload.revision == configuration.pinRevision,
              Date(timeIntervalSince1970: payload.exp) > Date() else {
            return nil
        }

        if let tokenId = payload.jti, store.isTokenIdRevoked(tokenId) {
            return nil
        }

        return payload
    }

    private nonisolated func extractToken(from request: Request, allowQueryToken: Bool) -> String? {
        if let authorization = request.headers.bearerAuthorization {
            return authorization.token
        }

        if let cookie = request.cookies[Self.sessionCookieName]?.string, !cookie.isEmpty {
            return cookie
        }

        guard allowQueryToken else { return nil }
        // QueryTokenMiddleware moves the query item into storage so it is never logged
        return request.storage[QueryTokenStorageKey.self]
            ?? request.query[String.self, at: Self.queryTokenName]
    }

    private nonisolated func setSessionCookie(on response: Response, token: String, expiresAt: Date) {
        var cookie = HTTPCookies.Value(string: token)
        cookie.isHTTPOnly = true
        cookie.sameSite = .strict
        cookie.expires = expiresAt
        cookie.path = "/"
        response.cookies[Self.sessionCookieName] = cookie
    }

    private nonisolated func clearSessionCookie(on response: Response) {
        var cookie = HTTPCookies.Value(string: "")
        cookie.isHTTPOnly = true
        cookie.sameSite = .strict
        cookie.expires = Date(timeIntervalSince1970: 0)
        cookie.maxAge = 0
        cookie.path = "/"
        response.cookies[Self.sessionCookieName] = cookie
    }

    private nonisolated func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private nonisolated func base64URLDecode(_ string: String) -> Data? {
        let padding = (4 - string.count % 4) % 4
        let padded = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: padding)
        return Data(base64Encoded: padded)
    }
}

private nonisolated struct ServerAuthManagerStorageKey: StorageKey {
    typealias Value = ServerAuthManager
}

nonisolated extension Application {
    nonisolated var serverAuthManager: ServerAuthManager {
        get {
            if let manager = storage[ServerAuthManagerStorageKey.self] {
                return manager
            }

            let manager = ServerAuthManager()
            storage[ServerAuthManagerStorageKey.self] = manager
            return manager
        }
        set {
            storage[ServerAuthManagerStorageKey.self] = newValue
        }
    }
}

import Foundation
import GridStreamAPI
import OSLog
import Security

@Observable
@MainActor
final class ServerSessionManager {
    static let shared = ServerSessionManager()

    enum State: Sendable, Equatable {
        case checking
        case locked
        case authenticated
        case cachedAuthenticated
    }

    private(set) var state: State = .checking
    private(set) var authEnabled = false
    private(set) var errorMessage: String?
    private(set) var currentServerURL: URL?
    /// Set when the server rate-limits PIN attempts (HTTP 429): the PIN UI
    /// must not allow another attempt before this date.
    private(set) var loginRetryAfter: Date?
    /// Bumped whenever a new session token is stored, so media URLs that
    /// embed the token (stream URLs held by tiles) can be rebuilt.
    private(set) var tokenRevision = 0

    /// True when authenticated requests may be sent (fresh or cached session).
    /// Pollers and catalog fetches must stay idle while this is false.
    var isAuthorized: Bool {
        state == .authenticated || state == .cachedAuthenticated
    }

    /// Called when a request carrying the *current* token comes back 401,
    /// after the session state has been reset to `.locked`. Wired from the
    /// app so discovery can re-probe — a session can expire because the
    /// server restarted with a fresh PIN. Never called when the session was
    /// already locked or when the request carried no (or a stale) token.
    var onSessionExpired: (@MainActor (URL) -> Void)?

    /// Dedicated session for all API traffic (contract §7): ephemeral, no
    /// cookie storage, so the server's session cookie never ends up on disk
    /// and the Keychain token is the only credential.
    let urlSession: URLSession

    private let decoder = JSONDecoder.gridStream()
    private let encoder = JSONEncoder()
    private let keychainService: String
    private let requestTimeout: TimeInterval = 8
    /// In-memory mirror of the Keychain, keyed by account. `.some(nil)`
    /// caches a miss. Never persisted.
    private var tokenCache: [String: String?] = [:]

    init(
        urlSession: URLSession = ServerSessionManager.makeAPISession(),
        keychainService: String = "com.gridstream.ipad.server-session"
    ) {
        self.urlSession = urlSession
        self.keychainService = keychainService
    }

    /// Builds the cookie-less API session. `protocolClasses` lets tests
    /// inject a `URLProtocol` stub. `DemoURLProtocol` is always installed: it
    /// only answers the demo host.
    nonisolated static func makeAPISession(protocolClasses: [AnyClass]? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.protocolClasses = (protocolClasses ?? []) + [DemoURLProtocol.self] + (configuration.protocolClasses ?? [])
        return URLSession(configuration: configuration)
    }

    // MARK: - Session lifecycle

    func refreshSession(for serverURL: URL) async {
        let previousState = state
        let previousAuthEnabled = authEnabled
        let hasStoredToken = token(for: serverURL) != nil

        currentServerURL = serverURL
        if previousState != .authenticated && previousState != .cachedAuthenticated {
            state = .checking
        }
        errorMessage = nil

        do {
            let request = buildAuthenticatedRequest(
                url: serverURL.appendingPathComponent("api/v1/auth/session"),
                method: "GET",
                serverURL: serverURL
            )
            let sentToken = Self.bearerToken(in: request)

            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                preserveAuthenticatedStateIfPossible(
                    previousState: previousState,
                    previousAuthEnabled: previousAuthEnabled,
                    hasStoredToken: hasStoredToken,
                    allowStoredTokenFallback: false,
                    fallbackMessage: String(localized: "Unable to verify the current session.")
                )
                return
            }

            let session = try decoder.decode(AuthSessionResponse.self, from: data)
            authEnabled = session.authEnabled

            if session.authenticated {
                state = .authenticated
            } else if !session.authEnabled {
                clearToken(for: serverURL)
                state = .authenticated
            } else {
                // Only drop the token the server just rejected; a login that
                // completed while this check was in flight stored a new one.
                if let sentToken, sentToken == token(for: serverURL) {
                    clearToken(for: serverURL)
                }
                if token(for: serverURL) == nil {
                    state = .locked
                }
            }
        } catch {
            preserveAuthenticatedStateIfPossible(
                previousState: previousState,
                previousAuthEnabled: previousAuthEnabled,
                hasStoredToken: hasStoredToken,
                allowStoredTokenFallback: true,
                fallbackMessage: String(localized: "Unable to reach the server.")
            )
        }
    }

    private func preserveAuthenticatedStateIfPossible(
        previousState: State,
        previousAuthEnabled: Bool,
        hasStoredToken: Bool,
        allowStoredTokenFallback: Bool,
        fallbackMessage: String
    ) {
        if previousState == .authenticated {
            state = .authenticated
            authEnabled = previousAuthEnabled
            errorMessage = nil
        } else if previousState == .cachedAuthenticated {
            state = .cachedAuthenticated
            authEnabled = previousAuthEnabled
            errorMessage = fallbackMessage
        } else if allowStoredTokenFallback && hasStoredToken {
            state = .cachedAuthenticated
            authEnabled = true
            errorMessage = fallbackMessage
        } else {
            state = .locked
            authEnabled = true
            errorMessage = fallbackMessage
        }
    }

    func login(pin: String, serverURL: URL) async -> Bool {
        if let retryAfter = loginRetryAfter, retryAfter > Date() {
            return false
        }

        currentServerURL = serverURL
        errorMessage = nil
        loginRetryAfter = nil

        let url = serverURL.appendingPathComponent("api/v1/auth/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? encoder.encode(LoginRequest(pin: pin))

        let data: Data
        let httpResponse: HTTPURLResponse
        do {
            let (responseData, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                failLogin(String(localized: "Unexpected response from the server."))
                return false
            }
            data = responseData
            httpResponse = http
        } catch {
            // Network failure: the PIN was never checked, so don't call it
            // wrong — and keep any state we had.
            failLogin(String(localized: "Can't reach the server. Check the connection and try again."))
            return false
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            failLogin(String(localized: "Incorrect PIN."))
            return false
        case 429:
            let seconds = Self.retryAfterSeconds(from: httpResponse) ?? 30
            loginRetryAfter = Date().addingTimeInterval(seconds)
            failLogin(String(localized: "Too many attempts. Try again in \(Self.formatDelay(seconds))."))
            return false
        default:
            failLogin(String(localized: "The server couldn't check the PIN (HTTP \(httpResponse.statusCode))."))
            return false
        }

        guard let session = try? decoder.decode(AuthSessionResponse.self, from: data) else {
            failLogin(String(localized: "Invalid session response."))
            return false
        }
        authEnabled = session.authEnabled

        if !session.authEnabled {
            clearToken(for: serverURL)
            state = .authenticated
            return true
        }

        guard session.authenticated, let token = session.token, !token.isEmpty else {
            clearToken(for: serverURL)
            failLogin(String(localized: "Invalid session response."))
            return false
        }

        guard storeToken(token, for: serverURL) else {
            // Surface Keychain failure: we can't persist the session
            // token, so the user would silently be re-prompted on
            // restart. Force re-entry now rather than later.
            clearToken(for: serverURL)
            failLogin(String(localized: "Couldn't save the session credentials. Please try again."))
            return false
        }

        state = .authenticated
        return true
    }

    private func failLogin(_ message: String) {
        authEnabled = true
        state = .locked
        errorMessage = message
    }

    func logout() async {
        guard let currentServerURL else {
            state = .locked
            return
        }

        let request = buildAuthenticatedRequest(
            url: currentServerURL.appendingPathComponent("api/v1/auth/logout"),
            method: "POST",
            serverURL: currentServerURL
        )

        _ = try? await urlSession.data(for: request)
        // Cleared even when the server is unreachable: with no cookie jar,
        // the Keychain token is the only credential this device holds.
        clearToken(for: currentServerURL)
        authEnabled = true
        errorMessage = nil
        state = .locked
    }

    // MARK: - Requests

    func buildAuthenticatedRequest(url: URL, method: String, serverURL: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = requestTimeout

        if let token = token(for: serverURL) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    func hasStoredToken(for serverURL: URL) -> Bool {
        token(for: serverURL) != nil
    }

    /// The session token for `serverURL`, if any — used to authorize media
    /// URLs (`token` query item) that AVPlayer/image loaders fetch.
    func sessionToken(for serverURL: URL) -> String? {
        token(for: serverURL)
    }

    func data(for request: URLRequest, serverURL: URL) async throws -> (Data, URLResponse) {
        let sentToken = Self.bearerToken(in: request)
        let result = try await urlSession.data(for: request)

        if let response = result.1 as? HTTPURLResponse, response.statusCode == 401 {
            handleUnauthorized(serverURL: serverURL, sentToken: sentToken)
        }

        return result
    }

    /// Reacts to a 401. A 401 only invalidates the session when the request
    /// carried the token we currently hold; a response to a request sent
    /// before a fresh login (stale or missing token) is ignored.
    func handleUnauthorized(serverURL: URL, sentToken: String?) {
        let currentToken = token(for: serverURL)

        if let sentToken {
            guard sentToken == currentToken else {
                AppLogger.session.info("Ignoring 401 for a request sent with a superseded token")
                return
            }
            clearToken(for: serverURL)
        } else if currentToken != nil {
            // Request predates the login that stored the current token.
            return
        }

        let wasLocked = state == .locked
        currentServerURL = serverURL
        authEnabled = true
        state = .locked

        guard !wasLocked else { return }

        if sentToken != nil {
            errorMessage = String(localized: "Session expired. Enter the PIN again.")
            onSessionExpired?(serverURL)
        } else {
            // We had no session: the server simply requires a PIN now.
            errorMessage = nil
        }
    }

    // MARK: - Helpers

    nonisolated static func bearerToken(in request: URLRequest) -> String? {
        guard let header = request.value(forHTTPHeaderField: "Authorization"),
              header.hasPrefix("Bearer ") else {
            return nil
        }
        return String(header.dropFirst("Bearer ".count))
    }

    nonisolated static func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespaces) else {
            return nil
        }
        if let seconds = TimeInterval(value) {
            return max(0, seconds)
        }
        // HTTP-date form.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: value) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }

    nonisolated static func formatDelay(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        if total < 60 {
            return String(localized: "\(total) s")
        }
        let minutes = (total + 59) / 60
        return String(localized: "\(minutes) min")
    }

    // MARK: - Keychain

    private func token(for serverURL: URL) -> String? {
        let account = account(for: serverURL)
        if let cached = tokenCache[account] {
            return cached
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        let token: String?
        if status == errSecSuccess, let data = item as? Data {
            token = String(data: data, encoding: .utf8)
        } else {
            token = nil
        }
        tokenCache[account] = .some(token)
        return token
    }

    @discardableResult
    func storeToken(_ token: String, for serverURL: URL) -> Bool {
        let account = account(for: serverURL)
        let data = Data(token.utf8)
        tokenCache[account] = nil

        let deleteStatus = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ] as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            AppLogger.session.error("Keychain delete (pre-store) failed: OSStatus \(deleteStatus)")
            return false
        }

        let addStatus = SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ] as CFDictionary, nil)
        if addStatus != errSecSuccess {
            AppLogger.session.error("Keychain add failed: OSStatus \(addStatus)")
            return false
        }
        tokenCache[account] = .some(token)
        tokenRevision += 1
        return true
    }

    @discardableResult
    func clearToken(for serverURL: URL) -> Bool {
        let account = account(for: serverURL)
        tokenCache[account] = .some(nil)
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ] as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            AppLogger.session.error("Keychain delete failed: OSStatus \(status)")
            tokenCache[account] = nil
            return false
        }
        return true
    }

    private func account(for serverURL: URL) -> String {
        Self.serverKey(for: serverURL)
    }

    /// Normalized `scheme://host:port` key, so a token stored for the base
    /// URL is found from any URL on that server.
    nonisolated static func serverKey(for url: URL) -> String {
        guard let scheme = url.scheme, let host = url.host else {
            return url.absoluteString
        }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }
}

import GridStreamAPI
import XCTest
import Vapor
@testable import gridstream_macos

/// Server side of contracts/decisions.md §7.
final class ServerSecurityTests: XCTestCase {
    private var app: Application!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var store: ServerAuthConfigurationStore!
    private var mediaDir: URL!

    private static let pin = "246813"
    private static let fileId = "media_file"
    private static let fileSize = 1000

    override func setUp() async throws {
        var env = try Environment.detect()
        env.arguments = ["vapor", "test"]
        app = try await Application.make(env)
        ServerManager.configureSecurityMiddleware(app)

        defaultsSuiteName = "ServerSecurityTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        store = ServerAuthConfigurationStore(defaults: defaults, secrets: InMemorySecretStore())
        store.save(ServerAuthConfiguration(
            isEnabled: true,
            pinHash: try ServerPINSecurity.hash(pin: Self.pin),
            pinRevision: 1,
            sessionTTLDays: 30,
            tokenSecret: "server-security-tests"
        ))
        app.serverAuthManager = ServerAuthManager(store: store)
        app.loginRateLimiter = LoginRateLimiter()

        // A real file behind the real stream route
        mediaDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ServerSecurityTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: Self.fileSize).write(to: mediaDir.appendingPathComponent("clip.mp4"))
        let sourceDirectory = SourceDirectory(id: UUID(), path: mediaDir.path, isEnabled: true)
        let video = VideoItem(
            fileId: Self.fileId, filename: "clip.mp4", relativePath: "clip.mp4",
            sourceDirectoryId: sourceDirectory.id, duration: 10, width: 1, height: 1,
            codec: "h264", fileSize: Int64(Self.fileSize), lastModified: Date()
        )
        app.storage[VideoCatalogStorageKey.self] = StaticCatalogProvider(videos: [video], sourceDirectories: [sourceDirectory])

        try app.register(collection: AuthRoutes())
        let media = app.grouped(SessionAuthMiddleware(allowQueryToken: true))
        try media.register(collection: VideoStreamRoutes())
        media.get("media-echo") { req in req.url.string }
        let authenticated = app.grouped(SessionAuthMiddleware())
        authenticated.get("protected") { _ in HTTPStatus.ok }
        app.get("public") { _ in HTTPStatus.ok }
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: mediaDir)
        app = nil
        store = nil
        defaults = nil
    }

    // MARK: - Helpers

    private func login(_ pin: String) async throws -> Response {
        try await app.sendRequest(
            .POST, "/api/v1/auth/login",
            headers: ["Content-Type": "application/json"],
            body: ByteBuffer(string: #"{"pin":"\#(pin)"}"#)
        )
    }

    private func token() async throws -> String {
        let response = try await login(Self.pin)
        XCTAssertEqual(response.status, .ok)
        return try XCTUnwrap(try response.content.decode(AuthSessionResponse.self).token)
    }

    private func disableAuth() {
        var configuration = store.load()
        configuration.isEnabled = false
        store.save(configuration)
    }

    // MARK: - PIN rules and default PIN

    func testNewPINsNeedSixDigitsButLegacyPINsStillVerify() throws {
        XCTAssertThrowsError(try ServerPINSecurity.hash(pin: "1234"))
        XCTAssertThrowsError(try ServerPINSecurity.hash(pin: "1234567890123"))
        XCTAssertNoThrow(try ServerPINSecurity.hash(pin: "123456789012"))

        let legacyHash = try Bcrypt.hash("1234")
        XCTAssertTrue(ServerPINSecurity.verify(pin: "1234", hash: legacyHash))
        XCTAssertFalse(ServerPINSecurity.verify(pin: "12a4", hash: legacyHash))
    }

    func testDefaultPINIsGeneratedOnceAndEnablesAuth() throws {
        let suite = "ServerSecurityTests-default-\(UUID().uuidString)"
        let freshDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { freshDefaults.removePersistentDomain(forName: suite) }
        let freshStore = ServerAuthConfigurationStore(defaults: freshDefaults, secrets: InMemorySecretStore())
        XCTAssertFalse(freshStore.load().requiresAuthentication)

        let pin = try XCTUnwrap(try freshStore.ensureDefaultPIN())
        XCTAssertEqual(pin.count, 6)
        XCTAssertTrue(pin.allSatisfy(\.isNumber))

        let configuration = freshStore.load()
        XCTAssertTrue(configuration.requiresAuthentication)
        XCTAssertEqual(configuration.generatedPIN, pin)
        XCTAssertTrue(ServerPINSecurity.verify(pin: pin, hash: try XCTUnwrap(configuration.pinHash)))

        XCTAssertNil(try freshStore.ensureDefaultPIN(), "An existing PIN is never replaced")

        // A PIN chosen by the user is kept even when auth is turned off
        var disabled = configuration
        disabled.isEnabled = false
        freshStore.save(disabled)
        XCTAssertNil(try freshStore.ensureDefaultPIN())
        XCTAssertFalse(freshStore.load().isEnabled)
    }

    // MARK: - Login rate limiting

    func testLoginIsRateLimitedAfterThreeFailures() async throws {
        for _ in 0..<3 {
            let response = try await login("000000")
            XCTAssertEqual(response.status, .unauthorized)
        }

        let limited = try await login(Self.pin)
        XCTAssertEqual(limited.status, .tooManyRequests)
        let retryAfter = try XCTUnwrap(limited.headers.first(name: "Retry-After").flatMap(Int.init))
        XCTAssertGreaterThanOrEqual(retryAfter, 1)
    }

    func testSignInsAreLoggedByTheConnectionMonitor() async throws {
        let monitor = ConnectionMonitor()
        app.connectionMonitor = monitor

        for _ in 0..<3 {
            _ = try await login("000000")
        }
        _ = try await login(Self.pin)
        XCTAssertEqual(monitor.sample().events.map(\.kind), [.wrongPIN, .wrongPIN, .wrongPIN, .signInBlocked])

        app.loginRateLimiter = LoginRateLimiter()
        _ = try await token()
        XCTAssertEqual(monitor.sample().events.map(\.kind), [.connected, .signedIn])
    }

    func testConcurrentReservationsCannotPassTheClientQuota() async {
        let limiter = LoginRateLimiter()
        let now = Date()
        let admitted = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<100 {
                group.addTask { limiter.reserveAttempt(for: "same-client", now: now) == nil }
            }
            var count = 0
            for await allowed in group where allowed { count += 1 }
            return count
        }
        XCTAssertEqual(admitted, LoginRateLimiter.freeFailures)
        // Reservations stay bounded even when bcrypt takes longer than backoff.
        XCTAssertNotNil(limiter.reserveAttempt(for: "same-client", now: now.addingTimeInterval(60)))
    }

    func testConcurrentReservationsCannotPassTheGlobalQuota() async {
        let limiter = LoginRateLimiter()
        let admitted = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for client in 0..<100 {
                group.addTask { limiter.reserveAttempt(for: "client-\(client)") == nil }
            }
            var count = 0
            for await allowed in group where allowed { count += 1 }
            return count
        }
        XCTAssertEqual(admitted, LoginRateLimiter.globalFailureLimit)
    }

    func testSuccessfulReservationsDoNotConsumeFailureQuota() {
        let limiter = LoginRateLimiter()
        for _ in 0..<30 {
            XCTAssertNil(limiter.reserveAttempt(for: "client"))
            limiter.finishAttempt(for: "client", succeeded: true)
        }
        XCTAssertNil(limiter.retryAfter(for: "client"))
    }

    func testRateLimiterBacksOffExponentiallyAndLocksGlobally() {
        let limiter = LoginRateLimiter()
        let start = Date(timeIntervalSince1970: 1_000_000)

        for _ in 0..<2 { limiter.recordFailure(for: "a", now: start) }
        XCTAssertNil(limiter.retryAfter(for: "a", now: start))

        limiter.recordFailure(for: "a", now: start)
        XCTAssertEqual(limiter.retryAfter(for: "a", now: start) ?? 0, 1, accuracy: 0.001)
        limiter.recordFailure(for: "a", now: start)
        XCTAssertEqual(limiter.retryAfter(for: "a", now: start) ?? 0, 2, accuracy: 0.001)
        for _ in 0..<20 { limiter.recordFailure(for: "a", now: start) }
        XCTAssertEqual(limiter.retryAfter(for: "a", now: start) ?? 0, 900, accuracy: 0.001, "Capped at 15 minutes")

        limiter.recordSuccess(for: "a")
        XCTAssertNotNil(limiter.retryAfter(for: "b", now: start), "20 failures in a minute lock everyone")
        XCTAssertNil(limiter.retryAfter(for: "b", now: start.addingTimeInterval(61)))
    }

    // MARK: - Logout revocation

    func testLogoutRevokesTheToken() async throws {
        let token = try await token()
        let bearer: HTTPHeaders = ["Authorization": "Bearer \(token)"]

        let before = try await app.sendRequest(.GET, "/protected", headers: bearer)
        XCTAssertEqual(before.status, .ok)

        let logout = try await app.sendRequest(.POST, "/api/v1/auth/logout", headers: bearer)
        XCTAssertEqual(logout.status, .ok)

        let after = try await app.sendRequest(.GET, "/protected", headers: bearer)
        XCTAssertEqual(after.status, .unauthorized)
    }

    // MARK: - Media routes

    func testMediaRouteRequiresSessionAndAcceptsTokenQueryItem() async throws {
        let anonymous = try await app.sendRequest(.GET, "/api/v1/videos/\(Self.fileId)/stream?stats=client")
        XCTAssertEqual(anonymous.status, .unauthorized)

        let token = try await token()
        let withQuery = try await app.sendRequest(.GET, "/api/v1/videos/\(Self.fileId)/stream?stats=client&token=\(token)")
        XCTAssertEqual(withQuery.status, .ok)

        let withBearer = try await app.sendRequest(
            .GET, "/api/v1/videos/\(Self.fileId)/stream?stats=client",
            headers: ["Authorization": "Bearer \(token)"]
        )
        XCTAssertEqual(withBearer.status, .ok)

        // Metadata routes do not accept the query item
        let metadata = try await app.sendRequest(.GET, "/protected?token=\(token)")
        XCTAssertEqual(metadata.status, .unauthorized)
    }

    func testTokenQueryItemIsRemovedFromTheRequestURL() async throws {
        let token = try await token()
        let response = try await app.sendRequest(.GET, "/media-echo?a=1&token=\(token)&b=2")
        XCTAssertEqual(response.status, .ok)
        let echoed = response.body.string ?? ""
        XCTAssertFalse(echoed.contains(token))
        XCTAssertEqual(echoed, "/media-echo?a=1&b=2")
    }

    // MARK: - Range requests on the real stream route

    func testRangeEndPastFileIsClampedAndStartPastFileIs416() async throws {
        let token = try await token()
        let path = "/api/v1/videos/\(Self.fileId)/stream?stats=client&token=\(token)"

        let clamped = try await app.sendRequest(.GET, path, headers: ["Range": "bytes=900-999999999"])
        XCTAssertEqual(clamped.status, .partialContent)
        XCTAssertEqual(clamped.headers.first(name: .contentRange), "bytes 900-999/1000")

        let unsatisfiable = try await app.sendRequest(.GET, path, headers: ["Range": "bytes=5000-"])
        XCTAssertEqual(unsatisfiable.status, .rangeNotSatisfiable)
        XCTAssertEqual(unsatisfiable.headers.first(name: .contentRange), "bytes */1000")

        let normal = try await app.sendRequest(.GET, path, headers: ["Range": "bytes=0-99"])
        XCTAssertEqual(normal.status, .partialContent)
        XCTAssertEqual(normal.headers.first(name: .contentRange), "bytes 0-99/1000")
    }

    func testRangeNormalization() {
        func normalize(_ value: HTTPHeaders.Range.Value) -> VideoStreamRoutes.RangeNormalization {
            VideoStreamRoutes.normalizedRange(HTTPHeaders.Range(unit: .bytes, ranges: [value]), fileSize: 100)
        }
        XCTAssertEqual(normalize(.within(start: 0, end: 50)), .unchanged)
        XCTAssertEqual(normalize(.within(start: 10, end: 500)),
                       .replaced(HTTPHeaders.Range(unit: .bytes, ranges: [.within(start: 10, end: 99)])))
        XCTAssertEqual(normalize(.within(start: 100, end: 200)), .unsatisfiable)
        XCTAssertEqual(normalize(.start(value: 100)), .unsatisfiable)
        XCTAssertEqual(normalize(.tail(value: 500)),
                       .replaced(HTTPHeaders.Range(unit: .bytes, ranges: [.tail(value: 100)])))
        XCTAssertEqual(normalize(.tail(value: 0)), .unsatisfiable)
    }

    // MARK: - Scrub frame time

    func testScrubFrameTimeValidation() {
        XCTAssertTrue(ScrubRoutes.isValidFrameTime(0, duration: 10))
        XCTAssertTrue(ScrubRoutes.isValidFrameTime(10, duration: 10))
        XCTAssertFalse(ScrubRoutes.isValidFrameTime(-1, duration: 10))
        XCTAssertFalse(ScrubRoutes.isValidFrameTime(10.5, duration: 10))
        XCTAssertFalse(ScrubRoutes.isValidFrameTime(.nan, duration: 10))
        XCTAssertFalse(ScrubRoutes.isValidFrameTime(.infinity, duration: 10))
    }

    // MARK: - Host guard and headers

    func testHostGuardOnlyAppliesWhenAuthIsDisabled() async throws {
        let evil: HTTPHeaders = ["Host": "attacker.example.com"]

        let withAuth = try await app.sendRequest(.GET, "/public", headers: evil)
        XCTAssertEqual(withAuth.status, .ok, "With auth on, sessions protect the data")

        disableAuth()
        let rejected = try await app.sendRequest(.GET, "/public", headers: evil)
        XCTAssertEqual(rejected.status, .forbidden)

        for host in ["192.168.1.20:8080", "[fe80::1]:8080", "localhost:8080", "mozart.local", "Mozart.local:8080"] {
            let allowed = try await app.sendRequest(.GET, "/public", headers: ["Host": host])
            XCTAssertEqual(allowed.status, .ok, host)
        }
    }

    func testHostNameParsing() {
        let guardMiddleware = HostGuardMiddleware(ownHostNames: ["studio-mac"])
        XCTAssertTrue(guardMiddleware.isAllowed(host: "studio-mac:8080"))
        XCTAssertTrue(guardMiddleware.isAllowed(host: "127.0.0.1"))
        XCTAssertTrue(guardMiddleware.isAllowed(host: "[::1]:8080"))
        XCTAssertFalse(guardMiddleware.isAllowed(host: "localhost.attacker.com"))
        XCTAssertFalse(guardMiddleware.isAllowed(host: "192.168.1.20.nip.io"))
    }

    func testSecurityHeadersAreSetOnEveryResponse() async throws {
        let ok = try await app.sendRequest(.GET, "/public")
        XCTAssertEqual(ok.headers.first(name: "X-Content-Type-Options"), "nosniff")
        XCTAssertEqual(ok.headers.first(name: "Referrer-Policy"), "no-referrer")
        XCTAssertEqual(ok.headers.first(name: "X-Frame-Options"), "DENY")
        XCTAssertNil(ok.headers.first(name: "Content-Security-Policy"))

        let unauthorized = try await app.sendRequest(.GET, "/protected")
        XCTAssertEqual(unauthorized.headers.first(name: "X-Frame-Options"), "DENY")

        app.get("page") { _ -> Response in
            var headers = HTTPHeaders()
            headers.contentType = .html
            return Response(status: .ok, headers: headers, body: "<html></html>")
        }
        let html = try await app.sendRequest(.GET, "/page")
        XCTAssertEqual(html.headers.first(name: "Content-Security-Policy"), SecurityHeadersMiddleware.contentSecurityPolicy)
    }
}

private final class StaticCatalogProvider: VideoCatalogProvider, @unchecked Sendable {
    private let videos: [VideoItem]
    private let sourceDirectories: [SourceDirectory]

    init(videos: [VideoItem], sourceDirectories: [SourceDirectory]) {
        self.videos = videos
        self.sourceDirectories = sourceDirectories
    }

    func getVideos() -> [VideoItem] { videos }
    func getSourceDirectories() -> [SourceDirectory] { sourceDirectories }
    func getVideoByFileId(_ fileId: String) -> VideoItem? { videos.first { $0.fileId == fileId } }
}

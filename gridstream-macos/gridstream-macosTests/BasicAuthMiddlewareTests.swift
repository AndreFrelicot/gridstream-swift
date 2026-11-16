import GridStreamAPI
import XCTest
import Vapor
import NIOFoundationCompat
@testable import gridstream_macos

final class BasicAuthMiddlewareTests: XCTestCase {
    private var app: Application!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() async throws {
        var env = try Environment.detect()
        env.arguments = ["vapor", "test"]
        app = try await Application.make(env)
        app.middleware.use(ErrorMiddleware.default(environment: app.environment))

        defaultsSuiteName = "ServerAuthTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        let store = ServerAuthConfigurationStore(defaults: defaults, secrets: InMemorySecretStore())
        store.save(
            ServerAuthConfiguration(
                isEnabled: true,
                pinHash: try ServerPINSecurity.hash(pin: "123456"),
                pinRevision: 1,
                sessionTTLDays: 30,
                tokenSecret: "basic-auth-middleware-tests"
            )
        )

        app.serverAuthManager = ServerAuthManager(store: store)
        try app.register(collection: AuthRoutes())

        let protected = app.grouped(SessionAuthMiddleware())
        protected.get("protected") { _ in
            HTTPStatus.ok
        }
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        app = nil
    }

    func testPinHashValidationWorks() throws {
        let hash = try ServerPINSecurity.hash(pin: "123456")
        XCTAssertTrue(ServerPINSecurity.verify(pin: "123456", hash: hash))
        XCTAssertFalse(ServerPINSecurity.verify(pin: "999999", hash: hash))
    }

    func testInvalidPinFormatIsRejected() {
        XCTAssertThrowsError(try ServerPINSecurity.hash(pin: "12"))
        XCTAssertThrowsError(try ServerPINSecurity.hash(pin: "abcd"))
    }

    func testLoginWithValidPinReturnsBearerToken() async throws {
        let response = try await login(pin: "123456")

        XCTAssertEqual(response.status, .ok)

        let payload = try response.content.decode(AuthSessionResponse.self)
        XCTAssertTrue(payload.authEnabled)
        XCTAssertTrue(payload.authenticated)
        XCTAssertNotNil(payload.token)
    }

    func testLoginWithInvalidPinReturnsUnauthorized() async throws {
        let response = try await login(pin: "000000")
        XCTAssertEqual(response.status, .unauthorized)
    }

    func testProtectedRouteRejectsMissingOrInvalidToken() async throws {
        let noAuthResponse = try await app.sendRequest(.GET, "/protected")
        XCTAssertEqual(noAuthResponse.status, .unauthorized)

        var invalidHeaders = HTTPHeaders()
        invalidHeaders.add(name: .authorization, value: "Bearer invalid")
        let invalidResponse = try await app.sendRequest(.GET, "/protected", headers: invalidHeaders)
        XCTAssertEqual(invalidResponse.status, .unauthorized)
    }

    func testPinRevisionChangeInvalidatesExistingTokens() async throws {
        let loginResponse = try await login(pin: "123456")
        let payload = try loginResponse.content.decode(AuthSessionResponse.self)

        var headers = HTTPHeaders()
        headers.add(name: .authorization, value: "Bearer \(payload.token ?? "")")

        let initialResponse = try await app.sendRequest(.GET, "/protected", headers: headers)
        XCTAssertEqual(initialResponse.status, .ok)

        let store = ServerAuthConfigurationStore(defaults: defaults, secrets: InMemorySecretStore())
        var configuration = store.load()
        configuration.pinRevision += 1
        store.save(configuration)

        let revokedResponse = try await app.sendRequest(.GET, "/protected", headers: headers)
        XCTAssertEqual(revokedResponse.status, .unauthorized)
    }

    private func login(pin: String) async throws -> Response {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        let body = ByteBuffer(data: #"{"pin":"\#(pin)"}"#.data(using: .utf8)!)
        return try await app.sendRequest(.POST, "/api/v1/auth/login", headers: headers, body: body)
    }
}

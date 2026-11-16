import GridStreamAPI
import XCTest
import Vapor
import NIOFoundationCompat
import GRDB
@testable import gridstream_macos

final class CatalogRoutesTests: XCTestCase {

    var testDatabaseURL: URL!
    var databaseManager: DatabaseManager!
    var app: Application!
    var authDefaults: UserDefaults!
    var authDefaultsSuiteName: String!

    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GridStreamCatalogRoutesTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        testDatabaseURL = testDir.appendingPathComponent("test_gridstream.sqlite")
        databaseManager = DatabaseManager(databasePath: testDatabaseURL)
        try await databaseManager.initialize()

        var env = try Environment.detect()
        env.arguments = ["vapor", "test"]
        app = try await Application.make(env)
        app.middleware.use(ErrorMiddleware.default(environment: app.environment))
        authDefaultsSuiteName = "CatalogRoutesTests-\(UUID().uuidString)"
        authDefaults = UserDefaults(suiteName: authDefaultsSuiteName)
        let authStore = ServerAuthConfigurationStore(defaults: authDefaults, secrets: InMemorySecretStore())
        authStore.save(
            ServerAuthConfiguration(
                isEnabled: true,
                pinHash: try ServerPINSecurity.hash(pin: "123456"),
                pinRevision: 1,
                sessionTTLDays: 30,
                tokenSecret: "catalog-test-secret"
            )
        )
        app.serverAuthManager = ServerAuthManager(store: authStore)
        try app.register(collection: AuthRoutes())

        let authenticated = app.grouped(SessionAuthMiddleware())
        try authenticated.register(collection: CatalogRoutes(databaseManager: databaseManager))
    }

    override func tearDown() async throws {
        try await databaseManager.close()
        try await app.asyncShutdown()
        let testDir = testDatabaseURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: testDir)
        if let authDefaults {
            authDefaults.removePersistentDomain(forName: authDefaultsSuiteName)
        }
        databaseManager = nil
        testDatabaseURL = nil
        app = nil
        authDefaults = nil
        authDefaultsSuiteName = nil
    }

    // MARK: - Test Helpers

    private func authHeader() async throws -> HTTPHeaders {
        let body = ByteBuffer(data: #"{"pin":"123456"}"#.data(using: .utf8)!)
        var loginHeaders = HTTPHeaders()
        loginHeaders.add(name: .contentType, value: "application/json")

        let response = try await app.sendRequest(
            .POST,
            "/api/v1/auth/login",
            headers: loginHeaders,
            body: body
        )
        XCTAssertEqual(response.status, .ok)

        let session = try response.content.decode(AuthSessionResponse.self)
        var headers = HTTPHeaders()
        headers.add(name: .authorization, value: "Bearer \(session.token ?? "")")
        return headers
    }

    // MARK: - Test 1: GET /api/v1/catalog/status returns 200 with version

    func testGetCatalogStatusReturns200WithVersion() async throws {
        // Set a known catalog version
        let expectedVersion: Int64 = 1703123456000
        try await databaseManager.updateCatalogVersion(expectedVersion)

        let response = try await app.sendRequest(
            .GET,
            "/api/v1/catalog/status",
            headers: try await authHeader()
        )

        XCTAssertEqual(response.status, .ok)

        let result = try response.content.decode(CatalogStatusDTO.self)
        XCTAssertEqual(result.version, expectedVersion)
    }

    // MARK: - Test 2: Response format is lightweight JSON with version field

    func testResponseFormatIsLightweightJsonWithVersionField() async throws {
        // Set a catalog version
        try await databaseManager.updateCatalogVersion(1609459200000)

        let response = try await app.sendRequest(
            .GET,
            "/api/v1/catalog/status",
            headers: try await authHeader()
        )

        XCTAssertEqual(response.status, .ok)

        // Verify response is valid JSON with expected structure
        let result = try response.content.decode(CatalogStatusDTO.self)
        XCTAssertTrue(result.version > 0)

        // Verify response body is lightweight (small JSON)
        // ByteBuffer's readableBytes gives us the byte count
        let bodySize = response.body.buffer?.readableBytes ?? 0
        // Response should be small (less than 100 bytes for just {"version":...})
        XCTAssertGreaterThan(bodySize, 0)
        XCTAssertLessThan(bodySize, 100)
    }

    // MARK: - Test 3: Endpoint requires session auth

    func testEndpointRequiresSessionAuth() async throws {
        // Request without auth header should fail
        let responseNoAuth = try await app.sendRequest(
            .GET,
            "/api/v1/catalog/status"
        )
        XCTAssertEqual(responseNoAuth.status, .unauthorized)

        // Request with invalid credentials should fail
        var invalidHeaders = HTTPHeaders()
        invalidHeaders.add(name: .authorization, value: "Bearer invalid-token")

        let responseInvalidAuth = try await app.sendRequest(
            .GET,
            "/api/v1/catalog/status",
            headers: invalidHeaders
        )
        XCTAssertEqual(responseInvalidAuth.status, .unauthorized)

        // Request with valid credentials should succeed
        let responseValidAuth = try await app.sendRequest(
            .GET,
            "/api/v1/catalog/status",
            headers: try await authHeader()
        )
        XCTAssertEqual(responseValidAuth.status, .ok)
    }

    // MARK: - Test 4: Fresh database returns version (default is 0)

    func testFreshDatabaseReturnsVersion() async throws {
        // Fresh database should return a version (default 0 or any non-negative value)
        let response = try await app.sendRequest(
            .GET,
            "/api/v1/catalog/status",
            headers: try await authHeader()
        )

        XCTAssertEqual(response.status, .ok)

        let result = try response.content.decode(CatalogStatusDTO.self)
        // Version should be a valid non-negative Int64
        XCTAssertGreaterThanOrEqual(result.version, 0)
    }

    // MARK: - Test 5: Version updates when catalog changes

    func testVersionUpdatesWhenCatalogChanges() async throws {
        // Get initial version
        let response1 = try await app.sendRequest(
            .GET,
            "/api/v1/catalog/status",
            headers: try await authHeader()
        )
        let result1 = try response1.content.decode(CatalogStatusDTO.self)
        let initialVersion = result1.version

        // Update catalog version (simulating a catalog change)
        try await databaseManager.updateCatalogVersion()

        // Get updated version
        let response2 = try await app.sendRequest(
            .GET,
            "/api/v1/catalog/status",
            headers: try await authHeader()
        )
        let result2 = try response2.content.decode(CatalogStatusDTO.self)

        // Version should have changed (new timestamp is greater than 0 or initial)
        XCTAssertGreaterThan(result2.version, initialVersion)
    }
}

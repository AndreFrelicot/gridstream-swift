import GridStreamAPI
import XCTest
import Security
import Vapor
@testable import gridstream_macos

final class ServerAuthSecretStorageTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "ServerAuthSecretStorageTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    // MARK: - Migration from UserDefaults

    func testLegacySecretsMoveToTheSecretStoreUnchanged() throws {
        defaults.set("legacy-token-secret", forKey: "serverAuthTokenSecret")
        defaults.set("legacy-pin-hash", forKey: "serverPinHash")
        defaults.set("123456", forKey: "serverGeneratedPIN")
        defaults.set(true, forKey: "serverAuthEnabled")
        defaults.set(3, forKey: "serverPinRevision")
        let secrets = InMemorySecretStore()

        let configuration = ServerAuthConfigurationStore(defaults: defaults, secrets: secrets).load()

        // The signing secret is carried over as-is, so issued tokens stay valid
        XCTAssertEqual(configuration.tokenSecret, "legacy-token-secret")
        XCTAssertEqual(configuration.pinHash, "legacy-pin-hash")
        XCTAssertEqual(configuration.generatedPIN, "123456")
        XCTAssertTrue(configuration.isEnabled)
        XCTAssertEqual(configuration.pinRevision, 3)

        XCTAssertEqual(try secrets.string(forKey: "serverAuthTokenSecret"), "legacy-token-secret")
        XCTAssertEqual(try secrets.string(forKey: "serverPinHash"), "legacy-pin-hash")
        XCTAssertEqual(try secrets.string(forKey: "serverGeneratedPIN"), "123456")
        XCTAssertNil(defaults.object(forKey: "serverAuthTokenSecret"))
        XCTAssertNil(defaults.object(forKey: "serverPinHash"))
        XCTAssertNil(defaults.object(forKey: "serverGeneratedPIN"))
        // Non-secret settings stay in UserDefaults
        XCTAssertTrue(defaults.bool(forKey: "serverAuthEnabled"))
        XCTAssertEqual(defaults.integer(forKey: "serverPinRevision"), 3)
    }

    func testTokensIssuedBeforeTheMigrationStayValid() async throws {
        let pinHash = try ServerPINSecurity.hash(pin: "123456")
        let legacyStore = ServerAuthConfigurationStore(defaults: defaults, secrets: InMemorySecretStore())
        legacyStore.save(ServerAuthConfiguration(
            isEnabled: true, pinHash: pinHash, pinRevision: 1, sessionTTLDays: 30, tokenSecret: "legacy-token-secret"
        ))

        let app = try await Application.make(.testing)
        app.serverAuthManager = ServerAuthManager(store: legacyStore)
        try app.register(collection: AuthRoutes())
        var loginHeaders = HTTPHeaders()
        loginHeaders.add(name: .contentType, value: "application/json")
        let login = try await app.sendRequest(
            .POST, "/api/v1/auth/login", headers: loginHeaders, body: ByteBuffer(string: #"{"pin":"123456"}"#)
        )
        let token = try XCTUnwrap(try login.content.decode(AuthSessionResponse.self).token)

        // Simulate the previous version: every value in UserDefaults
        defaults.set("legacy-token-secret", forKey: "serverAuthTokenSecret")
        defaults.set(pinHash, forKey: "serverPinHash")
        let migratedStore = ServerAuthConfigurationStore(defaults: defaults, secrets: InMemorySecretStore())

        var headers = HTTPHeaders()
        headers.add(name: .authorization, value: "Bearer \(token)")
        let request = Request(
            application: app, method: .GET, url: URI(string: "/api/v1/videos"), headers: headers,
            on: app.eventLoopGroup.next()
        )
        XCTAssertNotNil(ServerAuthManager(store: migratedStore).authenticatedSession(from: request))
        try await app.asyncShutdown()
    }

    func testValueAlreadyInTheSecretStoreWinsOverALeftoverDefault() throws {
        defaults.set("stale", forKey: "serverAuthTokenSecret")
        let secrets = InMemorySecretStore(["serverAuthTokenSecret": "current"])

        let store = ServerAuthConfigurationStore(defaults: defaults, secrets: secrets)

        XCTAssertEqual(store.load().tokenSecret, "current")
        XCTAssertNil(defaults.object(forKey: "serverAuthTokenSecret"))
    }

    func testDefaultsAreKeptWhenTheSecretStoreFails() {
        defaults.set("legacy-token-secret", forKey: "serverAuthTokenSecret")

        let store = ServerAuthConfigurationStore(defaults: defaults, secrets: FailingSecretStore())

        XCTAssertEqual(store.load().tokenSecret, "legacy-token-secret")
        XCTAssertEqual(defaults.string(forKey: "serverAuthTokenSecret"), "legacy-token-secret")
    }

    // MARK: - Fresh install and round trips

    func testFreshStoreGeneratesA256BitSecretOutsideUserDefaults() throws {
        let secrets = InMemorySecretStore()

        let secret = ServerAuthConfigurationStore(defaults: defaults, secrets: secrets).load().tokenSecret

        XCTAssertEqual(Data(base64Encoded: secret)?.count, 32)
        XCTAssertEqual(try secrets.string(forKey: "serverAuthTokenSecret"), secret)
        XCTAssertNil(defaults.object(forKey: "serverAuthTokenSecret"))
        XCTAssertNotEqual(ServerAuthConfigurationStore.generateTokenSecret(), secret)
    }

    func testSaveAndLoadRoundTripSecretsThroughTheSecretStore() throws {
        let secrets = InMemorySecretStore()
        let store = ServerAuthConfigurationStore(defaults: defaults, secrets: secrets)
        var configuration = store.load()
        configuration.pinHash = "hash"
        configuration.generatedPIN = "654321"
        configuration.tokenSecret = "secret"
        store.save(configuration)

        let reloaded = ServerAuthConfigurationStore(defaults: defaults, secrets: secrets).load()
        XCTAssertEqual(reloaded.pinHash, "hash")
        XCTAssertEqual(reloaded.generatedPIN, "654321")
        XCTAssertEqual(reloaded.tokenSecret, "secret")
        XCTAssertNil(defaults.object(forKey: "serverPinHash"))
        XCTAssertNil(defaults.object(forKey: "serverGeneratedPIN"))

        configuration.generatedPIN = nil
        store.save(configuration)
        XCTAssertNil(store.load().generatedPIN)
        XCTAssertNil(try secrets.string(forKey: "serverGeneratedPIN"))
    }

    func testGeneratedDefaultPINIsStoredInTheSecretStore() throws {
        let secrets = InMemorySecretStore()
        let store = ServerAuthConfigurationStore(defaults: defaults, secrets: secrets)

        let pin = try XCTUnwrap(try store.ensureDefaultPIN())

        XCTAssertEqual(try secrets.string(forKey: "serverGeneratedPIN"), pin)
        XCTAssertNotNil(try secrets.string(forKey: "serverPinHash"))
        XCTAssertNil(defaults.object(forKey: "serverGeneratedPIN"))
        XCTAssertNil(defaults.object(forKey: "serverPinHash"))
    }

    // MARK: - Keychain

    func testKeychainStoreRoundTripsValues() throws {
        let keychain = KeychainSecretStore(service: "com.gridstream.macos.tests.\(UUID().uuidString)")
        defer { try? keychain.setString(nil, forKey: "value") }

        do {
            try keychain.setString("first", forKey: "value")
        } catch let error as SecretStoreError
                    where [errSecInteractionNotAllowed, errSecMissingEntitlement, errSecNotAvailable].contains(error.status) {
            throw XCTSkip("Keychain unavailable here: \(error.localizedDescription)")
        }
        XCTAssertEqual(try keychain.string(forKey: "value"), "first")

        try keychain.setString("second", forKey: "value")
        XCTAssertEqual(try keychain.string(forKey: "value"), "second")

        try keychain.setString(nil, forKey: "value")
        XCTAssertNil(try keychain.string(forKey: "value"))
        XCTAssertNoThrow(try keychain.setString(nil, forKey: "value"), "Removing a missing value is a no-op")
    }
}

private struct FailingSecretStore: SecretStore {
    func string(forKey key: String) throws -> String? {
        throw SecretStoreError(status: errSecNotAvailable)
    }

    func setString(_ value: String?, forKey key: String) throws {
        throw SecretStoreError(status: errSecNotAvailable)
    }
}

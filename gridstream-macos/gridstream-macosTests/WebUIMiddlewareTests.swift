import XCTest
import Vapor
@testable import gridstream_macos

/// The web UI on/off setting: served on the API port, switched per request.
final class WebUIMiddlewareTests: XCTestCase {
    private var app: Application!
    private var publicDir: URL!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() async throws {
        var env = try Environment.detect()
        env.arguments = ["vapor", "test"]
        app = try await Application.make(env)
        ServerManager.configureSecurityMiddleware(app)

        publicDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebUIMiddlewareTests_\(UUID().uuidString)")
        let browserDir = publicDir.appendingPathComponent("browser")
        try FileManager.default.createDirectory(at: browserDir, withIntermediateDirectories: true)
        try Data("<html>web ui</html>".utf8).write(to: browserDir.appendingPathComponent("index.html"))
        try Data("console.log(1)".utf8).write(to: browserDir.appendingPathComponent("main.js"))

        defaultsSuiteName = "WebUIMiddlewareTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        nonisolated(unsafe) let defaults = self.defaults!
        app.middleware.use(WebUIMiddleware(publicDirectory: publicDir.path + "/") {
            ConfigurationService.webUIEnabled(in: defaults)
        })
        app.get("api", "v1", "health") { _ in HTTPStatus.ok }
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: publicDir)
        app = nil
        defaults = nil
    }

    /// Files are streamed, so the body has to be collected.
    private func body(_ response: Response) async throws -> String {
        let buffer = try await response.body.collect(on: app.eventLoopGroup.next()).get()
        return buffer.map { String(buffer: $0) } ?? ""
    }

    func testWebUIIsServedByDefaultNextToTheAPI() async throws {
        let index = try await app.sendRequest(.GET, "/")
        XCTAssertEqual(index.status, .ok)
        let indexBody = try await body(index)
        XCTAssertEqual(indexBody, "<html>web ui</html>")

        let script = try await app.sendRequest(.GET, "/main.js")
        let scriptBody = try await body(script)
        XCTAssertEqual(scriptBody, "console.log(1)", "Assets referenced by index.html are served from browser/")

        let clientRoute = try await app.sendRequest(.GET, "/library/videos")
        let clientRouteBody = try await body(clientRoute)
        XCTAssertEqual(clientRouteBody, "<html>web ui</html>", "Client-side routes fall back to index.html")

        let api = try await app.sendRequest(.GET, "/api/v1/health")
        XCTAssertEqual(api.status, .ok)
        let missingAPI = try await app.sendRequest(.GET, "/api/v1/missing")
        XCTAssertEqual(missingAPI.status, .notFound, "API 404s are not turned into the web app")
    }

    func testTurningTheWebUIOffTakesEffectWithoutRestart() async throws {
        let before = try await app.sendRequest(.GET, "/")
        XCTAssertEqual(before.status, .ok)

        defaults.set(false, forKey: "webUIEnabled")

        for path in ["/", "/main.js", "/library/videos"] {
            let response = try await app.sendRequest(.GET, path)
            XCTAssertEqual(response.status, .notFound, path)
        }
        let api = try await app.sendRequest(.GET, "/api/v1/health")
        XCTAssertEqual(api.status, .ok, "The API keeps working with the web UI off")

        defaults.set(true, forKey: "webUIEnabled")
        let after = try await app.sendRequest(.GET, "/")
        XCTAssertEqual(after.status, .ok)
    }

    @MainActor
    func testSettingIsOnByDefaultAndPersisted() async throws {
        let databaseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebUISetting_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: databaseDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: databaseDir) }
        let databaseManager = DatabaseManager(databasePath: databaseDir.appendingPathComponent("test.sqlite"))

        let configuration = ConfigurationService(
            databaseManager: databaseManager, defaults: defaults, secrets: InMemorySecretStore()
        )
        XCTAssertTrue(configuration.webUIEnabled)

        configuration.webUIEnabled = false
        XCTAssertFalse(ConfigurationService.webUIEnabled(in: defaults), "The server reads the saved value")

        let reloaded = ConfigurationService(
            databaseManager: databaseManager, defaults: defaults, secrets: InMemorySecretStore()
        )
        XCTAssertFalse(reloaded.webUIEnabled)
    }
}

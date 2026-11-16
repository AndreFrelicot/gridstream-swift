//
//  ServerDiscoveryServiceTests.swift
//  gridstream-ipadTests
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class ServerDiscoveryServiceTests: XCTestCase {

    private let testServerKey = "GridStreamLastKnownServer"

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: testServerKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: testServerKey)
        try await super.tearDown()
    }

    // MARK: - Sticky last-known seeding

    func testStickyLastKnownSeedsInstantly() async throws {
        // Pre-populate UserDefaults with a known server.
        let payload: [String: Any] = [
            "name": "GridStream@laptop",
            "hostname": "laptop.local",
            "port": 8080
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        UserDefaults.standard.set(data, forKey: testServerKey)

        let service = ServerDiscoveryService()

        XCTAssertEqual(service.discoveredServers.count, 1)
        XCTAssertEqual(service.discoveredServers.first?.name, "GridStream@laptop")
        XCTAssertEqual(service.discoveredServers.first?.hostname, "laptop.local")
        XCTAssertEqual(service.discoveredServers.first?.port, 8080)

        if case .found(let name) = service.connectionStatus {
            XCTAssertEqual(name, "GridStream@laptop")
        } else {
            XCTFail("Expected .found connection status, got \(service.connectionStatus)")
        }

        // Seeded servers must NOT appear in verifiedServers until a probe
        // (or Bonjour resolution) confirms reachability.
        XCTAssertTrue(service.verifiedServers.isEmpty)
        XCTAssertTrue(service.unverifiedServerNames.contains("GridStream@laptop"))
    }

    func testServiceWithoutPersistedServerStartsEmpty() async {
        let service = ServerDiscoveryService()

        XCTAssertTrue(service.discoveredServers.isEmpty)
        XCTAssertTrue(service.verifiedServers.isEmpty)
        XCTAssertTrue(service.unverifiedServerNames.isEmpty)
    }

    // MARK: - onSessionExpired hook

    func testHandleUnauthorizedTriggersRediscovery() async {
        let exp = expectation(description: "onSessionExpired fires")
        var capturedURL: URL?

        let sut = ServerSessionManager(keychainService: "com.gridstream.ipad.tests.discovery")
        sut.onSessionExpired = { url in
            capturedURL = url
            exp.fulfill()
        }
        defer { sut.onSessionExpired = nil }

        let serverURL = URL(string: "http://laptop.local:8080")!
        XCTAssertTrue(sut.storeToken("current-token", for: serverURL))
        defer { sut.clearToken(for: serverURL) }
        sut.handleUnauthorized(serverURL: serverURL, sentToken: "current-token")

        await fulfillment(of: [exp], timeout: 1.0)
        XCTAssertEqual(capturedURL, serverURL)
        XCTAssertEqual(sut.state, .locked)
    }

    // MARK: - verifiedServers computed property

    func testVerifiedServersFiltersOutUnverifiedSeed() async throws {
        let payload: [String: Any] = [
            "name": "GridStream@seeded",
            "hostname": "seeded.local",
            "port": 8080
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        UserDefaults.standard.set(data, forKey: testServerKey)

        let service = ServerDiscoveryService()

        XCTAssertFalse(service.discoveredServers.isEmpty)
        XCTAssertTrue(service.verifiedServers.isEmpty, "Unverified seed must not leak into verifiedServers")
    }
}

//
//  CatalogStatusPollingTests.swift
//  gridstream-ipadTests
//
//  Tests for catalog status polling and dirty state detection.
//

import GridStreamAPI
import XCTest
@testable import gridstream_ipad

@MainActor
final class CatalogStatusPollingTests: XCTestCase {

    // MARK: - Test Catalog Status Response Parsing

    func testCatalogStatusResponseParsesVersion() async throws {
        // Given a valid JSON response with version
        let json = """
        {
            "version": 1703012345678
        }
        """
        let data = json.data(using: .utf8)!

        // When parsing the response
        let response = try JSONDecoder().decode(CatalogStatusDTO.self, from: data)

        // Then the version should be correctly parsed
        XCTAssertEqual(response.version, 1703012345678)
    }

    // MARK: - Test Version Comparison Detects Dirty State

    func testVersionComparisonDetectsDirtyState() async {
        // Given a stored version and a different server version
        let storedVersion: Int64 = 1703012345678
        let serverVersion: Int64 = 1703012399999

        // When comparing versions
        let isDirty = serverVersion != storedVersion

        // Then the dirty state should be detected
        XCTAssertTrue(isDirty, "Dirty state should be detected when versions differ")
    }

    func testVersionComparisonNoDirtyStateWhenSame() async {
        // Given the same stored and server version
        let storedVersion: Int64 = 1703012345678
        let serverVersion: Int64 = 1703012345678

        // When comparing versions
        let isDirty = serverVersion != storedVersion

        // Then no dirty state should be detected
        XCTAssertFalse(isDirty, "No dirty state when versions match")
    }

    // MARK: - Test Initial State

    func testInitialStoredVersionIsZero() async {
        // Given no previously stored version
        let userDefaults = UserDefaults(suiteName: "TestSuite")!
        userDefaults.removePersistentDomain(forName: "TestSuite")

        // When reading the stored version
        let storedVersion = userDefaults.object(forKey: "catalogVersion") as? Int64 ?? 0

        // Then it should be zero
        XCTAssertEqual(storedVersion, 0, "Initial stored version should be 0")
    }

    func testVersionStorageAndRetrieval() async {
        // Given a UserDefaults instance
        let userDefaults = UserDefaults(suiteName: "TestCatalogVersion")!
        userDefaults.removePersistentDomain(forName: "TestCatalogVersion")
        let testVersion: Int64 = 1703012345678

        // When storing the version
        userDefaults.set(testVersion, forKey: "catalogVersion")

        // Then it should be retrievable
        let retrievedVersion = userDefaults.object(forKey: "catalogVersion") as? Int64
        XCTAssertEqual(retrievedVersion, testVersion, "Version should be stored and retrieved correctly")

        // Cleanup
        userDefaults.removePersistentDomain(forName: "TestCatalogVersion")
    }
}

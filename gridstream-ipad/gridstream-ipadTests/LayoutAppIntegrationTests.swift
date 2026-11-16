//
//  LayoutAppIntegrationTests.swift
//  gridstream-ipadTests
//

import XCTest
import SwiftData
@testable import gridstream_ipad

@MainActor
final class LayoutAppIntegrationTests: XCTestCase {

    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([LayoutState.self, TileLayout.self, PiPPositionState.self, PiPLayoutEntry.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try! ModelContainer(for: schema, configurations: [configuration])
        modelContext = ModelContext(modelContainer)
    }

    override func tearDown() async throws {
        modelContainer = nil
        modelContext = nil
        try await super.tearDown()
    }

    // MARK: - Layout State Restoration Tests

    func testLayoutStateRestoresOnAppLaunch() async {
        // Create and save a custom layout state
        let persistenceService = LayoutPersistenceService(modelContext: modelContext)
        persistenceService.currentLayout.orientation = .vertical
        persistenceService.currentLayout.presetIdentifier = LayoutPreset.onePlusTwo.rawValue
        persistenceService.currentLayout.tileLayouts = [
            TileLayout(index: 0, widthRatio: 0.6, heightRatio: 1.0),
            TileLayout(index: 1, widthRatio: 0.4, heightRatio: 0.5),
            TileLayout(index: 2, widthRatio: 0.4, heightRatio: 0.5)
        ]
        persistenceService.save()

        // Simulate app launch by creating new GridState and connecting to persistence
        let gridState = GridState()
        let newPersistenceService = LayoutPersistenceService(modelContext: modelContext)
        gridState.connectPersistence(newPersistenceService)

        // Verify layout state is restored
        XCTAssertEqual(gridState.orientation, .vertical)
        XCTAssertEqual(gridState.activePreset, .onePlusTwo)
        XCTAssertEqual(gridState.tiles.count, 3)
        XCTAssertEqual(gridState.tileRatios.count, 3)
        XCTAssertEqual(gridState.tileRatios[0].widthRatio, 0.6, accuracy: 0.001)
    }

    func testLayoutChangesPersistAcrossAppRestart() async {
        // First "app session" - make layout changes
        let persistenceService1 = LayoutPersistenceService(modelContext: modelContext)
        let gridState1 = GridState()
        gridState1.connectPersistence(persistenceService1)

        gridState1.setTileCount(4)
        gridState1.setOrientation(.vertical)
        gridState1.setPreset(.symmetric)
        gridState1.updateTileRatio(at: 0, widthRatio: 0.3, heightRatio: 0.4)

        // Manually trigger save (in real app, debounced save would fire)
        persistenceService1.save()

        // Second "app session" - verify changes persisted
        let persistenceService2 = LayoutPersistenceService(modelContext: modelContext)
        let gridState2 = GridState()
        gridState2.connectPersistence(persistenceService2)

        XCTAssertEqual(gridState2.orientation, .vertical)
        XCTAssertEqual(gridState2.tiles.count, 4)
        XCTAssertEqual(gridState2.tileRatios[0].widthRatio, 0.3, accuracy: 0.001)
        XCTAssertEqual(gridState2.tileRatios[0].heightRatio, 0.4, accuracy: 0.001)
    }

    func testDefaultLayoutCreatedWhenNoSavedState() async {
        // Create fresh persistence service with no saved state
        let persistenceService = LayoutPersistenceService(modelContext: modelContext)
        let gridState = GridState()
        gridState.connectPersistence(persistenceService)

        // Should have default layout values
        XCTAssertEqual(gridState.orientation, .horizontal)
        XCTAssertNil(gridState.activePreset)
        XCTAssertEqual(gridState.tiles.count, 1)
        XCTAssertEqual(gridState.tileRatios.count, 1)
        XCTAssertEqual(gridState.tileRatios[0].widthRatio, 0.5, accuracy: 0.001)
        XCTAssertEqual(gridState.tileRatios[0].heightRatio, 0.5, accuracy: 0.001)
    }
}

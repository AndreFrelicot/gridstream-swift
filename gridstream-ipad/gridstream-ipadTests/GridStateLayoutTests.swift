//
//  GridStateLayoutTests.swift
//  gridstream-ipadTests
//

import XCTest
import SwiftData
@testable import gridstream_ipad

@MainActor
final class GridStateLayoutTests: XCTestCase {

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

    // MARK: - Initialization Tests

    func testGridStateInitializesWithDefaultLayoutState() async throws {
        let state = GridState()

        XCTAssertEqual(state.orientation, .horizontal)
        XCTAssertNil(state.activePreset)
        XCTAssertEqual(state.tileRatios.count, 1)
        let firstTile = try XCTUnwrap(state.tileRatios.first)
        XCTAssertEqual(firstTile.widthRatio, 0.5, accuracy: 0.001)
        XCTAssertEqual(firstTile.heightRatio, 0.5, accuracy: 0.001)
    }

    // MARK: - Orientation Tests

    func testSetOrientationUpdatesOrientation() async {
        let state = GridState()

        state.setOrientation(.vertical)

        XCTAssertEqual(state.orientation, .vertical)

        state.setOrientation(.horizontal)

        XCTAssertEqual(state.orientation, .horizontal)
    }

    // MARK: - Preset Tests

    func testSetPresetUpdatesPresetAndResetsTileRatios() async {
        let state = GridState()
        state.setTileCount(3)

        state.setPreset(.onePlusTwo)

        XCTAssertEqual(state.activePreset, .onePlusTwo)
        XCTAssertEqual(state.tileRatios.count, 3)
        // Ratios should be reset to defaults (0.5)
        for tileRatio in state.tileRatios {
            XCTAssertEqual(tileRatio.widthRatio, 0.5, accuracy: 0.001)
            XCTAssertEqual(tileRatio.heightRatio, 0.5, accuracy: 0.001)
        }
    }

    // MARK: - Tile Ratio Update Tests

    func testUpdateTileRatioRespectsMinMaxConstraints() async {
        let state = GridState()
        state.setTileCount(2)

        // Try to set ratio below minimum (0.1)
        state.updateTileRatio(at: 0, widthRatio: 0.05, heightRatio: nil)
        XCTAssertGreaterThanOrEqual(state.tileRatios[0].widthRatio, TileLayout.minimumRatio)

        // Try to set ratio above maximum (0.75)
        state.updateTileRatio(at: 0, widthRatio: 0.9, heightRatio: nil)
        XCTAssertLessThanOrEqual(state.tileRatios[0].widthRatio, TileLayout.maximumRatio)

        // Set valid ratio
        state.updateTileRatio(at: 0, widthRatio: 0.5, heightRatio: 0.6)
        XCTAssertEqual(state.tileRatios[0].widthRatio, 0.5, accuracy: 0.001)
        XCTAssertEqual(state.tileRatios[0].heightRatio, 0.6, accuracy: 0.001)
    }

    // MARK: - Preset Compatibility Tests

    func testAddingTileConvertsIncompatiblePresetToSymmetric() async {
        let state = GridState()
        state.setTileCount(3)
        state.setPreset(.onePlusTwo)

        XCTAssertEqual(state.activePreset, .onePlusTwo)

        // Adding a tile makes count 4, which is incompatible with onePlusTwo (requires 3 tiles)
        state.addTile()

        XCTAssertEqual(state.tiles.count, 4)
        // Preset should convert to symmetric since onePlusTwo is not compatible with 4 tiles
        XCTAssertEqual(state.activePreset, .symmetric)
    }

    func testRemoveTileUpdatesTileLayoutsArray() async {
        let state = GridState()
        state.setTileCount(3)
        state.setPreset(.onePlusTwo)

        // Modify a ratio to verify it gets properly updated
        state.updateTileRatio(at: 1, widthRatio: 0.4, heightRatio: 0.5)

        state.selectTile(at: 1)
        state.removeSelectedTile()

        XCTAssertEqual(state.tiles.count, 2)
        XCTAssertEqual(state.tileRatios.count, 2)
        // Indices should be recalculated
        XCTAssertEqual(state.tileRatios[0].index, 0)
        XCTAssertEqual(state.tileRatios[1].index, 1)
    }
}

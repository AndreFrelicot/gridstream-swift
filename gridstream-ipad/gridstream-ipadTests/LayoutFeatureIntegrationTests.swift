//
//  LayoutFeatureIntegrationTests.swift
//  gridstream-ipadTests
//

import XCTest
import SwiftData
@testable import gridstream_ipad

/// Integration tests for the complete tile resize, orientation, and arrangement feature.
/// These tests cover end-to-end workflows and edge cases not covered by unit tests.
@MainActor
final class LayoutFeatureIntegrationTests: XCTestCase {

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

    // MARK: - End-to-End: Complete Resize Workflow

    func testCompleteResizeWorkflow_ResizeSaveRestore() async {
        // Setup: Create GridState with persistence and 3-tile layout
        let persistenceService = LayoutPersistenceService(modelContext: modelContext)
        let gridState = GridState()
        gridState.connectPersistence(persistenceService)
        gridState.setTileCount(3)
        gridState.setPreset(.onePlusTwo)

        // Step 1: Perform resize operation
        let originalRatio = gridState.tileRatios[0].widthRatio
        gridState.updateTileRatio(at: 0, widthRatio: 0.65, heightRatio: 0.6)

        // Verify resize applied
        XCTAssertEqual(gridState.tileRatios[0].widthRatio, 0.65, accuracy: 0.001)
        XCTAssertEqual(gridState.tileRatios[0].heightRatio, 0.6, accuracy: 0.001)
        XCTAssertNotEqual(gridState.tileRatios[0].widthRatio, originalRatio)

        // Step 2: Save explicitly
        persistenceService.save()

        // Step 3: Simulate app restart by creating new instances
        let newPersistenceService = LayoutPersistenceService(modelContext: modelContext)
        let newGridState = GridState()
        newGridState.connectPersistence(newPersistenceService)

        // Verify restored values match
        XCTAssertEqual(newGridState.tileRatios[0].widthRatio, 0.65, accuracy: 0.001)
        XCTAssertEqual(newGridState.tileRatios[0].heightRatio, 0.6, accuracy: 0.001)
        XCTAssertEqual(newGridState.activePreset, .onePlusTwo)
        XCTAssertEqual(newGridState.tiles.count, 3)
    }

    // MARK: - Integration: Orientation Change Preserves Tile Assignments

    func testOrientationChangePreservesTileAssignments() async {
        // Setup: Create GridState with videos assigned
        let gridState = GridState()
        gridState.setTileCount(3)
        gridState.setPreset(.onePlusTwo)
        gridState.setOrientation(.horizontal)

        // Assign videos
        let url0 = URL(string: "http://test.com/video0")
        let url1 = URL(string: "http://test.com/video1")
        let url2 = URL(string: "http://test.com/video2")
        gridState.setVideoURL(url0, videoId: "video0", at: 0)
        gridState.setVideoURL(url1, videoId: "video1", at: 1)
        gridState.setVideoURL(url2, videoId: "video2", at: 2)

        // Change orientation
        gridState.setOrientation(.vertical)

        // Verify orientation changed
        XCTAssertEqual(gridState.orientation, .vertical)

        // Verify video assignments preserved
        XCTAssertEqual(gridState.tiles[0].videoURL, url0)
        XCTAssertEqual(gridState.tiles[1].videoURL, url1)
        XCTAssertEqual(gridState.tiles[2].videoURL, url2)

        // Verify tile count unchanged
        XCTAssertEqual(gridState.tiles.count, 3)

        // Verify preset preserved
        XCTAssertEqual(gridState.activePreset, .onePlusTwo)
    }

    // MARK: - Integration: Preset Change with Videos Assigned

    func testPresetChangePreservesVideoAssignments() async {
        // Setup: Create GridState with 4 tiles and videos
        let gridState = GridState()
        gridState.setTileCount(4)
        gridState.setPreset(.symmetric)

        // Assign videos to all tiles
        let urls = (0..<4).map { URL(string: "http://test.com/video\($0)") }
        for (index, url) in urls.enumerated() {
            gridState.setVideoURL(url, videoId: "video\(index)", at: index)
        }

        // Verify initial assignments
        for (index, url) in urls.enumerated() {
            XCTAssertEqual(gridState.tiles[index].videoURL, url)
        }

        // Change to asymmetric preset
        gridState.setPreset(.onePlusThree)

        // Verify preset changed
        XCTAssertEqual(gridState.activePreset, .onePlusThree)

        // Verify all video assignments preserved
        for (index, url) in urls.enumerated() {
            XCTAssertEqual(gridState.tiles[index].videoURL, url)
        }

        // Verify tile count unchanged
        XCTAssertEqual(gridState.tiles.count, 4)
    }

    // MARK: - Edge Case: Resize at Minimum Constraint Boundary

    func testResizeAtMinimumConstraintBoundary() async {
        let gridState = GridState()
        gridState.setTileCount(2)

        // Try to set ratio at exact minimum
        gridState.updateTileRatio(at: 0, widthRatio: TileLayout.minimumRatio, heightRatio: TileLayout.minimumRatio)

        // Verify minimum is applied exactly
        XCTAssertEqual(gridState.tileRatios[0].widthRatio, TileLayout.minimumRatio, accuracy: 0.001)
        XCTAssertEqual(gridState.tileRatios[0].heightRatio, TileLayout.minimumRatio, accuracy: 0.001)

        // Try to set below minimum
        gridState.updateTileRatio(at: 0, widthRatio: 0.05, heightRatio: 0.05)

        // Verify clamped to minimum
        XCTAssertEqual(gridState.tileRatios[0].widthRatio, TileLayout.minimumRatio, accuracy: 0.001)
        XCTAssertEqual(gridState.tileRatios[0].heightRatio, TileLayout.minimumRatio, accuracy: 0.001)

        // Try to set extremely small value
        gridState.updateTileRatio(at: 0, widthRatio: 0.001, heightRatio: 0.001)

        // Verify still clamped to minimum
        XCTAssertEqual(gridState.tileRatios[0].widthRatio, TileLayout.minimumRatio, accuracy: 0.001)
        XCTAssertEqual(gridState.tileRatios[0].heightRatio, TileLayout.minimumRatio, accuracy: 0.001)
    }

    // MARK: - Edge Case: Resize at Maximum Constraint Boundary

    func testResizeAtMaximumConstraintBoundary() async {
        let gridState = GridState()
        gridState.setTileCount(2)

        // Try to set ratio at exact maximum
        gridState.updateTileRatio(at: 0, widthRatio: TileLayout.maximumRatio, heightRatio: TileLayout.maximumRatio)

        // Verify maximum is applied exactly
        XCTAssertEqual(gridState.tileRatios[0].widthRatio, TileLayout.maximumRatio, accuracy: 0.001)
        XCTAssertEqual(gridState.tileRatios[0].heightRatio, TileLayout.maximumRatio, accuracy: 0.001)

        // Try to set above maximum
        gridState.updateTileRatio(at: 0, widthRatio: 0.9, heightRatio: 0.85)

        // Verify clamped to maximum
        XCTAssertEqual(gridState.tileRatios[0].widthRatio, TileLayout.maximumRatio, accuracy: 0.001)
        XCTAssertEqual(gridState.tileRatios[0].heightRatio, TileLayout.maximumRatio, accuracy: 0.001)

        // Try to set to 1.0 (full size)
        gridState.updateTileRatio(at: 0, widthRatio: 1.0, heightRatio: 1.0)

        // Verify clamped to maximum
        XCTAssertEqual(gridState.tileRatios[0].widthRatio, TileLayout.maximumRatio, accuracy: 0.001)
        XCTAssertEqual(gridState.tileRatios[0].heightRatio, TileLayout.maximumRatio, accuracy: 0.001)
    }

    // MARK: - Edge Case: Add Tile Triggers Preset Conversion

    func testAddTileTriggersPresetConversion() async {
        let gridState = GridState()
        gridState.setTileCount(3)
        gridState.setPreset(.onePlusTwo)

        // Assign videos to verify they survive conversion
        let url0 = URL(string: "http://test.com/video0")
        let url1 = URL(string: "http://test.com/video1")
        let url2 = URL(string: "http://test.com/video2")
        gridState.setVideoURL(url0, videoId: "video0", at: 0)
        gridState.setVideoURL(url1, videoId: "video1", at: 1)
        gridState.setVideoURL(url2, videoId: "video2", at: 2)

        // Verify initial preset
        XCTAssertEqual(gridState.activePreset, .onePlusTwo)
        XCTAssertEqual(gridState.tiles.count, 3)

        // Add a tile, making count incompatible with onePlusTwo (requires 3 tiles)
        gridState.addTile()

        // Verify preset converted to symmetric
        XCTAssertEqual(gridState.tiles.count, 4)
        XCTAssertEqual(gridState.activePreset, .symmetric)

        // Verify all original video assignments preserved
        XCTAssertEqual(gridState.tiles[0].videoURL, url0)
        XCTAssertEqual(gridState.tiles[1].videoURL, url1)
        XCTAssertEqual(gridState.tiles[2].videoURL, url2)
        XCTAssertNil(gridState.tiles[3].videoURL) // New tile has no video

        // Verify tile ratios updated for new count
        XCTAssertEqual(gridState.tileRatios.count, 4)
    }

    // MARK: - Integration: Full Layout Cycle with All Features

    func testFullLayoutCycleWithAllFeatures() async {
        // Setup persistence
        let persistenceService = LayoutPersistenceService(modelContext: modelContext)
        let gridState = GridState()
        gridState.connectPersistence(persistenceService)

        // Step 1: Create 3-tile layout with preset
        gridState.setTileCount(3)
        gridState.setPreset(.twoPlusOne)
        gridState.setOrientation(.vertical)

        // Step 2: Assign videos
        let urls = (0..<3).map { URL(string: "http://test.com/video\($0)") }
        for (index, url) in urls.enumerated() {
            gridState.setVideoURL(url, videoId: "video\(index)", at: index)
        }

        // Step 3: Customize tile sizes
        gridState.updateTileRatio(at: 0, widthRatio: 0.4, heightRatio: 0.3)
        gridState.updateTileRatio(at: 1, widthRatio: 0.6, heightRatio: 0.3)
        gridState.updateTileRatio(at: 2, widthRatio: nil, heightRatio: 0.7)

        // Step 4: Save
        persistenceService.save()

        // Step 5: Verify complete state
        XCTAssertEqual(gridState.orientation, .vertical)
        XCTAssertEqual(gridState.activePreset, .twoPlusOne)
        XCTAssertEqual(gridState.tiles.count, 3)

        // Videos should stay assigned
        XCTAssertEqual(gridState.tiles[0].videoURL, urls[0])
        XCTAssertEqual(gridState.tiles[1].videoURL, urls[1])
        XCTAssertEqual(gridState.tiles[2].videoURL, urls[2])

        // Ratios should be updated
        XCTAssertEqual(gridState.tileRatios[0].widthRatio, 0.4, accuracy: 0.001)
        XCTAssertEqual(gridState.tileRatios[1].widthRatio, 0.6, accuracy: 0.001)
        XCTAssertEqual(gridState.tileRatios[2].heightRatio, 0.7, accuracy: 0.001)

        // Step 7: Simulate restart and verify persistence
        let newPersistenceService = LayoutPersistenceService(modelContext: modelContext)
        let newGridState = GridState()
        newGridState.connectPersistence(newPersistenceService)

        XCTAssertEqual(newGridState.orientation, .vertical)
        XCTAssertEqual(newGridState.activePreset, .twoPlusOne)
        XCTAssertEqual(newGridState.tiles.count, 3)
        XCTAssertEqual(newGridState.tileRatios[0].widthRatio, 0.4, accuracy: 0.001)
        XCTAssertEqual(newGridState.tileRatios[2].heightRatio, 0.7, accuracy: 0.001)
    }

    // MARK: - Edge Case: Asymmetric Layout Frame Calculations with Custom Ratios

    func testAsymmetricLayoutFrameCalculationsWithCustomRatios() async {
        let availableSize = CGSize(width: 1024, height: 768)
        let spacing: CGFloat = 8

        // Create custom tile layouts with non-default ratios
        let tileLayouts = [
            TileLayout(index: 0, widthRatio: 0.6, heightRatio: 1.0),
            TileLayout(index: 1, widthRatio: 0.4, heightRatio: 0.4),
            TileLayout(index: 2, widthRatio: 0.4, heightRatio: 0.6)
        ]

        // Calculate frames with custom ratios
        let frames = AsymmetricLayoutCalculator.calculateFrames(
            preset: .onePlusTwo,
            orientation: .horizontal,
            availableSize: availableSize,
            tileLayouts: tileLayouts,
            spacing: spacing
        )

        XCTAssertEqual(frames.count, 3)

        // Verify first frame uses custom width ratio
        let expectedPrimaryWidth = (availableSize.width - spacing) * 0.6
        XCTAssertEqual(frames[0].width, expectedPrimaryWidth, accuracy: 1.0)
        XCTAssertEqual(frames[0].height, availableSize.height, accuracy: 0.01)

        // Verify second and third frames use height ratios
        let totalSecondaryHeight = availableSize.height - spacing
        let expectedSecondHeight = totalSecondaryHeight * 0.4
        XCTAssertEqual(frames[1].height, expectedSecondHeight, accuracy: 1.0)

        // Verify all frames are non-overlapping
        XCTAssertFalse(frames[0].intersects(frames[1].insetBy(dx: 1, dy: 1)))
        XCTAssertFalse(frames[0].intersects(frames[2].insetBy(dx: 1, dy: 1)))
        XCTAssertFalse(frames[1].intersects(frames[2].insetBy(dx: 1, dy: 1)))
    }
}

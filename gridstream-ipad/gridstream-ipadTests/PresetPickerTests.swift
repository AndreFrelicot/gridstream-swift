//
//  PresetPickerTests.swift
//  gridstream-ipadTests
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class PresetPickerTests: XCTestCase {

    // MARK: - Compatible Presets Tests

    func testAsymmetricPresetPickerShowsCompatiblePresetsForTileCount() async {
        // Test that only compatible presets are returned for a given tile count

        // For 3 tiles: should show symmetric, onePlusTwo, twoPlusOne
        let threePresetsArray = LayoutPreset.compatiblePresets(forTileCount: 3)
        XCTAssertEqual(threePresetsArray.count, 3)
        XCTAssertTrue(threePresetsArray.contains(.symmetric))
        XCTAssertTrue(threePresetsArray.contains(.onePlusTwo))
        XCTAssertTrue(threePresetsArray.contains(.twoPlusOne))

        // For 4 tiles: should show symmetric, onePlusThree, threePlusOne, twoPlusTwoStacked
        let fourPresetsArray = LayoutPreset.compatiblePresets(forTileCount: 4)
        XCTAssertEqual(fourPresetsArray.count, 4)
        XCTAssertTrue(fourPresetsArray.contains(.symmetric))
        XCTAssertTrue(fourPresetsArray.contains(.onePlusThree))
        XCTAssertTrue(fourPresetsArray.contains(.threePlusOne))
        XCTAssertTrue(fourPresetsArray.contains(.twoPlusTwoStacked))

        // For 2 tiles: should only show symmetric
        let twoPresetsArray = LayoutPreset.compatiblePresets(forTileCount: 2)
        XCTAssertEqual(twoPresetsArray.count, 1)
        XCTAssertTrue(twoPresetsArray.contains(.symmetric))

        // For 5+ tiles: should only show symmetric
        let fivePresetsArray = LayoutPreset.compatiblePresets(forTileCount: 5)
        XCTAssertEqual(fivePresetsArray.count, 1)
        XCTAssertTrue(fivePresetsArray.contains(.symmetric))
    }

    // MARK: - Preset Selection Tests

    func testSelectingPresetUpdatesGridState() async {
        let gridState = GridState()

        // Set up 3 tiles for asymmetric presets
        gridState.setTileCount(3)
        XCTAssertEqual(gridState.tileCount, 3)

        // Initially no preset is selected
        XCTAssertNil(gridState.activePreset)

        // Select onePlusTwo preset
        gridState.setPreset(.onePlusTwo)
        XCTAssertEqual(gridState.activePreset, .onePlusTwo)

        // Select twoPlusOne preset
        gridState.setPreset(.twoPlusOne)
        XCTAssertEqual(gridState.activePreset, .twoPlusOne)

        // Change to 4 tiles and verify preset selection works
        gridState.setTileCount(4)
        gridState.setPreset(.onePlusThree)
        XCTAssertEqual(gridState.activePreset, .onePlusThree)
    }

    // MARK: - Preset Display Properties Tests

    func testPresetThumbnailsHaveCorrectDisplayProperties() async {
        // Test that each preset has valid display properties for rendering

        // Test symmetric preset
        XCTAssertEqual(String(localized: LayoutPreset.symmetric.displayName), "Symmetric")
        XCTAssertEqual(LayoutPreset.symmetric.iconName, "square.grid.2x2")

        // Test onePlusTwo preset
        XCTAssertEqual(String(localized: LayoutPreset.onePlusTwo.displayName), "1 + 2")
        XCTAssertEqual(LayoutPreset.onePlusTwo.iconName, "rectangle.split.1x2")
        XCTAssertEqual(LayoutPreset.onePlusTwo.tileCount, 3)

        // Test twoPlusOne preset
        XCTAssertEqual(String(localized: LayoutPreset.twoPlusOne.displayName), "2 + 1")
        XCTAssertEqual(LayoutPreset.twoPlusOne.iconName, "rectangle.split.2x1")
        XCTAssertEqual(LayoutPreset.twoPlusOne.tileCount, 3)

        // Test onePlusThree preset
        XCTAssertEqual(String(localized: LayoutPreset.onePlusThree.displayName), "1 + 3")
        XCTAssertEqual(LayoutPreset.onePlusThree.iconName, "rectangle.split.1x2.fill")
        XCTAssertEqual(LayoutPreset.onePlusThree.tileCount, 4)

        // Test threePlusOne preset
        XCTAssertEqual(String(localized: LayoutPreset.threePlusOne.displayName), "3 + 1")
        XCTAssertEqual(LayoutPreset.threePlusOne.iconName, "rectangle.split.2x1.fill")
        XCTAssertEqual(LayoutPreset.threePlusOne.tileCount, 4)

        // Test twoPlusTwoStacked preset
        XCTAssertEqual(String(localized: LayoutPreset.twoPlusTwoStacked.displayName), "2 + 2 Stacked")
        XCTAssertEqual(LayoutPreset.twoPlusTwoStacked.iconName, "rectangle.split.2x2")
        XCTAssertEqual(LayoutPreset.twoPlusTwoStacked.tileCount, 4)
    }

    // MARK: - Preset Icon Rendering Tests

    func testPresetIconRendersCorrectFrameCount() async {
        // Test that AsymmetricLayoutCalculator returns correct frame count for each preset

        let availableSize = CGSize(width: 400, height: 300)

        // Test onePlusTwo returns 3 frames
        let onePlusTwoFrames = AsymmetricLayoutCalculator.calculateFrames(
            preset: .onePlusTwo,
            orientation: .horizontal,
            availableSize: availableSize
        )
        XCTAssertEqual(onePlusTwoFrames.count, 3)

        // Test twoPlusOne returns 3 frames
        let twoPlusOneFrames = AsymmetricLayoutCalculator.calculateFrames(
            preset: .twoPlusOne,
            orientation: .horizontal,
            availableSize: availableSize
        )
        XCTAssertEqual(twoPlusOneFrames.count, 3)

        // Test onePlusThree returns 4 frames
        let onePlusThreeFrames = AsymmetricLayoutCalculator.calculateFrames(
            preset: .onePlusThree,
            orientation: .horizontal,
            availableSize: availableSize
        )
        XCTAssertEqual(onePlusThreeFrames.count, 4)

        // Test threePlusOne returns 4 frames
        let threePlusOneFrames = AsymmetricLayoutCalculator.calculateFrames(
            preset: .threePlusOne,
            orientation: .horizontal,
            availableSize: availableSize
        )
        XCTAssertEqual(threePlusOneFrames.count, 4)

        // Test twoPlusTwoStacked returns 4 frames
        let twoPlusTwoStackedFrames = AsymmetricLayoutCalculator.calculateFrames(
            preset: .twoPlusTwoStacked,
            orientation: .horizontal,
            availableSize: availableSize
        )
        XCTAssertEqual(twoPlusTwoStackedFrames.count, 4)

        // Test symmetric returns empty array (handled by GridLayout instead)
        let symmetricFrames = AsymmetricLayoutCalculator.calculateFrames(
            preset: .symmetric,
            orientation: .horizontal,
            availableSize: availableSize
        )
        XCTAssertEqual(symmetricFrames.count, 0)
    }
}

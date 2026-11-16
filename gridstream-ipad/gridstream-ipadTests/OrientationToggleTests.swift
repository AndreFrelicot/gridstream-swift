//
//  OrientationToggleTests.swift
//  gridstream-ipadTests
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class OrientationToggleTests: XCTestCase {

    // MARK: - Display Tests

    func testOrientationToggleDisplaysCurrentOrientation() async {
        let gridState = GridState()
        gridState.setOrientation(.horizontal)

        XCTAssertEqual(gridState.orientation, .horizontal)
        XCTAssertEqual(gridState.orientation.sfSymbolName, "arrow.left.and.right")

        gridState.setOrientation(.vertical)

        XCTAssertEqual(gridState.orientation, .vertical)
        XCTAssertEqual(gridState.orientation.sfSymbolName, "arrow.up.and.down")
    }

    // MARK: - Toggle Action Tests

    func testToggleActionChangesGridStateOrientation() async {
        let gridState = GridState()

        XCTAssertEqual(gridState.orientation, .horizontal)

        gridState.setOrientation(.vertical)

        XCTAssertEqual(gridState.orientation, .vertical)

        gridState.setOrientation(.horizontal)

        XCTAssertEqual(gridState.orientation, .horizontal)
    }

    // MARK: - Layout Recalculation Tests

    func testOrientationChangeRecalculatesLayout() async {
        let gridState = GridState()
        gridState.setTileCount(3)
        gridState.setPreset(.onePlusTwo)

        let initialOrientation = gridState.orientation

        // Change orientation
        let newOrientation: LayoutOrientation = initialOrientation == .horizontal ? .vertical : .horizontal
        gridState.setOrientation(newOrientation)

        // Verify orientation changed
        XCTAssertEqual(gridState.orientation, newOrientation)

        // Verify preset is still active (orientation change should preserve preset)
        XCTAssertEqual(gridState.activePreset, .onePlusTwo)

        // Verify tile ratios remain valid
        XCTAssertEqual(gridState.tileRatios.count, 3)
    }
}

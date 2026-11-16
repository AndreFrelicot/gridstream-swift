//
//  TileFramingStateTests.swift
//  gridstream-ipadTests
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class TileFramingStateTests: XCTestCase {

    // MARK: - FramingMode Tests

    func testFramingModeRawValueEncodingDecoding() async {
        // Test that FramingMode correctly encodes and decodes from raw values
        XCTAssertEqual(FramingMode(rawValue: "fill"), .fill)
        XCTAssertEqual(FramingMode(rawValue: "fit"), .fit)
        XCTAssertEqual(FramingMode(rawValue: "custom"), .custom)

        XCTAssertEqual(FramingMode.fill.rawValue, "fill")
        XCTAssertEqual(FramingMode.fit.rawValue, "fit")
        XCTAssertEqual(FramingMode.custom.rawValue, "custom")
    }

    func testFramingModeCycling() async {
        // Test that modes cycle correctly: fill -> fit -> custom -> fill
        XCTAssertEqual(FramingMode.fill.next, .fit)
        XCTAssertEqual(FramingMode.fit.next, .custom)
        XCTAssertEqual(FramingMode.custom.next, .fill)
    }

    // MARK: - TileFramingState Initialization Tests

    func testTileFramingStateInitializationWithDefaults() async {
        let state = TileFramingState(index: 0)

        XCTAssertEqual(state.index, 0)
        XCTAssertEqual(state.framingMode, .fill)
        XCTAssertEqual(state.customZoomLevel, 1.0)
        XCTAssertEqual(state.customPanOffsetX, 0.0)
        XCTAssertEqual(state.customPanOffsetY, 0.0)
        XCTAssertEqual(state.customPanOffset, .zero)
    }

    func testCustomZoomPanStatePreservation() async {
        // Test that custom zoom level and pan offset are stored correctly
        let state = TileFramingState(
            index: 1,
            framingMode: .custom,
            customZoomLevel: 2.5,
            customPanOffsetX: 100.0,
            customPanOffsetY: -50.0
        )

        XCTAssertEqual(state.framingMode, .custom)
        XCTAssertEqual(state.customZoomLevel, 2.5)
        XCTAssertEqual(state.customPanOffset.x, 100.0)
        XCTAssertEqual(state.customPanOffset.y, -50.0)

        // Test CGPoint setter
        state.customPanOffset = CGPoint(x: 200.0, y: 150.0)
        XCTAssertEqual(state.customPanOffsetX, 200.0)
        XCTAssertEqual(state.customPanOffsetY, 150.0)
    }

    func testResetToDefaultsFunctionality() async {
        // Set up state with custom values
        let state = TileFramingState(
            index: 0,
            framingMode: .custom,
            customZoomLevel: 3.0,
            customPanOffsetX: 150.0,
            customPanOffsetY: -75.0
        )

        // Reset custom framing
        state.resetCustomFraming()

        // Verify reset to defaults
        XCTAssertEqual(state.customZoomLevel, 1.0)
        XCTAssertEqual(state.customPanOffsetX, 0.0)
        XCTAssertEqual(state.customPanOffsetY, 0.0)

        // Note: framing mode should NOT be reset
        XCTAssertEqual(state.framingMode, .custom)
    }
}

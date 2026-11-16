//
//  VideoReframingIntegrationTests.swift
//  gridstream-ipadTests
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class VideoReframingIntegrationTests: XCTestCase {

    func testModeCyclingPreservesCustomSettings() async {
        // Given a TileFramingState with custom zoom and pan
        let state = TileFramingState(index: 0)
        state.framingMode = .custom
        state.customZoomLevel = 2.5
        state.customPanOffset = CGPoint(x: 100, y: -50)

        // When cycling through modes: custom -> fill
        state.cycleMode()
        XCTAssertEqual(state.framingMode, .fill)

        // Then custom settings are preserved
        XCTAssertEqual(state.customZoomLevel, 2.5)
        XCTAssertEqual(state.customPanOffset.x, 100)
        XCTAssertEqual(state.customPanOffset.y, -50)

        // When cycling: fill -> fit
        state.cycleMode()
        XCTAssertEqual(state.framingMode, .fit)

        // Settings still preserved
        XCTAssertEqual(state.customZoomLevel, 2.5)

        // When cycling back to custom: fit -> custom
        state.cycleMode()
        XCTAssertEqual(state.framingMode, .custom)

        // Original settings restored
        XCTAssertEqual(state.customZoomLevel, 2.5)
        XCTAssertEqual(state.customPanOffset, CGPoint(x: 100, y: -50))
    }

    func testFramingStateIndependencePerTile() async {
        // Given two separate TileFramingStates
        let state1 = TileFramingState(index: 0)
        let state2 = TileFramingState(index: 1)

        // When modifying state1
        state1.framingMode = .custom
        state1.customZoomLevel = 3.0
        state1.customPanOffset = CGPoint(x: 200, y: 100)

        // And modifying state2 differently
        state2.framingMode = .fit
        state2.customZoomLevel = 1.5
        state2.customPanOffset = CGPoint(x: -50, y: 75)

        // Then each state maintains independent values
        XCTAssertEqual(state1.framingMode, .custom)
        XCTAssertEqual(state1.customZoomLevel, 3.0)
        XCTAssertEqual(state1.customPanOffset, CGPoint(x: 200, y: 100))

        XCTAssertEqual(state2.framingMode, .fit)
        XCTAssertEqual(state2.customZoomLevel, 1.5)
        XCTAssertEqual(state2.customPanOffset, CGPoint(x: -50, y: 75))
    }

    func testTileLayoutIncludesFramingState() async {
        // Given a TileLayout
        let layout = TileLayout(index: 0)

        // Then it should have a framing state
        XCTAssertNotNil(layout.framingState)

        // And the framing state should have default values
        XCTAssertEqual(layout.framingState?.framingMode, .fill)
        XCTAssertEqual(layout.framingState?.customZoomLevel, 1.0)
        XCTAssertEqual(layout.framingState?.customPanOffset, .zero)
    }

    func testEnsureFramingStateCreatesIfMissing() async {
        // Given a TileLayout
        let layout = TileLayout(index: 0)

        // Initially it has a framing state from init
        XCTAssertNotNil(layout.framingState)

        // Store the original ID to verify identity
        let originalId = layout.framingState?.id

        // When calling ensureFramingState
        layout.ensureFramingState()

        // Then the existing state is preserved (not recreated)
        XCTAssertEqual(layout.framingState?.id, originalId)
    }

    func testCurrentFramingModeConvenienceProperty() async {
        // Given a TileLayout with custom framing mode
        let layout = TileLayout(index: 0)
        layout.framingState?.framingMode = .fit

        // Then currentFramingMode returns the correct value
        XCTAssertEqual(layout.currentFramingMode, .fit)

        // When changing to custom
        layout.framingState?.framingMode = .custom

        // Then it updates accordingly
        XCTAssertEqual(layout.currentFramingMode, .custom)
    }
}

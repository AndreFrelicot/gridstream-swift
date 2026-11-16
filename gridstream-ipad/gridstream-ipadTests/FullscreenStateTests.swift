//
//  FullscreenStateTests.swift
//  gridstream-ipadTests
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class FullscreenStateTests: XCTestCase {

    // MARK: - Fullscreen State Tests

    func testEnterFullscreenSetsFullscreenTileIndex() async {
        let state = GridState()
        state.setTileCount(4)

        state.enterFullscreen(tileIndex: 2)

        XCTAssertEqual(state.fullscreenTileIndex, 2)
        XCTAssertTrue(state.isFullscreenMode)
    }

    func testExitFullscreenClearsFullscreenTileIndex() async {
        let state = GridState()
        state.setTileCount(4)
        state.enterFullscreen(tileIndex: 1)

        state.exitFullscreen()

        XCTAssertNil(state.fullscreenTileIndex)
        XCTAssertFalse(state.isFullscreenMode)
    }

    func testSwapFullscreenExchangesIndices() async {
        let state = GridState()
        state.setTileCount(4)
        state.enterFullscreen(tileIndex: 0)

        state.swapFullscreen(toPipIndex: 2)

        XCTAssertEqual(state.fullscreenTileIndex, 2)
        XCTAssertTrue(state.isFullscreenMode)
    }

    func testIsFullscreenModeComputedProperty() async {
        let state = GridState()

        // Initially not in fullscreen mode
        XCTAssertFalse(state.isFullscreenMode)

        // Enter fullscreen
        state.enterFullscreen(tileIndex: 0)
        XCTAssertTrue(state.isFullscreenMode)

        // Exit fullscreen
        state.exitFullscreen()
        XCTAssertFalse(state.isFullscreenMode)
    }

    func testEnterFullscreenWithInvalidIndexDoesNothing() async {
        let state = GridState()
        state.setTileCount(4)

        // Try to enter fullscreen with invalid index
        state.enterFullscreen(tileIndex: 10)

        XCTAssertNil(state.fullscreenTileIndex)
        XCTAssertFalse(state.isFullscreenMode)
    }
}

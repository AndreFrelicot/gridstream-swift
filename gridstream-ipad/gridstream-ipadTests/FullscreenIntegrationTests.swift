//
//  FullscreenIntegrationTests.swift
//  gridstream-ipadTests
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class FullscreenIntegrationTests: XCTestCase {

    // MARK: - Mode Switching Tests

    func testFullscreenButtonEntersFullscreenMode() async {
        let state = GridState()
        state.setTileCount(4)

        // Simulate tapping fullscreen button on tile 0
        state.enterFullscreen(tileIndex: 0)

        XCTAssertTrue(state.isFullscreenMode)
        XCTAssertEqual(state.fullscreenTileIndex, 0)
    }

    func testExitButtonReturnsToGridMode() async {
        let state = GridState()
        state.setTileCount(4)
        state.enterFullscreen(tileIndex: 0)

        // Simulate tapping exit button
        state.exitFullscreen()

        XCTAssertFalse(state.isFullscreenMode)
        XCTAssertNil(state.fullscreenTileIndex)
    }

    func testPiPTapSwapsWithFullscreen() async {
        let state = GridState()
        state.setTileCount(4)
        state.enterFullscreen(tileIndex: 0)

        // Simulate tapping PiP tile 2
        state.swapFullscreen(toPipIndex: 2)

        XCTAssertTrue(state.isFullscreenMode)
        XCTAssertEqual(state.fullscreenTileIndex, 2)
    }

    func testModeTransitionsPreserveGridState() async {
        let state = GridState()
        state.setTileCount(4)

        // Store initial state
        let initialTileCount = state.tileCount

        // Enter fullscreen
        state.enterFullscreen(tileIndex: 0)

        // Swap
        state.swapFullscreen(toPipIndex: 1)

        // Exit fullscreen
        state.exitFullscreen()

        // Verify grid state unchanged
        XCTAssertEqual(state.tileCount, initialTileCount)
        XCTAssertFalse(state.isFullscreenMode)
    }

    func testPiPPositionsPersistAcrossModeExits() async {
        // Verify that tile layouts can store PiP positions
        let layout = TileLayout(index: 0)

        // Set a position
        layout.updatePiPPosition(CGPoint(x: 100, y: 200))

        // Verify it's stored
        XCTAssertEqual(layout.currentPiPPosition, CGPoint(x: 100, y: 200))

        // Verify ensurePiPPosition creates state if needed
        let layout2 = TileLayout(index: 1)
        XCTAssertEqual(layout2.currentPiPPosition, .zero)
        layout2.ensurePiPPosition()
        XCTAssertNotNil(layout2.pipPosition)
    }

    func testResetPiPLayoutForgetsOnlyTheCurrentVideosLayout() async {
        UserDefaults.standard.removeObject(forKey: "pipLayoutMemoryDisabled")
        let state = GridState()
        state.setTileCount(3)
        state.enterFullscreen(tileIndex: 0)
        state.updatePiPPosition(at: 1, position: CGPoint(x: 10, y: 20))
        state.swapFullscreen(toPipIndex: 1)
        state.updatePiPPosition(at: 0, position: CGPoint(x: 30, y: 40))

        state.resetPiPLayout(forFullscreen: 1)

        XCTAssertTrue(state.layoutState.pipLayouts(forFullscreen: 1).isEmpty)
        XCTAssertNotNil(state.layoutState.pipLayout(forPiP: 1, whenFullscreen: 0))
    }

    func testResetAllPiPLayoutsForgetsEveryLayout() async {
        let state = GridState()
        state.setTileCount(3)
        state.layoutState.setPipLayout(forPiP: 1, whenFullscreen: 0, position: CGPoint(x: 10, y: 20), scale: 0.3, rotation: 0.2)
        state.layoutState.setPipLayout(forPiP: 0, whenFullscreen: 2, position: CGPoint(x: 30, y: 40), scale: 0.3, rotation: 0)
        state.tileRatios[1].updatePiPPosition(CGPoint(x: 50, y: 60))

        state.resetAllPiPLayouts()

        XCTAssertTrue(state.layoutState.pipLayouts.isEmpty)
        XCTAssertTrue(state.tileRatios.allSatisfy { $0.pipPosition == nil })
    }

    func testResetPiPLayoutWithoutLayoutMemoryClearsTheSharedLayout() async {
        UserDefaults.standard.set(true, forKey: "pipLayoutMemoryDisabled")
        defer { UserDefaults.standard.removeObject(forKey: "pipLayoutMemoryDisabled") }
        let state = GridState()
        state.setTileCount(3)
        state.enterFullscreen(tileIndex: 0)
        state.updatePiPPosition(at: 1, position: CGPoint(x: 10, y: 20))
        state.updatePiPScale(at: 2, scale: 0.3)
        state.layoutState.setPipLayout(forPiP: 1, whenFullscreen: 0, position: CGPoint(x: 10, y: 20), scale: 0.3, rotation: 0)

        state.resetPiPLayout(forFullscreen: 0)

        XCTAssertTrue(state.tileRatios.allSatisfy { $0.pipPosition == nil })
        // The remembered layouts are kept for when memory is turned back on.
        XCTAssertNotNil(state.layoutState.pipLayout(forPiP: 1, whenFullscreen: 0))
    }

    func testPiPSwapExchangesPersistedTransforms() async throws {
        // The transform exchange is the legacy path; per-fullscreen PiP layout
        // memory (the default) stores layouts per context instead.
        UserDefaults.standard.set(true, forKey: "pipLayoutMemoryDisabled")
        defer { UserDefaults.standard.removeObject(forKey: "pipLayoutMemoryDisabled") }

        let state = GridState()
        state.setTileCount(3)
        state.enterFullscreen(tileIndex: 0)

        // Existing persisted transform for current fullscreen tile.
        state.updatePiPPosition(at: 0, position: CGPoint(x: 30, y: 40))
        state.updatePiPScale(at: 0, scale: 0.24)
        state.updatePiPRotation(at: 0, rotation: 0.1)

        // Live transform of tapped PiP tile.
        let tappedTransform = PiPTransform(
            position: CGPoint(x: 320, y: 180),
            scale: 0.32,
            rotation: 0.6
        )

        state.swapFullscreen(toPipIndex: 1, tappedPiPTransform: tappedTransform)

        XCTAssertEqual(state.fullscreenTileIndex, 1)

        let layout0 = try XCTUnwrap(state.tileRatios.first { $0.index == 0 })
        let layout1 = try XCTUnwrap(state.tileRatios.first { $0.index == 1 })

        // Old fullscreen tile should now use tapped PiP transform.
        XCTAssertEqual(layout0.currentPiPPosition.x, tappedTransform.position.x, accuracy: 0.001)
        XCTAssertEqual(layout0.currentPiPPosition.y, tappedTransform.position.y, accuracy: 0.001)
        XCTAssertEqual(layout0.currentPiPScale, tappedTransform.scale, accuracy: 0.001)
        XCTAssertEqual(layout0.currentPiPRotation, tappedTransform.rotation, accuracy: 0.001)

        // Tapped tile should keep old fullscreen transform (true exchange, no duplication).
        XCTAssertEqual(layout1.currentPiPPosition.x, 30, accuracy: 0.001)
        XCTAssertEqual(layout1.currentPiPPosition.y, 40, accuracy: 0.001)
        XCTAssertEqual(layout1.currentPiPScale, 0.24, accuracy: 0.001)
        XCTAssertEqual(layout1.currentPiPRotation, 0.1, accuracy: 0.001)
    }
}

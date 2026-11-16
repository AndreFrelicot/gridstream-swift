//
//  VideoControlsStateTests.swift
//  gridstream-ipadTests
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class VideoControlsStateTests: XCTestCase {

    func testShowControlsSetsIsVisibleToTrue() async {
        let state = VideoControlsState()

        state.show()

        XCTAssertTrue(state.isVisible)
    }

    func testTogglePinChangesIsPinnedState() async {
        let state = VideoControlsState()

        XCTAssertFalse(state.isPinned)

        state.togglePin()
        XCTAssertTrue(state.isPinned)

        state.togglePin()
        XCTAssertFalse(state.isPinned)
    }

    func testHideBlockedWhenPinned() async {
        let state = VideoControlsState()

        state.show()
        state.togglePin()
        state.hide()

        // Controls should remain visible when pinned
        XCTAssertTrue(state.isVisible)
    }

    func testHideAllowedWhenNotPinned() async {
        let state = VideoControlsState()

        state.show()
        state.hide()

        // Controls should be hidden when not pinned
        XCTAssertFalse(state.isVisible)
    }
}

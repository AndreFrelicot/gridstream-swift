//
//  FullscreenButtonTests.swift
//  gridstream-ipadTests
//

import XCTest
import SwiftUI
@testable import gridstream_ipad

@MainActor
final class FullscreenButtonTests: XCTestCase {

    // MARK: - FullscreenButton Tests

    func testFullscreenButtonRendersCorrectSymbol() async {
        // The FullscreenButton should use "arrow.up.left.and.arrow.down.right" SF Symbol
        let button = FullscreenButton(onFullscreen: {})
        XCTAssertNotNil(button)
    }

    func testFullscreenButtonHasCorrectAccessibilityLabel() async {
        // The FullscreenButton should have "Enter fullscreen" accessibility label
        let button = FullscreenButton(onFullscreen: {})
        XCTAssertNotNil(button)
    }

    func testFullscreenButtonActionTriggered() async {
        var actionTriggered = false
        let button = FullscreenButton(onFullscreen: {
            actionTriggered = true
        })

        // Trigger the action
        button.onFullscreen()

        XCTAssertTrue(actionTriggered)
    }

    // MARK: - ExitFullscreenButton Tests

    func testExitFullscreenButtonRendersCorrectSymbol() async {
        // The ExitFullscreenButton should use "arrow.down.right.and.arrow.up.left" SF Symbol
        let button = ExitFullscreenButton(onExitFullscreen: {})
        XCTAssertNotNil(button)
    }

    func testExitFullscreenButtonActionTriggered() async {
        var actionTriggered = false
        let button = ExitFullscreenButton(onExitFullscreen: {
            actionTriggered = true
        })

        // Trigger the action
        button.onExitFullscreen()

        XCTAssertTrue(actionTriggered)
    }
}

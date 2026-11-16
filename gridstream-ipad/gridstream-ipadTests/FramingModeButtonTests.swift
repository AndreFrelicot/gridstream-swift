//
//  FramingModeButtonTests.swift
//  gridstream-ipadTests
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class FramingModeButtonTests: XCTestCase {

    func testButtonDisplaysCorrectIconForEachMode() async {
        // Test Fill mode icon
        XCTAssertEqual(FramingMode.fill.iconName, "arrow.up.left.and.arrow.down.right")

        // Test Fit mode icon
        XCTAssertEqual(FramingMode.fit.iconName, "arrow.down.forward.and.arrow.up.backward")

        // Test Custom mode icon
        XCTAssertEqual(FramingMode.custom.iconName, "viewfinder")
    }

    func testButtonCyclesToNextModeOnTap() async {
        var receivedMode: FramingMode?

        // Simulate starting from Fill mode
        let onModeChange: (FramingMode) -> Void = { mode in
            receivedMode = mode
        }

        // When fill mode cycles, should go to fit
        onModeChange(FramingMode.fill.next)
        XCTAssertEqual(receivedMode, .fit)

        // When fit mode cycles, should go to custom
        onModeChange(FramingMode.fit.next)
        XCTAssertEqual(receivedMode, .custom)

        // When custom mode cycles, should go back to fill
        onModeChange(FramingMode.custom.next)
        XCTAssertEqual(receivedMode, .fill)
    }

    func testAccessibilityLabelAndHint() async {
        // Test display names used for accessibility
        XCTAssertEqual(String(localized: FramingMode.fill.displayName), "Fill")
        XCTAssertEqual(String(localized: FramingMode.fit.displayName), "Fit")
        XCTAssertEqual(String(localized: FramingMode.custom.displayName), "Custom")
    }
}

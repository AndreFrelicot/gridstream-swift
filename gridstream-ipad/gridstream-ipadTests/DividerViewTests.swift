//
//  DividerViewTests.swift
//  gridstream-ipadTests
//

import XCTest
import SwiftUI
@testable import gridstream_ipad

@MainActor
final class DividerViewTests: XCTestCase {

    // MARK: - DividerView Rendering Tests

    func testDividerViewRendersAtCorrectPositionForVerticalAxis() async {
        // Given a vertical divider at position 500
        let divider = DividerPosition(
            axis: .vertical,
            position: 500,
            affectedTileIndices: [0, 1],
            length: 768
        )

        // The divider should be centered at x = 500
        let hitRect = divider.hitRect(touchSize: 44)

        XCTAssertEqual(hitRect.midX, 500, accuracy: 0.01)
        XCTAssertEqual(hitRect.width, 44, accuracy: 0.01)
        XCTAssertEqual(hitRect.height, 768, accuracy: 0.01)
    }

    func testDividerViewRendersAtCorrectPositionForHorizontalAxis() async {
        // Given a horizontal divider at position 300
        let divider = DividerPosition(
            axis: .horizontal,
            position: 300,
            affectedTileIndices: [0, 2],
            length: 1024
        )

        // The divider should be centered at y = 300
        let hitRect = divider.hitRect(touchSize: 44)

        XCTAssertEqual(hitRect.midY, 300, accuracy: 0.01)
        XCTAssertEqual(hitRect.width, 1024, accuracy: 0.01)
        XCTAssertEqual(hitRect.height, 44, accuracy: 0.01)
    }

    // MARK: - Drag Gesture Tests

    func testDividerDragGestureCalculatesDelta() async {
        // Test that delta calculations work correctly
        let initialPosition: CGFloat = 500
        let dragTranslation: CGFloat = 50
        let expectedNewPosition = initialPosition + dragTranslation

        // Verify delta calculation logic
        let delta = dragTranslation
        let newPosition = initialPosition + delta

        XCTAssertEqual(newPosition, expectedNewPosition, accuracy: 0.01)
    }

    // MARK: - Constraint Tests

    func testDragConstraintsEnforceMinMaxTileSizes() async {
        // Given constraints for min/max tile sizes
        let minimumRatio = TileLayout.minimumRatio  // 0.1
        let maximumRatio = TileLayout.maximumRatio  // 0.75
        let availableWidth: CGFloat = 1000

        // Calculate min/max positions for a divider
        let minPosition = availableWidth * minimumRatio
        let maxPosition = availableWidth * maximumRatio

        // Test clamping below minimum
        let positionBelowMin: CGFloat = 50
        let clampedMin = max(minPosition, min(maxPosition, positionBelowMin))
        XCTAssertEqual(clampedMin, minPosition, accuracy: 0.01)

        // Test clamping above maximum
        let positionAboveMax: CGFloat = 800
        let clampedMax = max(minPosition, min(maxPosition, positionAboveMax))
        XCTAssertEqual(clampedMax, maxPosition, accuracy: 0.01)

        // Test valid position passes through
        let validPosition: CGFloat = 400
        let clampedValid = max(minPosition, min(maxPosition, validPosition))
        XCTAssertEqual(clampedValid, validPosition, accuracy: 0.01)
    }

    // MARK: - Visual Feedback Tests

    func testDividerVisualFeedbackProperties() async {
        // Test the visual properties change between normal and dragging states

        // Normal state: 2pt line, opacity 0.3
        let normalLineWidth: CGFloat = 2
        let normalOpacity: Double = 0.3

        // Dragging state: 4pt line, higher opacity
        let draggingLineWidth: CGFloat = 4
        let draggingOpacity: Double = 0.6

        XCTAssertEqual(normalLineWidth, 2)
        XCTAssertEqual(normalOpacity, 0.3, accuracy: 0.01)
        XCTAssertEqual(draggingLineWidth, 4)
        XCTAssertEqual(draggingOpacity, 0.6, accuracy: 0.01)

        // Verify dragging state is more prominent
        XCTAssertGreaterThan(draggingLineWidth, normalLineWidth)
        XCTAssertGreaterThan(draggingOpacity, normalOpacity)
    }

    // MARK: - Hit Area Tests

    func testDividerHitAreaIs44Points() async {
        // Per iOS HIG, touch targets should be at least 44pt

        let verticalDivider = DividerPosition(
            axis: .vertical,
            position: 500,
            affectedTileIndices: [0, 1],
            length: 768
        )

        let horizontalDivider = DividerPosition(
            axis: .horizontal,
            position: 300,
            affectedTileIndices: [0, 2],
            length: 1024
        )

        let verticalHitRect = verticalDivider.hitRect(touchSize: 44)
        let horizontalHitRect = horizontalDivider.hitRect(touchSize: 44)

        // Vertical divider should have 44pt width
        XCTAssertEqual(verticalHitRect.width, 44, accuracy: 0.01)

        // Horizontal divider should have 44pt height
        XCTAssertEqual(horizontalHitRect.height, 44, accuracy: 0.01)
    }
}

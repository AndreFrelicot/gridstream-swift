//
//  VariableLayoutTests.swift
//  gridstream-ipadTests
//

import XCTest
import SwiftUI
@testable import gridstream_ipad

@MainActor
final class VariableLayoutTests: XCTestCase {

    private let availableSize = CGSize(width: 1024, height: 768)
    private let spacing: CGFloat = 8

    // MARK: - Asymmetric Layout Frame Calculations

    func testOnePlusTwoPresetFrameCalculationsHorizontal() async {
        // 1+2 layout in horizontal orientation:
        // One large tile on left, two smaller tiles stacked on right
        let frames = AsymmetricLayoutCalculator.calculateFrames(
            preset: .onePlusTwo,
            orientation: .horizontal,
            availableSize: availableSize,
            spacing: spacing
        )

        XCTAssertEqual(frames.count, 3)

        // First tile should take majority of left side
        let firstFrame = frames[0]
        XCTAssertEqual(firstFrame.origin.x, 0, accuracy: 0.01)
        XCTAssertEqual(firstFrame.origin.y, 0, accuracy: 0.01)
        XCTAssertGreaterThan(firstFrame.width, availableSize.width * 0.5)
        XCTAssertEqual(firstFrame.height, availableSize.height, accuracy: 0.01)

        // Second and third tiles should be stacked on right
        let secondFrame = frames[1]
        let thirdFrame = frames[2]

        XCTAssertGreaterThan(secondFrame.origin.x, firstFrame.maxX)
        XCTAssertEqual(secondFrame.origin.y, 0, accuracy: 0.01)

        XCTAssertGreaterThan(thirdFrame.origin.x, firstFrame.maxX)
        XCTAssertGreaterThan(thirdFrame.origin.y, secondFrame.maxY)
    }

    func testOnePlusTwoPresetFrameCalculationsVertical() async {
        // 1+2 layout in vertical orientation:
        // One large tile on top, two smaller tiles side by side on bottom
        let frames = AsymmetricLayoutCalculator.calculateFrames(
            preset: .onePlusTwo,
            orientation: .vertical,
            availableSize: availableSize,
            spacing: spacing
        )

        XCTAssertEqual(frames.count, 3)

        // First tile should take majority of top
        let firstFrame = frames[0]
        XCTAssertEqual(firstFrame.origin.x, 0, accuracy: 0.01)
        XCTAssertEqual(firstFrame.origin.y, 0, accuracy: 0.01)
        XCTAssertEqual(firstFrame.width, availableSize.width, accuracy: 0.01)
        XCTAssertGreaterThan(firstFrame.height, availableSize.height * 0.5)

        // Second and third tiles should be side by side on bottom
        let secondFrame = frames[1]
        let thirdFrame = frames[2]

        XCTAssertEqual(secondFrame.origin.x, 0, accuracy: 0.01)
        XCTAssertGreaterThan(secondFrame.origin.y, firstFrame.maxY)

        XCTAssertGreaterThan(thirdFrame.origin.x, secondFrame.maxX)
        XCTAssertGreaterThan(thirdFrame.origin.y, firstFrame.maxY)
    }

    // MARK: - Divider Position Tests

    func testDividerPositionsDerivedFromTileRatios() async {
        let frames = AsymmetricLayoutCalculator.calculateFrames(
            preset: .onePlusTwo,
            orientation: .horizontal,
            availableSize: availableSize,
            spacing: spacing
        )

        let dividers = DividerCalculator.calculateDividers(
            from: frames,
            preset: .onePlusTwo,
            orientation: .horizontal,
            availableSize: availableSize
        )

        // 1+2 horizontal should have one vertical divider and one horizontal divider
        XCTAssertGreaterThanOrEqual(dividers.count, 1)

        // Find vertical divider between large tile and smaller tiles
        let verticalDivider = dividers.first { $0.axis == .vertical }
        XCTAssertNotNil(verticalDivider)

        // Divider position should be between first tile and second/third tiles
        if let divider = verticalDivider {
            let firstFrame = frames[0]
            XCTAssertEqual(divider.position, firstFrame.maxX + spacing / 2, accuracy: 1.0)
            XCTAssertTrue(divider.affectedTileIndices.contains(0))
        }
    }

    // MARK: - Size Constraint Tests

    func testMinimumSizeConstraintsEnforced() async {
        // Create tile layouts with ratios below minimum
        let tileLayouts = [
            TileLayout(index: 0, widthRatio: 0.05, heightRatio: 1.0),
            TileLayout(index: 1, widthRatio: 0.95, heightRatio: 1.0)
        ]

        // Verify TileLayout clamping works
        XCTAssertGreaterThanOrEqual(tileLayouts[0].widthRatio, TileLayout.minimumRatio)
    }

    func testMaximumSizeConstraintsEnforced() async {
        // Create tile layouts with ratios above maximum
        let tileLayouts = [
            TileLayout(index: 0, widthRatio: 0.9, heightRatio: 1.0),
            TileLayout(index: 1, widthRatio: 0.1, heightRatio: 1.0)
        ]

        // Verify TileLayout clamping works
        XCTAssertLessThanOrEqual(tileLayouts[0].widthRatio, TileLayout.maximumRatio)
    }

    // MARK: - Spacing Tests

    func testSpacingMaintainedBetweenAllTiles() async {
        let frames = AsymmetricLayoutCalculator.calculateFrames(
            preset: .onePlusTwo,
            orientation: .horizontal,
            availableSize: availableSize,
            spacing: spacing
        )

        // Check spacing between tile 0 and tile 1
        let frame0 = frames[0]
        let frame1 = frames[1]
        let frame2 = frames[2]

        // Horizontal gap between tile 0 and tile 1
        let horizontalGap = frame1.minX - frame0.maxX
        XCTAssertEqual(horizontalGap, spacing, accuracy: 0.01)

        // Vertical gap between tile 1 and tile 2
        let verticalGap = frame2.minY - frame1.maxY
        XCTAssertEqual(verticalGap, spacing, accuracy: 0.01)
    }

    // MARK: - Divider Hit Rect Tests

    func testDividerHitRectFor44ptTouchTarget() async {
        let divider = DividerPosition(
            axis: .vertical,
            position: 500,
            affectedTileIndices: [0, 1],
            length: 768
        )

        let hitRect = divider.hitRect(touchSize: 44)

        // Touch target should be 44pt wide for vertical divider
        XCTAssertEqual(hitRect.width, 44, accuracy: 0.01)
        XCTAssertEqual(hitRect.height, 768, accuracy: 0.01)

        // Should be centered on the divider position
        XCTAssertEqual(hitRect.midX, 500, accuracy: 0.01)
    }

    // MARK: - GridLayout Variable Sizing Extension

    func testGridLayoutCalculateVariableFrames() async {
        let tileLayouts = [
            TileLayout(index: 0, widthRatio: 0.66, heightRatio: 1.0),
            TileLayout(index: 1, widthRatio: 0.34, heightRatio: 0.5),
            TileLayout(index: 2, widthRatio: 0.34, heightRatio: 0.5)
        ]

        let frames = GridLayout.calculateVariable(
            preset: .onePlusTwo,
            orientation: .horizontal,
            tileLayouts: tileLayouts,
            availableSize: availableSize,
            spacing: spacing
        )

        XCTAssertEqual(frames.count, 3)

        // Frames should respect the ratios
        let totalWidth = availableSize.width - spacing
        let expectedFirstWidth = totalWidth * 0.66
        XCTAssertEqual(frames[0].width, expectedFirstWidth, accuracy: 1.0)
    }
}

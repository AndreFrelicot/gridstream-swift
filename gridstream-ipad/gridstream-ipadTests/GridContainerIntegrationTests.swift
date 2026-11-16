//
//  GridContainerIntegrationTests.swift
//  gridstream-ipadTests
//

import XCTest
import SwiftUI
@testable import gridstream_ipad

@MainActor
final class GridContainerIntegrationTests: XCTestCase {

    // MARK: - Divider Rendering Tests

    func testGridContainerRendersDividersWhenUsingAsymmetricPreset() async {
        // Given a GridState with 3 tiles and an asymmetric preset
        let gridState = GridState()
        gridState.setTileCount(3)
        gridState.setPreset(.onePlusTwo)

        // When calculating frames and dividers
        let availableSize = CGSize(width: 1024, height: 768)
        let frames = AsymmetricLayoutCalculator.calculateFrames(
            preset: .onePlusTwo,
            orientation: gridState.orientation,
            availableSize: availableSize,
            tileLayouts: gridState.tileRatios
        )

        let dividers = DividerCalculator.calculateDividers(
            from: frames,
            preset: .onePlusTwo,
            orientation: gridState.orientation,
            availableSize: availableSize
        )

        // Then dividers should be calculated
        XCTAssertFalse(dividers.isEmpty, "Asymmetric preset should produce dividers")
        XCTAssertEqual(dividers.count, 2, "1+2 layout should have 2 dividers")
    }

    func testGridContainerNoDividersForSymmetricPreset() async {
        // Given a GridState with symmetric preset
        let gridState = GridState()
        gridState.setTileCount(4)
        gridState.setPreset(.symmetric)

        // When calculating dividers
        let availableSize = CGSize(width: 1024, height: 768)
        let frames: [CGRect] = []  // Symmetric uses GridLayout.calculate, not asymmetric

        let dividers = DividerCalculator.calculateDividers(
            from: frames,
            preset: .symmetric,
            orientation: gridState.orientation,
            availableSize: availableSize
        )

        // Then no dividers should be rendered
        XCTAssertTrue(dividers.isEmpty, "Symmetric preset should not produce dividers")
    }

    // MARK: - Divider Drag Tests

    func testDividerDragUpdatesTileRatiosInGridState() async {
        // Given a GridState with asymmetric preset
        let gridState = GridState()
        gridState.setTileCount(3)
        gridState.setPreset(.onePlusTwo)

        let initialRatio = gridState.tileRatios[0].widthRatio

        // When updating tile ratio (simulating divider drag)
        gridState.updateTileRatio(at: 0, widthRatio: 0.65, heightRatio: nil)

        // Then tile ratio should be updated
        XCTAssertNotEqual(gridState.tileRatios[0].widthRatio, initialRatio)
        XCTAssertEqual(gridState.tileRatios[0].widthRatio, 0.65, accuracy: 0.01)
    }

    func testDividerDragRespectsMinMaxConstraints() async {
        // Given a GridState with asymmetric preset
        let gridState = GridState()
        gridState.setTileCount(3)
        gridState.setPreset(.onePlusTwo)

        // When trying to set ratio below minimum (0.1)
        gridState.updateTileRatio(at: 0, widthRatio: 0.05, heightRatio: nil)

        // Then ratio should be clamped to minimum
        XCTAssertGreaterThanOrEqual(gridState.tileRatios[0].widthRatio, TileLayout.minimumRatio)

        // When trying to set ratio above maximum (0.75)
        gridState.updateTileRatio(at: 0, widthRatio: 0.9, heightRatio: nil)

        // Then ratio should be clamped to maximum
        XCTAssertLessThanOrEqual(gridState.tileRatios[0].widthRatio, TileLayout.maximumRatio)
    }

    // MARK: - Orientation Change Tests

    func testLayoutRecalculatesOnOrientationChange() async {
        // Given a GridState with an asymmetric preset
        let gridState = GridState()
        gridState.setTileCount(3)
        gridState.setPreset(.onePlusTwo)

        let availableSize = CGSize(width: 1024, height: 768)

        // Calculate frames with horizontal orientation
        gridState.setOrientation(.horizontal)
        let horizontalFrames = AsymmetricLayoutCalculator.calculateFrames(
            preset: .onePlusTwo,
            orientation: .horizontal,
            availableSize: availableSize
        )

        // When changing to vertical orientation
        gridState.setOrientation(.vertical)
        let verticalFrames = AsymmetricLayoutCalculator.calculateFrames(
            preset: .onePlusTwo,
            orientation: .vertical,
            availableSize: availableSize
        )

        // Then layout should be different
        XCTAssertNotEqual(horizontalFrames[0], verticalFrames[0], "Orientation change should produce different layout")
        XCTAssertEqual(gridState.orientation, .vertical)
    }
}

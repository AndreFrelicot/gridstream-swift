//
//  GridLayoutTests.swift
//  gridstream-ipadTests
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class GridLayoutTests: XCTestCase {

    func testOneByOneLayoutCalculation() async {
        let availableSize = CGSize(width: 1024, height: 768)
        let layout = GridLayout.calculate(for: .oneByOne, availableSize: availableSize)

        XCTAssertEqual(layout.columns, 1)
        XCTAssertEqual(layout.rows, 1)
        XCTAssertEqual(layout.tileSize.width, 1024, accuracy: 0.01)
        XCTAssertEqual(layout.tileSize.height, 768, accuracy: 0.01)
    }

    func testTwoByTwoLayoutCalculation() async {
        let availableSize = CGSize(width: 1024, height: 768)
        let spacing: CGFloat = 8
        let layout = GridLayout.calculate(for: .twoByTwo, availableSize: availableSize, spacing: spacing)

        let expectedWidth = (1024 - spacing) / 2
        let expectedHeight = (768 - spacing) / 2

        XCTAssertEqual(layout.columns, 2)
        XCTAssertEqual(layout.rows, 2)
        XCTAssertEqual(layout.tileSize.width, expectedWidth, accuracy: 0.01)
        XCTAssertEqual(layout.tileSize.height, expectedHeight, accuracy: 0.01)
    }

    func testSpacingAccountedInCalculations() async {
        let availableSize = CGSize(width: 100, height: 100)
        let spacing: CGFloat = 10

        let layoutWithSpacing = GridLayout.calculate(for: .twoByTwo, availableSize: availableSize, spacing: spacing)
        let layoutWithoutSpacing = GridLayout.calculate(for: .twoByTwo, availableSize: availableSize, spacing: 0)

        XCTAssertLessThan(layoutWithSpacing.tileSize.width, layoutWithoutSpacing.tileSize.width)
        XCTAssertLessThan(layoutWithSpacing.tileSize.height, layoutWithoutSpacing.tileSize.height)
    }

    func testFrameCalculation() async {
        let availableSize = CGSize(width: 1000, height: 1000)
        let spacing: CGFloat = 10
        let layout = GridLayout.calculate(for: .twoByTwo, availableSize: availableSize, spacing: spacing)

        let frame0 = layout.frame(forIndex: 0)
        let frame1 = layout.frame(forIndex: 1)
        let frame2 = layout.frame(forIndex: 2)

        XCTAssertEqual(frame0.origin.x, 0, accuracy: 0.01)
        XCTAssertEqual(frame0.origin.y, 0, accuracy: 0.01)

        XCTAssertEqual(frame1.origin.x, layout.tileSize.width + spacing, accuracy: 0.01)
        XCTAssertEqual(frame1.origin.y, 0, accuracy: 0.01)

        XCTAssertEqual(frame2.origin.x, 0, accuracy: 0.01)
        XCTAssertEqual(frame2.origin.y, layout.tileSize.height + spacing, accuracy: 0.01)
    }
}

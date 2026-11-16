//
//  GridConfigurationTests.swift
//  gridstream-ipadTests
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class GridConfigurationTests: XCTestCase {

    func testConfigurationFromTileCount() async {
        XCTAssertEqual(GridConfiguration.configuration(forTileCount: 1), .oneByOne)
        XCTAssertEqual(GridConfiguration.configuration(forTileCount: 2), .oneByTwo)
        XCTAssertEqual(GridConfiguration.configuration(forTileCount: 4), .twoByTwo)
        XCTAssertEqual(GridConfiguration.configuration(forTileCount: 6), .twoByThree)
        XCTAssertEqual(GridConfiguration.configuration(forTileCount: 9), .threeByThree)
        XCTAssertEqual(GridConfiguration.configuration(forTileCount: 12), .threeByFour)
    }

    func testColumnsAndRowsComputedCorrectly() async {
        XCTAssertEqual(GridConfiguration.oneByOne.columns, 1)
        XCTAssertEqual(GridConfiguration.oneByOne.rows, 1)

        XCTAssertEqual(GridConfiguration.twoByTwo.columns, 2)
        XCTAssertEqual(GridConfiguration.twoByTwo.rows, 2)

        XCTAssertEqual(GridConfiguration.threeByFour.columns, 4)
        XCTAssertEqual(GridConfiguration.threeByFour.rows, 3)
    }

    func testTileCountComputedCorrectly() async {
        XCTAssertEqual(GridConfiguration.oneByOne.tileCount, 1)
        XCTAssertEqual(GridConfiguration.oneByTwo.tileCount, 2)
        XCTAssertEqual(GridConfiguration.twoByTwo.tileCount, 4)
        XCTAssertEqual(GridConfiguration.twoByThree.tileCount, 6)
        XCTAssertEqual(GridConfiguration.threeByThree.tileCount, 9)
        XCTAssertEqual(GridConfiguration.threeByFour.tileCount, 12)
    }
}

//
//  GridStateTests.swift
//  gridstream-ipadTests
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class GridStateTests: XCTestCase {

    func testInitialStateHasSingleTile() async {
        let state = GridState()

        XCTAssertEqual(state.tiles.count, 1)
        XCTAssertEqual(state.currentConfiguration, .oneByOne)
        XCTAssertNil(state.selectedTileIndex)
    }

    func testAddTileIncreasesCount() async {
        let state = GridState()

        state.addTile()
        XCTAssertEqual(state.tiles.count, 2)

        state.addTile()
        XCTAssertEqual(state.tiles.count, 3)
    }

    func testRemoveTileDecreasesCount() async {
        let state = GridState()
        state.addTile()
        state.addTile()
        state.selectTile(at: 1)

        state.removeSelectedTile()

        XCTAssertEqual(state.tiles.count, 2)
    }

    func testCannotRemoveLastTile() async {
        let state = GridState()
        state.selectTile(at: 0)

        state.removeSelectedTile()

        XCTAssertEqual(state.tiles.count, 1)
    }

    func testRemoveTileClearsSelectionWhenSelectedRemoved() async {
        let state = GridState()
        state.addTile()
        state.selectTile(at: 1)

        state.removeSelectedTile()

        XCTAssertNil(state.selectedTileIndex)
    }

    func testSetTileCountAdjustsCorrectly() async {
        let state = GridState()

        state.setTileCount(4)
        XCTAssertEqual(state.tiles.count, 4)

        state.setTileCount(2)
        XCTAssertEqual(state.tiles.count, 2)
    }

    func testRemoveTilePreservesSimpleListAssignmentsWhenReindexing() async {
        let state = GridState()
        let listId = UUID()

        state.setTileCount(3)
        state.setSimpleList(listId, at: 2)

        state.removeTile(at: 0)

        XCTAssertEqual(state.tiles.count, 2)
        XCTAssertEqual(state.tiles[1].simpleListId, listId)
    }
}

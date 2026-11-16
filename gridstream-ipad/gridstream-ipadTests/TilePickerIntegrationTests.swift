//
//  TilePickerIntegrationTests.swift
//  gridstream-ipadTests
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class TilePickerIntegrationTests: XCTestCase {

    // MARK: - GridState selectedTileIndex Tests

    func testGridStateTracksSelectedTileForPicker() async {
        // Test that GridState.selectedTileIndex properly tracks which tile triggered the picker
        let state = GridState()
        state.setTileCount(4)

        // Select tile at index 2
        state.selectTile(at: 2)

        XCTAssertEqual(state.selectedTileIndex, 2, "selectedTileIndex should track the tile that was tapped")
    }

    // MARK: - Video Assignment Tests

    func testVideoSelectionAssignsURLToCorrectTile() async {
        // Test that video selection assigns the stream URL to the correct tile
        let state = GridState()
        state.setTileCount(4)

        let serverURL = URL(string: "http://localhost:8080")!
        let videoId = "test-video-id"
        let expectedStreamURL = VideoURLBuilder.buildStreamURL(from: serverURL, videoId: videoId)

        // Simulate selecting tile 2 and assigning video
        state.selectTile(at: 2)
        state.setVideoURL(expectedStreamURL, videoId: videoId, at: 2)

        XCTAssertEqual(state.tiles[2].videoURL, expectedStreamURL, "Tile at selected index should have the assigned video URL")
        XCTAssertEqual(state.tiles[2].videoId, videoId, "Tile at selected index should have the assigned video ID")
    }

    func testSameVideoCanBeAssignedToMultipleTiles() async {
        // Test that the same video can be assigned to different tiles (independent instances)
        let state = GridState()
        state.setTileCount(4)

        let serverURL = URL(string: "http://localhost:8080")!
        let videoId = "shared-video-id"
        let streamURL = VideoURLBuilder.buildStreamURL(from: serverURL, videoId: videoId)

        // Assign same video to tiles 0 and 2
        state.setVideoURL(streamURL, videoId: videoId, at: 0)
        state.setVideoURL(streamURL, videoId: videoId, at: 2)

        XCTAssertEqual(state.tiles[0].videoURL, streamURL, "Tile 0 should have the video URL")
        XCTAssertEqual(state.tiles[2].videoURL, streamURL, "Tile 2 should have the same video URL")
        XCTAssertEqual(state.tiles[0].videoId, state.tiles[2].videoId, "Both tiles should have the same video ID")
    }

    // MARK: - Empty Tile vs Tile With Video Tests

    func testTileWithVideoCanBeReassigned() async {
        // Test that a tile that already has a video can have a new video assigned
        let state = GridState()
        state.setTileCount(2)

        let serverURL = URL(string: "http://localhost:8080")!
        let firstVideoId = "first-video"
        let secondVideoId = "second-video"

        let firstURL = VideoURLBuilder.buildStreamURL(from: serverURL, videoId: firstVideoId)
        let secondURL = VideoURLBuilder.buildStreamURL(from: serverURL, videoId: secondVideoId)

        // Assign first video
        state.setVideoURL(firstURL, videoId: firstVideoId, at: 0)
        XCTAssertEqual(state.tiles[0].videoId, firstVideoId)

        // Reassign with second video (simulating picker selection)
        state.setVideoURL(secondURL, videoId: secondVideoId, at: 0)
        XCTAssertEqual(state.tiles[0].videoId, secondVideoId, "Tile should have new video after reassignment")
        XCTAssertEqual(state.tiles[0].videoURL, secondURL, "Tile should have new URL after reassignment")
    }
}

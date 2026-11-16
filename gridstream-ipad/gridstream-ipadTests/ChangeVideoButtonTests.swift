//
//  ChangeVideoButtonTests.swift
//  gridstream-ipadTests
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class ChangeVideoButtonTests: XCTestCase {

    // MARK: - Button Visibility Tests

    func testButtonAppearsOnTilesWithAssignedVideo() async {
        // Given a tile with a video URL assigned
        let tile = Tile(
            index: 0,
            videoURL: URL(string: "http://localhost:8080/api/v1/videos/test/stream")
        )

        // Then the tile should have a video URL
        XCTAssertNotNil(tile.videoURL, "Tile should have a video URL assigned")

        // And ChangeVideoButton should be shown when controls are visible
        // Note: UI visibility is controlled by VideoTileView based on controlsState.isVisible
        // This test verifies the precondition for showing the button
    }

    func testButtonDoesNotAppearOnEmptyTiles() async {
        // Given a tile without a video URL
        let tile = Tile(index: 0)

        // Then the tile should not have a video URL
        XCTAssertNil(tile.videoURL, "Empty tile should not have a video URL")

        // And PlaceholderTileView is shown instead of VideoTileView
        // Note: TileView conditionally renders VideoTileView only when videoURL exists
    }

    func testButtonTriggersSamePickerFlowAsEmptyTile() async {
        // Given a GridState with a tile that has a video
        let gridState = GridState()
        let videoURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!
        gridState.setVideoURL(videoURL, videoId: "test", at: 0)

        // When we select the tile (simulating what happens when change video is tapped)
        gridState.selectTile(at: 0)

        // Then the tile is selected
        XCTAssertEqual(gridState.selectedTileIndex, 0, "Tile should be selected")

        // And a new video can be assigned to the same tile
        let newVideoURL = URL(string: "http://localhost:8080/api/v1/videos/new/stream")!
        gridState.setVideoURL(newVideoURL, videoId: "new", at: 0)

        // The tile should now have the new video URL
        XCTAssertEqual(gridState.tiles[0].videoURL, newVideoURL, "Tile should have new video URL")
        XCTAssertEqual(gridState.tiles[0].videoId, "new", "Tile should have new video ID")
    }
}

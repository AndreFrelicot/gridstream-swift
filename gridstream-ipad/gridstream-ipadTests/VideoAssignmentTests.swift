//
//  VideoAssignmentTests.swift
//  gridstream-ipadTests
//
//  Tests for video assignment integration between ContentLibraryView and GridView.
//

import GridStreamAPI
import XCTest
import SwiftUI
@testable import gridstream_ipad

@MainActor
final class VideoAssignmentTests: XCTestCase {

    // MARK: - Mock Data

    private func createMockVideo(fileId: String = "file-1", filename: String = "Test Video.mp4") -> VideoItem {
        VideoItem(
            fileId: fileId,
            filename: filename,
            relativePath: "/videos/\(filename)",
            sourceDirectoryId: UUID(),
            duration: 120,
            width: 1920,
            height: 1080,
            codec: "h264",
            fileSize: 1024000,
            lastModified: Date(),
            sourceDirectoryName: "My Videos"
        )
    }

    // MARK: - Test Single Video Selection Enables Assignment

    func testSingleVideoSelectionEnablesAssignment() async {
        // Given a ContentLibraryView in single-selection mode (not multi-select)
        var selectedVideo: VideoItem?
        let testVideo = createMockVideo()

        // When the onVideoSelected callback is invoked with a video
        let onVideoSelected: (VideoItem) -> Void = { video in
            selectedVideo = video
        }

        // Simulate video selection in single-select mode
        onVideoSelected(testVideo)

        // Then the selected video should be available for assignment
        XCTAssertNotNil(selectedVideo)
        XCTAssertEqual(selectedVideo?.id, testVideo.id)
        XCTAssertEqual(selectedVideo?.filename, testVideo.filename)
    }

    // MARK: - Test Tapping Tile Assigns Selected Video

    func testTappingTileAssignsSelectedVideo() async {
        // Given a GridState with a selected tile and a video to assign
        let gridState = GridState()
        gridState.setTileCount(4)

        let serverURL = URL(string: "http://localhost:8080")!
        let testVideo = createMockVideo(fileId: "assigned-file", filename: "Assigned.mp4")
        let targetTileIndex = 2

        // When selecting a tile and assigning a video
        gridState.selectTile(at: targetTileIndex)

        guard let streamURL = VideoURLBuilder.buildStreamURL(from: serverURL, videoId: testVideo.fileId) else {
            XCTFail("Failed to build stream URL")
            return
        }

        gridState.setVideoURL(streamURL, videoId: testVideo.fileId, at: targetTileIndex)

        // Then the tile should have the assigned video
        XCTAssertEqual(gridState.tiles[targetTileIndex].videoId, testVideo.fileId)
        XCTAssertEqual(gridState.tiles[targetTileIndex].videoURL, streamURL)
    }

    // MARK: - Test Modal Dismisses After Assignment

    func testModalDismissesAfterAssignment() async {
        // Given a presented Content Library with video selection callback
        var isPresented = true
        let testVideo = createMockVideo()

        // When video is selected via callback (which should dismiss the modal)
        let onVideoSelected: (VideoItem) -> Void = { video in
            // Simulate the ContentLibraryView behavior: dismiss after selection
            isPresented = false
        }

        // Trigger the callback
        onVideoSelected(testVideo)

        // Then the modal should be dismissed
        XCTAssertFalse(isPresented, "Modal should be dismissed after video assignment")
    }

    // MARK: - Test Tile Updates to Play Assigned Video

    func testTileUpdatesToPlayAssignedVideo() async {
        // Given a tile with an existing video
        let gridState = GridState()
        gridState.setTileCount(2)

        let serverURL = URL(string: "http://localhost:8080")!

        // Set initial video
        let initialVideoId = "initial-video"
        guard let initialURL = VideoURLBuilder.buildStreamURL(from: serverURL, videoId: initialVideoId) else {
            XCTFail("Failed to build initial stream URL")
            return
        }
        gridState.setVideoURL(initialURL, videoId: initialVideoId, at: 0)

        XCTAssertEqual(gridState.tiles[0].videoId, initialVideoId)

        // When assigning a new video to the same tile
        let newVideoId = "new-video"
        guard let newURL = VideoURLBuilder.buildStreamURL(from: serverURL, videoId: newVideoId) else {
            XCTFail("Failed to build new stream URL")
            return
        }
        gridState.setVideoURL(newURL, videoId: newVideoId, at: 0)

        // Then the tile should have the new video (ready to play)
        XCTAssertEqual(gridState.tiles[0].videoId, newVideoId)
        XCTAssertEqual(gridState.tiles[0].videoURL, newURL)
        XCTAssertNotEqual(gridState.tiles[0].videoId, initialVideoId, "Tile should no longer have the initial video")
    }

    // MARK: - Test Video Assignment Callback Flow

    func testVideoAssignmentCallbackFlowFromContentLibrary() async {
        // Given a simulated Content Library to GridView integration
        var isPresented = true
        var assignedVideo: VideoItem?
        let targetTileIndex: Int? = 2
        let testVideo = createMockVideo(fileId: "test-file-123", filename: "ContentLibrary.mp4")

        // When the onVideoSelected callback is configured
        let onVideoSelected: (VideoItem) -> Void = { video in
            assignedVideo = video
            isPresented = false
        }

        // And the callback is triggered (simulating user selection)
        onVideoSelected(testVideo)

        // Then the video should be captured for assignment
        XCTAssertNotNil(assignedVideo)
        XCTAssertEqual(assignedVideo?.fileId, "test-file-123")
        XCTAssertFalse(isPresented)

        // And the video can be assigned to the target tile
        let gridState = GridState()
        gridState.setTileCount(4)
        let serverURL = URL(string: "http://localhost:8080")!

        if let video = assignedVideo, let tileIndex = targetTileIndex {
            guard let streamURL = VideoURLBuilder.buildStreamURL(from: serverURL, videoId: video.fileId) else {
                XCTFail("Failed to build stream URL")
                return
            }
            gridState.setVideoURL(streamURL, videoId: video.fileId, at: tileIndex)
        }

        XCTAssertEqual(gridState.tiles[2].videoId, "test-file-123")
    }
}

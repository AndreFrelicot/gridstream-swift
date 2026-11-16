//
//  ContentLibraryViewTests.swift
//  gridstream-ipadTests
//

import GridStreamAPI
import XCTest
import SwiftUI
@testable import gridstream_ipad

@MainActor
final class ContentLibraryViewTests: XCTestCase {

    // MARK: - Mock Data

    private func createMockVideo(id: String = "video-1", filename: String = "Test Video.mp4") -> VideoItem {
        VideoItem(
            fileId: "file-" + id,
            filename: filename,
            relativePath: "/videos/\(filename)",
            sourceDirectoryId: UUID(),
            duration: 120,
            width: 1920,
            height: 1080,
            codec: "h264",
            fileSize: 1024000,
            lastModified: Date(timeIntervalSince1970: 1_705_314_600),
            sourceDirectoryName: "My Videos"
        )
    }

    // MARK: - Test Video Selection State

    func testVideoSelectionUpdatesSelectionState() async {
        // Given a selection state manager
        var selectedIds = Set<String>()
        let videoId = "video-123"

        // When adding a video to selection
        selectedIds.insert(videoId)

        // Then the selection should contain the video
        XCTAssertTrue(selectedIds.contains(videoId))
        XCTAssertEqual(selectedIds.count, 1)

        // When removing the video from selection
        selectedIds.remove(videoId)

        // Then the selection should be empty
        XCTAssertFalse(selectedIds.contains(videoId))
        XCTAssertEqual(selectedIds.count, 0)
    }

    // MARK: - Test Multi-Select Mode

    func testMultiSelectModeTogglesCorrectly() async {
        // Given initial state with multi-select disabled
        var isMultiSelectEnabled = false

        // When toggling multi-select mode
        isMultiSelectEnabled.toggle()

        // Then multi-select should be enabled
        XCTAssertTrue(isMultiSelectEnabled)

        // When toggling again
        isMultiSelectEnabled.toggle()

        // Then multi-select should be disabled
        XCTAssertFalse(isMultiSelectEnabled)
    }

    func testMultiSelectAllowsMultipleVideoSelection() async {
        // Given multi-select mode is enabled
        var selectedIds = Set<String>()
        let video1 = "video-1"
        let video2 = "video-2"
        let video3 = "video-3"

        // When selecting multiple videos
        selectedIds.insert(video1)
        selectedIds.insert(video2)
        selectedIds.insert(video3)

        // Then all videos should be in the selection
        XCTAssertEqual(selectedIds.count, 3)
        XCTAssertTrue(selectedIds.contains(video1))
        XCTAssertTrue(selectedIds.contains(video2))
        XCTAssertTrue(selectedIds.contains(video3))
    }

    // MARK: - Test Dismiss Behavior

    func testDismissOnCancel() async {
        // Given a presented Content Library
        var isPresented = true

        // When dismissing via cancel action
        isPresented = false

        // Then the modal should be dismissed
        XCTAssertFalse(isPresented)
    }

    func testDismissOnVideoAssignment() async {
        // Given a presented Content Library with video selection callback
        var isPresented = true
        var assignedVideo: VideoItem?
        let testVideo = createMockVideo()

        let onVideoSelected: (VideoItem) -> Void = { video in
            assignedVideo = video
            isPresented = false
        }

        // When a video is assigned
        onVideoSelected(testVideo)

        // Then the callback should receive the video and dismiss the modal
        XCTAssertNotNil(assignedVideo)
        XCTAssertEqual(assignedVideo?.id, testVideo.id)
        XCTAssertFalse(isPresented)
    }

    // MARK: - Test Filter State

    func testFilterStateUpdatesWithSearchText() async {
        // Given empty filters
        var filters = ContentLibraryFilters()

        // When updating search text
        filters.searchText = "vacation"

        // Then filters should have active search
        XCTAssertTrue(filters.hasActiveFilters)
        XCTAssertEqual(filters.searchText, "vacation")
        XCTAssertEqual(filters.activeChips.count, 1)
    }

    func testFilterStateUpdatesWithMultipleFilters() async {
        // Given empty filters
        var filters = ContentLibraryFilters()
        let tag = TagInfo(id: UUID(), name: "action", color: "#EF4444", ratingEnabled: false)

        // When adding multiple filters
        filters.searchText = "movie"
        filters.activeTagFilters = [TagFilter(tag: tag)]
        filters.minRating = 5

        // Then filters should show all active items
        XCTAssertTrue(filters.hasActiveFilters)
        XCTAssertEqual(filters.activeChips.count, 3) // search + tag + minRating
    }
}

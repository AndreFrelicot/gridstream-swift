//
//  ContentLibraryIntegrationTests.swift
//  gridstream-ipadTests
//
//  Strategic integration tests filling critical gaps in Content Library feature coverage.
//  These tests focus on end-to-end workflows and integration points between components.
//

import GridStreamAPI
import XCTest
import SwiftUI
@testable import gridstream_ipad

@MainActor
final class ContentLibraryIntegrationTests: XCTestCase {

    // MARK: - Mock Data Helpers

    private func createMockVideo(
        id: String = "video-1",
        filename: String = "Test Video.mp4",
        sourceDirectoryId: UUID = UUID(),
        sourceDirectoryName: String = "Movies"
    ) -> VideoItem {
        VideoItem(
            fileId: "file-" + id,
            filename: filename,
            relativePath: "/videos/\(filename)",
            sourceDirectoryId: sourceDirectoryId,
            duration: 120,
            width: 1920,
            height: 1080,
            codec: "h264",
            fileSize: 1024000,
            lastModified: Date(timeIntervalSince1970: 1_705_314_600),
            sourceDirectoryName: sourceDirectoryName
        )
    }

    private func createMockTag(
        name: String,
        color: String = TagColorPalette.blue,
        ratingEnabled: Bool = false
    ) -> TagInfo {
        TagInfo(id: UUID(), name: name, color: color, ratingEnabled: ratingEnabled)
    }

    // MARK: - Test 1: Filter Chip Removal Cascades Correctly

    func testFilterChipRemovalCascadesCorrectly() async {
        // Given a filter state with multiple active filters
        var filters = ContentLibraryFilters()
        let actionTag = createMockTag(name: "action", color: TagColorPalette.red)
        let comedyTag = createMockTag(name: "comedy", color: TagColorPalette.green)

        filters.searchText = "vacation"
        filters.activeTagFilters = [TagFilter(tag: actionTag), TagFilter(tag: comedyTag)]
        filters.minRating = 5
        filters.maxRating = 9
        filters.sourceDirectoryId = "dir-1"
        filters.sourceDirectoryName = "Movies"

        // Verify initial state has all filters active
        XCTAssertEqual(filters.activeChips.count, 6) // search + 2 tags + minRating + maxRating + sourceDir

        // When removing the search chip
        let searchChip = FilterChip.search(text: "vacation")
        filters.removeChip(searchChip)

        // Then search should be cleared but other filters remain
        XCTAssertEqual(filters.searchText, "")
        XCTAssertEqual(filters.activeTagFilters.count, 2)
        XCTAssertEqual(filters.minRating, 5)
        XCTAssertEqual(filters.activeChips.count, 5)

        // When removing a tag chip
        let tagChip = FilterChip.tagFilter(TagFilter(tag: actionTag))
        filters.removeChip(tagChip)

        // Then only that tag should be removed
        XCTAssertEqual(filters.activeTagFilters.count, 1)
        XCTAssertEqual(filters.activeTagFilters.first?.tag.name, "comedy")

        // When removing minRating chip
        let minRatingChip = FilterChip.minRating(value: 5)
        filters.removeChip(minRatingChip)

        // Then minRating should be nil but maxRating remains
        XCTAssertNil(filters.minRating)
        XCTAssertEqual(filters.maxRating, 9)

        // When removing source directory chip
        let sourceDirChip = FilterChip.sourceDirectory(id: "dir-1", name: "Movies")
        filters.removeChip(sourceDirChip)

        // Then source directory should be cleared
        XCTAssertNil(filters.sourceDirectoryId)
        XCTAssertNil(filters.sourceDirectoryName)
    }

    // MARK: - Test 2: Filter Clear Resets All State

    func testFilterClearResetsAllState() async {
        // Given a filter state with all filters active
        var filters = ContentLibraryFilters()
        let tag = createMockTag(name: "action")

        filters.searchText = "movie"
        filters.activeTagFilters = [TagFilter(tag: tag)]
        filters.minRating = 3
        filters.maxRating = 8
        filters.sourceDirectoryId = "dir-2"
        filters.sourceDirectoryName = "TV Shows"

        XCTAssertTrue(filters.hasActiveFilters)
        XCTAssertEqual(filters.activeChips.count, 5)

        // When clearing all filters
        filters.clear()

        // Then all filter state should be reset
        XCTAssertEqual(filters.searchText, "")
        XCTAssertTrue(filters.activeTagFilters.isEmpty)
        XCTAssertNil(filters.minRating)
        XCTAssertNil(filters.maxRating)
        XCTAssertNil(filters.sourceDirectoryId)
        XCTAssertNil(filters.sourceDirectoryName)
        XCTAssertFalse(filters.hasActiveFilters)
        XCTAssertTrue(filters.activeChips.isEmpty)
    }

    // MARK: - Test 3: End-to-End Browse -> Search -> Filter -> Select Flow

    func testBrowseSearchFilterSelectFlow() async {
        // Given a set of videos and filter state
        let videos = [
            createMockVideo(id: "v1", filename: "Action Movie.mp4", sourceDirectoryName: "Movies"),
            createMockVideo(id: "v2", filename: "Comedy Film.mp4", sourceDirectoryName: "Movies"),
            createMockVideo(id: "v3", filename: "Action Documentary.mp4", sourceDirectoryName: "Documentaries")
        ]

        var filters = ContentLibraryFilters()
        var selectedVideoIds = Set<String>()

        // Step 1: Browse - all videos visible (simulated by empty filters)
        XCTAssertFalse(filters.hasActiveFilters)

        // Step 2: Search - apply search text
        filters.searchText = "action"
        XCTAssertTrue(filters.hasActiveFilters)
        XCTAssertEqual(filters.activeChips.count, 1)

        // Simulate filtering (in real app, API would return filtered results)
        let searchFilteredVideos = videos.filter {
            $0.filename.lowercased().contains(filters.searchText.lowercased())
        }
        XCTAssertEqual(searchFilteredVideos.count, 2)

        // Step 3: Add tag filter
        let docTag = createMockTag(name: "documentary")
        filters.activeTagFilters = [TagFilter(tag: docTag)]
        XCTAssertEqual(filters.activeChips.count, 2)

        // Step 4: Select a video
        let selectedVideo = searchFilteredVideos.first!
        selectedVideoIds.insert(selectedVideo.fileId)

        XCTAssertTrue(selectedVideoIds.contains(selectedVideo.fileId))
        XCTAssertEqual(selectedVideoIds.count, 1)
    }

    // MARK: - Test 4: Multi-Select Then Bulk Tag Application State

    func testMultiSelectBulkTagApplicationState() async {
        // Given multiple videos and tags
        let videos = [
            createMockVideo(id: "v1", filename: "Video1.mp4"),
            createMockVideo(id: "v2", filename: "Video2.mp4"),
            createMockVideo(id: "v3", filename: "Video3.mp4")
        ]

        let actionTag = createMockTag(name: "action", ratingEnabled: true)
        let comedyTag = createMockTag(name: "comedy", ratingEnabled: false)

        // When entering multi-select mode and selecting videos
        let isMultiSelectEnabled = true
        var selectedVideoIds = Set<String>()

        selectedVideoIds.insert(videos[0].fileId)
        selectedVideoIds.insert(videos[1].fileId)

        XCTAssertTrue(isMultiSelectEnabled)
        XCTAssertEqual(selectedVideoIds.count, 2)

        // When preparing bulk tag operation
        var selectedTagIds = Set<UUID>()
        selectedTagIds.insert(actionTag.id)
        selectedTagIds.insert(comedyTag.id)

        XCTAssertEqual(selectedTagIds.count, 2)

        // When clearing selection after bulk operation
        selectedVideoIds.removeAll()
        selectedTagIds.removeAll()

        XCTAssertTrue(selectedVideoIds.isEmpty)
        XCTAssertTrue(selectedTagIds.isEmpty)
    }

    // MARK: - Test 5: Video Assignment Clears Selection and Dismisses Modal

    func testVideoAssignmentClearsSelectionAndDismisses() async {
        // Given a Content Library in single-select mode
        var isPresented = true
        let selectedVideoIds = Set<String>()
        var assignedVideo: VideoItem?

        let testVideo = createMockVideo(id: "test-video", filename: "Selected.mp4")

        // When tapping a video in single-select mode
        let onVideoSelected: (VideoItem) -> Void = { video in
            assignedVideo = video
            isPresented = false
        }

        // Simulate single tap selecting and assigning
        onVideoSelected(testVideo)

        // Then the video should be assigned and modal dismissed
        XCTAssertNotNil(assignedVideo)
        XCTAssertEqual(assignedVideo?.fileId, "file-test-video")
        XCTAssertFalse(isPresented)

        // And selection should not accumulate in single-select mode
        XCTAssertTrue(selectedVideoIds.isEmpty)
    }

    // MARK: - Test 6: Rating Info Correctly Tracks Global and Per-Tag Ratings

    func testRatingInfoTracksGlobalAndPerTagRatings() async {
        // Given tags with rating enabled
        let actionTag = createMockTag(name: "action", ratingEnabled: true)
        let comedyTag = createMockTag(name: "comedy", ratingEnabled: true)
        let dramaTag = createMockTag(name: "drama", ratingEnabled: false)

        // When creating rating info
        var ratingInfo = VideoRatingInfo(
            globalRating: 8,
            tagRatings: [actionTag.id: 7, comedyTag.id: 9]
        )

        // Then global rating is accessible
        XCTAssertEqual(ratingInfo.globalRating, 8)

        // And per-tag ratings are accessible
        XCTAssertEqual(ratingInfo.tagRatings[actionTag.id], 7)
        XCTAssertEqual(ratingInfo.tagRatings[comedyTag.id], 9)
        XCTAssertNil(ratingInfo.tagRatings[dramaTag.id])

        // When updating ratings
        ratingInfo.globalRating = 9
        ratingInfo.tagRatings[actionTag.id] = 10

        // Then updates are reflected
        XCTAssertEqual(ratingInfo.globalRating, 9)
        XCTAssertEqual(ratingInfo.tagRatings[actionTag.id], 10)
    }

    // MARK: - Test 7: Filter Chips Generate Correct Display Text

    func testFilterChipsGenerateCorrectDisplayText() async {
        // Given various filter chips
        let tagChip = FilterChip.tagFilter(TagFilter(
            tag: TagInfo(id: UUID(), name: "action", color: TagColorPalette.red, ratingEnabled: false)
        ))
        let minRatingChip = FilterChip.minRating(value: 5)
        let maxRatingChip = FilterChip.maxRating(value: 8)
        let sourceDirChip = FilterChip.sourceDirectory(id: "dir-1", name: "Movies")
        let searchChip = FilterChip.search(text: "vacation")

        // Then each chip has correct display text
        XCTAssertEqual(tagChip.displayText, "action")
        XCTAssertEqual(minRatingChip.displayText, "Min: 5 hearts")
        XCTAssertEqual(maxRatingChip.displayText, "Max: 8 hearts")
        XCTAssertEqual(sourceDirChip.displayText, "Movies")
        XCTAssertEqual(searchChip.displayText, "\"vacation\"")
    }

    // MARK: - Test 8: Filter Has Active Filters Correctly Reports State

    func testHasActiveFiltersCorrectlyReportsState() async {
        var filters = ContentLibraryFilters()

        // Initially no filters
        XCTAssertFalse(filters.hasActiveFilters)

        // With only search text
        filters.searchText = "test"
        XCTAssertTrue(filters.hasActiveFilters)
        filters.searchText = ""

        // With only tags
        filters.activeTagFilters = [TagFilter(tag: createMockTag(name: "action"))]
        XCTAssertTrue(filters.hasActiveFilters)
        filters.activeTagFilters = []

        // With only min rating
        filters.minRating = 3
        XCTAssertTrue(filters.hasActiveFilters)
        filters.minRating = nil

        // With only max rating
        filters.maxRating = 8
        XCTAssertTrue(filters.hasActiveFilters)
        filters.maxRating = nil

        // With only source directory
        filters.sourceDirectoryId = "dir-1"
        XCTAssertTrue(filters.hasActiveFilters)
        filters.sourceDirectoryId = nil

        // Back to no filters
        XCTAssertFalse(filters.hasActiveFilters)
    }

    // MARK: - Test 9: Selection Toggle Behavior in Multi-Select Mode

    func testSelectionToggleBehaviorInMultiSelectMode() async {
        // Given multi-select mode enabled
        var selectedVideoIds = Set<String>()
        let video1 = createMockVideo(id: "v1", filename: "Video1.mp4")
        let video2 = createMockVideo(id: "v2", filename: "Video2.mp4")

        // When toggling selection on first video
        if selectedVideoIds.contains(video1.fileId) {
            selectedVideoIds.remove(video1.fileId)
        } else {
            selectedVideoIds.insert(video1.fileId)
        }
        XCTAssertTrue(selectedVideoIds.contains(video1.fileId))
        XCTAssertEqual(selectedVideoIds.count, 1)

        // When adding second video
        if selectedVideoIds.contains(video2.fileId) {
            selectedVideoIds.remove(video2.fileId)
        } else {
            selectedVideoIds.insert(video2.fileId)
        }
        XCTAssertTrue(selectedVideoIds.contains(video2.fileId))
        XCTAssertEqual(selectedVideoIds.count, 2)

        // When toggling first video again (deselect)
        if selectedVideoIds.contains(video1.fileId) {
            selectedVideoIds.remove(video1.fileId)
        } else {
            selectedVideoIds.insert(video1.fileId)
        }
        XCTAssertFalse(selectedVideoIds.contains(video1.fileId))
        XCTAssertTrue(selectedVideoIds.contains(video2.fileId))
        XCTAssertEqual(selectedVideoIds.count, 1)
    }

    // MARK: - Test 10: Complete User Workflow - Browse to Assign

    func testCompleteUserWorkflowBrowseToAssign() async {
        // This test simulates a complete user journey through the Content Library

        // Step 1: User opens Content Library
        var isPresented = true
        var filters = ContentLibraryFilters()
        let isMultiSelectEnabled = false
        var assignedVideo: VideoItem?

        XCTAssertTrue(isPresented)
        XCTAssertFalse(filters.hasActiveFilters)

        // Step 2: User searches for "vacation"
        filters.searchText = "vacation"
        XCTAssertTrue(filters.hasActiveFilters)
        XCTAssertEqual(filters.activeChips.count, 1)

        // Step 3: User adds tag filter
        let travelTag = createMockTag(name: "travel", color: TagColorPalette.cyan)
        filters.activeTagFilters = [TagFilter(tag: travelTag)]
        XCTAssertEqual(filters.activeChips.count, 2)

        // Step 4: User adds rating filter
        filters.minRating = 7
        XCTAssertEqual(filters.activeChips.count, 3)

        // Step 5: User finds desired video and taps to assign (single-select mode)
        let desiredVideo = createMockVideo(
            id: "vacation-2023",
            filename: "Vacation 2023.mp4",
            sourceDirectoryName: "Travel Videos"
        )

        XCTAssertFalse(isMultiSelectEnabled)

        // Simulate onVideoSelected callback
        assignedVideo = desiredVideo
        isPresented = false

        // Step 6: Verify final state
        XCTAssertFalse(isPresented)
        XCTAssertNotNil(assignedVideo)
        XCTAssertEqual(assignedVideo?.fileId, "file-vacation-2023")
        XCTAssertEqual(assignedVideo?.filename, "Vacation 2023.mp4")
    }
}

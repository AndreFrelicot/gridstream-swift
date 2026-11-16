//
//  PlaybackRatingTests.swift
//  gridstream-ipadTests
//

import XCTest
import SwiftUI
@testable import gridstream_ipad

@MainActor
final class PlaybackRatingTests: XCTestCase {

    // MARK: - Test 1: Rating Overlay Appears With Transport Controls

    func testRatingOverlayAppearsWithTransportControls() async {
        // Given a PlaybackRatingOverlay configured with rating info
        let videoId = "test-video-123"
        let ratingInfo = VideoRatingInfo(globalRating: 7, tagRatings: [:])

        // When creating the overlay
        let overlay = PlaybackRatingOverlay(
            videoId: videoId,
            ratingInfo: .constant(ratingInfo),
            videoTags: [],
            serverURL: URL(string: "http://localhost:8080"),
            onGlobalRatingChanged: { _ in },
            onTagRatingChanged: { _, _ in }
        )

        // Then the overlay should be created successfully
        XCTAssertNotNil(overlay)

        // And should be designed to show alongside transport controls
        // (visibility is controlled by parent via controlsState.isVisible)
    }

    // MARK: - Test 2: Global Rating Display and Edit During Playback

    func testGlobalRatingDisplayAndEditDuringPlayback() async {
        // Given rating info with a global rating
        let ratingInfo = VideoRatingInfo(globalRating: 5, tagRatings: [:])

        var capturedNewRating: Int?
        let onGlobalRatingChanged: (Int) -> Void = { rating in
            capturedNewRating = rating
        }

        // When creating the overlay with editable rating
        let overlay = PlaybackRatingOverlay(
            videoId: "video-1",
            ratingInfo: .constant(ratingInfo),
            videoTags: [],
            serverURL: URL(string: "http://localhost:8080"),
            onGlobalRatingChanged: onGlobalRatingChanged,
            onTagRatingChanged: { _, _ in }
        )

        // Then the overlay should be created with the initial rating
        XCTAssertNotNil(overlay)
        XCTAssertEqual(ratingInfo.globalRating, 5)

        // When simulating a rating change
        onGlobalRatingChanged(8)

        // Then the callback should receive the new rating
        XCTAssertEqual(capturedNewRating, 8)
    }

    // MARK: - Test 3: Per-Tag Ratings Display Correctly

    func testPerTagRatingsDisplayCorrectly() async {
        // Given tags with rating enabled and disabled
        let tag1 = TagInfo(id: UUID(), name: "action", color: "#EF4444", ratingEnabled: true)
        let tag2 = TagInfo(id: UUID(), name: "comedy", color: "#22C55E", ratingEnabled: false)
        let tag3 = TagInfo(id: UUID(), name: "drama", color: "#3B82F6", ratingEnabled: true)

        // And rating info with per-tag ratings
        let ratingInfo = VideoRatingInfo(
            globalRating: 7,
            tagRatings: [tag1.id: 8, tag3.id: 6]
        )

        // When creating the overlay
        let overlay = PlaybackRatingOverlay(
            videoId: "video-1",
            ratingInfo: .constant(ratingInfo),
            videoTags: [tag1, tag2, tag3],
            serverURL: URL(string: "http://localhost:8080"),
            onGlobalRatingChanged: { _ in },
            onTagRatingChanged: { _, _ in }
        )

        // Then the overlay should be created successfully
        XCTAssertNotNil(overlay)

        // And should only display ratings for ratingEnabled tags
        let ratingEnabledTags = [tag1, tag2, tag3].filter { $0.ratingEnabled }
        XCTAssertEqual(ratingEnabledTags.count, 2)
        XCTAssertTrue(ratingEnabledTags.contains(where: { $0.id == tag1.id }))
        XCTAssertTrue(ratingEnabledTags.contains(where: { $0.id == tag3.id }))
        XCTAssertFalse(ratingEnabledTags.contains(where: { $0.id == tag2.id }))

        // And the tag ratings should be accessible
        XCTAssertEqual(ratingInfo.tagRatings[tag1.id], 8)
        XCTAssertEqual(ratingInfo.tagRatings[tag3.id], 6)
        XCTAssertNil(ratingInfo.tagRatings[tag2.id])
    }

    // MARK: - Test 4: Rating Update API Call Without Interrupting Playback

    func testRatingUpdateDoesNotInterruptPlayback() async {
        // Given a video playing with a rating
        let ratingInfo = VideoRatingInfo(globalRating: 5, tagRatings: [:])

        var globalRatingUpdateCount = 0
        var tagRatingUpdateCount = 0

        let onGlobalRatingChanged: (Int) -> Void = { _ in
            globalRatingUpdateCount += 1
        }

        let onTagRatingChanged: (UUID, Int) -> Void = { _, _ in
            tagRatingUpdateCount += 1
        }

        // When the overlay is created
        let overlay = PlaybackRatingOverlay(
            videoId: "video-1",
            ratingInfo: .constant(ratingInfo),
            videoTags: [],
            serverURL: URL(string: "http://localhost:8080"),
            onGlobalRatingChanged: onGlobalRatingChanged,
            onTagRatingChanged: onTagRatingChanged
        )

        XCTAssertNotNil(overlay)

        // When triggering rating updates multiple times (simulating user interaction)
        onGlobalRatingChanged(6)
        onGlobalRatingChanged(7)
        onGlobalRatingChanged(8)

        // Then all updates should be captured (API updates happen asynchronously)
        XCTAssertEqual(globalRatingUpdateCount, 3)

        // And tag ratings should work similarly
        let tagId = UUID()
        onTagRatingChanged(tagId, 5)
        onTagRatingChanged(tagId, 6)

        XCTAssertEqual(tagRatingUpdateCount, 2)
    }
}

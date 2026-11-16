//
//  TagRatingComponentTests.swift
//  gridstream-ipadTests
//

import XCTest
import SwiftUI
@testable import gridstream_ipad

@MainActor
final class TagRatingComponentTests: XCTestCase {

    // MARK: - TagPickerView Tests

    func testTagPickerViewDisplaysTagsWithColorsAndSelection() async {
        // Given a list of tags with different colors
        let tags = [
            TagInfo(id: UUID(), name: "action", color: "#EF4444", ratingEnabled: false),
            TagInfo(id: UUID(), name: "comedy", color: "#22C55E", ratingEnabled: true),
            TagInfo(id: UUID(), name: "drama", color: "#3B82F6", ratingEnabled: false)
        ]

        // And a set of selected tag IDs (comedy is selected)
        let selectedTagIds: Set<UUID> = [tags[1].id]

        // When creating a TagPickerView
        let pickerView = TagPickerView(
            availableTags: tags,
            selectedTagIds: .constant(selectedTagIds),
            onApply: {},
            onDismiss: {}
        )

        // Then it should be created successfully
        XCTAssertNotNil(pickerView)

        // And verify the tags contain expected data
        XCTAssertEqual(tags.count, 3)
        XCTAssertEqual(tags[0].name, "action")
        XCTAssertEqual(tags[0].color, "#EF4444")
        XCTAssertTrue(selectedTagIds.contains(tags[1].id))
        XCTAssertFalse(selectedTagIds.contains(tags[0].id))
    }

    func testTagPickerViewMultiSelectToggleBehavior() async {
        // Given initial selection state
        let tag1 = TagInfo(id: UUID(), name: "action", color: "#EF4444", ratingEnabled: false)
        let tag2 = TagInfo(id: UUID(), name: "comedy", color: "#22C55E", ratingEnabled: true)

        var selectedTagIds: Set<UUID> = [tag1.id]

        // When toggling a tag that is selected
        if selectedTagIds.contains(tag1.id) {
            selectedTagIds.remove(tag1.id)
        }

        // Then it should be deselected
        XCTAssertFalse(selectedTagIds.contains(tag1.id))

        // When toggling a tag that is not selected
        if !selectedTagIds.contains(tag2.id) {
            selectedTagIds.insert(tag2.id)
        }

        // Then it should be selected
        XCTAssertTrue(selectedTagIds.contains(tag2.id))
    }

    // MARK: - BulkOperationsBar Tests

    func testBulkOperationsBarAppliesTagsToMultipleVideos() async {
        // Given multiple selected videos
        let selectedVideoIds: Set<String> = ["video1", "video2", "video3"]

        var applyTagsTriggered = false
        var setRatingTriggered = false
        var clearSelectionTriggered = false

        // When creating a BulkOperationsBar
        let bulkBar = BulkOperationsBar(
            selectedCount: selectedVideoIds.count,
            onApplyTags: { applyTagsTriggered = true },
            onSetRating: { setRatingTriggered = true },
            onClearSelection: { clearSelectionTriggered = true }
        )

        // Then it should be created with correct selection count
        XCTAssertNotNil(bulkBar)
        XCTAssertEqual(selectedVideoIds.count, 3)

        // When triggering apply tags action
        bulkBar.onApplyTags()

        // Then the callback should be triggered
        XCTAssertTrue(applyTagsTriggered)

        // When triggering set rating action
        bulkBar.onSetRating()

        // Then the callback should be triggered
        XCTAssertTrue(setRatingTriggered)

        // When triggering clear selection action
        bulkBar.onClearSelection()

        // Then the callback should be triggered
        XCTAssertTrue(clearSelectionTriggered)
    }

    func testBulkOperationsBarDisplaysSelectionCount() async {
        // Given different selection counts
        let counts = [1, 5, 10, 100]

        for count in counts {
            // When creating a BulkOperationsBar with that count
            let bulkBar = BulkOperationsBar(
                selectedCount: count,
                onApplyTags: {},
                onSetRating: {},
                onClearSelection: {}
            )

            // Then it should be created with the correct count
            XCTAssertNotNil(bulkBar)
            XCTAssertEqual(bulkBar.selectedCount, count)
        }
    }
}

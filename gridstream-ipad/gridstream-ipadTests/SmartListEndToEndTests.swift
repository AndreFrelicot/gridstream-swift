//
//  SmartListEndToEndTests.swift
//  gridstream-ipadTests
//
//  Strategic end-to-end tests for Smart List feature covering:
//  - Tile with Smart List attachment workflows
//  - Complete criteria type coverage
//  - Query parameter building for all criteria
//  - Empty criteria edge cases
//

import GridStreamAPI
import XCTest
@testable import gridstream_ipad

@MainActor
final class SmartListEndToEndTests: XCTestCase {

    // MARK: - Tile + Smart List Attachment Workflow Tests

    /// Test that a tile can be created with a Smart List attachment
    func testTileWithSmartListAttachment() async {
        // Given: A Smart List ID
        let smartListId = UUID()

        // When: Creating a tile with the Smart List attached
        let tile = Tile(
            index: 0,
            smartListId: smartListId
        )

        // Then: The tile has the Smart List ID set
        XCTAssertEqual(tile.smartListId, smartListId)
        XCTAssertFalse(tile.hasVideo) // No video assigned yet
    }

    /// Test that a tile without Smart List shows full catalog behavior
    func testTileWithoutSmartListHasNoFilter() async {
        // Given/When: Creating a tile without a Smart List
        let tile = Tile(index: 0)

        // Then: No Smart List is attached (full catalog behavior)
        XCTAssertNil(tile.smartListId)
    }

    /// Test updating tile's Smart List attachment
    func testTileSmartListAttachmentUpdate() async {
        // Given: A tile with no Smart List
        var tile = Tile(index: 0)
        XCTAssertNil(tile.smartListId)

        // When: Attaching a Smart List
        let smartListId = UUID()
        tile.smartListId = smartListId

        // Then: Tile has the Smart List attached
        XCTAssertEqual(tile.smartListId, smartListId)

        // When: Clearing the Smart List
        tile.smartListId = nil

        // Then: Tile returns to full catalog behavior
        XCTAssertNil(tile.smartListId)
    }

    // MARK: - All Criteria Types Combined Test

    /// Test that all 7 criteria categories can be combined in a single Smart List
    func testAllCriteriaTypesCombined() async {
        // Given: Conditions from all 7 categories
        let tagId = UUID()
        let testDate = Date()
        let conditions: [FilterCondition] = [
            FilterCondition(criteriaType: .tagsInclude(tagIds: [tagId], tagRatings: []), logicOperator: .and),
            FilterCondition(criteriaType: .ratingMin(value: 3), logicOperator: .and),
            FilterCondition(criteriaType: .sourceDirectory(id: "source-123"), logicOperator: .and),
            FilterCondition(criteriaType: .fileSizeMin(megabytes: 100.0), logicOperator: .and),
            FilterCondition(criteriaType: .filenameContains(text: "video"), logicOperator: .and),
            FilterCondition(criteriaType: .dateAddedAfter(date: testDate), logicOperator: .and),
            FilterCondition(criteriaType: .playCountMin(value: 5), logicOperator: .and)
        ]

        // When: Creating criteria with all conditions
        let criteria = SmartListCriteria(conditions: conditions)

        // Then: All conditions are present
        XCTAssertEqual(criteria.conditions.count, 7)
        XCTAssertEqual(String(localized: criteria.summary), "7 filters")

        // And: Each category is represented
        let categories = criteria.conditions.map { $0.criteriaType.category }
        XCTAssertTrue(categories.contains(.tags))
        XCTAssertTrue(categories.contains(.rating))
        XCTAssertTrue(categories.contains(.source))
        XCTAssertTrue(categories.contains(.fileSize))
        XCTAssertTrue(categories.contains(.filename))
        XCTAssertTrue(categories.contains(.date))
        XCTAssertTrue(categories.contains(.playCount))
    }

    // MARK: - Tag Deletion Cascading to Smart List Tests

    /// Test finding all Smart Lists affected by a tag deletion
    func testFindAllSmartListsAffectedByTagDeletion() async {
        // Given: Multiple Smart Lists, some referencing a tag
        let targetTagId = UUID()
        let otherTagId = UUID()

        let smartListWithTag = SmartListInfo(
            name: "Uses Target Tag",
            criteria: SmartListCriteria(conditions: [
                FilterCondition(criteriaType: .tagsInclude(tagIds: [targetTagId], tagRatings: []), logicOperator: .and)
            ])
        )

        let smartListWithOtherTag = SmartListInfo(
            name: "Uses Other Tag",
            criteria: SmartListCriteria(conditions: [
                FilterCondition(criteriaType: .tagsInclude(tagIds: [otherTagId], tagRatings: []), logicOperator: .and)
            ])
        )

        let smartListWithBothTags = SmartListInfo(
            name: "Uses Both Tags",
            criteria: SmartListCriteria(conditions: [
                FilterCondition(criteriaType: .tagsInclude(tagIds: [targetTagId, otherTagId], tagRatings: []), logicOperator: .and)
            ])
        )

        let smartListNoTags = SmartListInfo(
            name: "No Tags",
            criteria: SmartListCriteria(conditions: [
                FilterCondition(criteriaType: .ratingMin(value: 3), logicOperator: .and)
            ])
        )

        let allSmartLists = [smartListWithTag, smartListWithOtherTag, smartListWithBothTags, smartListNoTags]

        // When: Finding Smart Lists containing the target tag
        let affectedSmartLists = SmartListQueryBuilder.findSmartListsContainingTag(allSmartLists, tagId: targetTagId)

        // Then: Only the Smart Lists referencing the target tag are returned
        XCTAssertEqual(affectedSmartLists.count, 2)
        XCTAssertTrue(affectedSmartLists.contains { $0.name == "Uses Target Tag" })
        XCTAssertTrue(affectedSmartLists.contains { $0.name == "Uses Both Tags" })
        XCTAssertFalse(affectedSmartLists.contains { $0.name == "Uses Other Tag" })
        XCTAssertFalse(affectedSmartLists.contains { $0.name == "No Tags" })
    }
}

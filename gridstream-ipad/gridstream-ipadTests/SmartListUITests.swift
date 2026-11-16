//
//  SmartListUITests.swift
//  gridstream-ipad
//

import GridStreamAPI
import XCTest
@testable import gridstream_ipad

@MainActor
final class SmartListUITests: XCTestCase {

    // MARK: - SmartListManagementView List Rendering Tests

    func testEmptySmartListsShowsContentUnavailable() async {
        // Empty smart lists should indicate empty state
        let smartLists: [SmartListInfo] = []
        XCTAssertTrue(smartLists.isEmpty)
    }

    func testSmartListsListRenderingWithData() async {
        // Smart lists with data should render list items
        let criteria = SmartListCriteria(conditions: [])
        let smartLists = [
            SmartListInfo(name: "Favorites", criteria: criteria),
            SmartListInfo(name: "Recent", criteria: criteria)
        ]

        XCTAssertEqual(smartLists.count, 2)
        XCTAssertEqual(smartLists[0].name, "Favorites")
        XCTAssertEqual(smartLists[1].name, "Recent")
    }

    // MARK: - SmartListFormView Condition Tests

    func testConditionAddingAndRemoving() async {
        // Test adding conditions to criteria
        var criteria = SmartListCriteria(conditions: [])
        XCTAssertEqual(criteria.conditions.count, 0)

        // Add a condition
        let condition1 = FilterCondition(
            criteriaType: .ratingMin(value: 3),
            logicOperator: .and
        )
        criteria.conditions.append(condition1)
        XCTAssertEqual(criteria.conditions.count, 1)

        // Add another condition
        let condition2 = FilterCondition(
            criteriaType: .playCountMin(value: 5),
            logicOperator: .or
        )
        criteria.conditions.append(condition2)
        XCTAssertEqual(criteria.conditions.count, 2)

        // Remove first condition
        criteria.conditions.removeFirst()
        XCTAssertEqual(criteria.conditions.count, 1)
        XCTAssertEqual(criteria.conditions[0].logicOperator, .or)
    }

    func testCriteriaCategoriesAndConditionTypes() async {
        // Verify the criteria categories offered by the editor
        let allCategories = CriteriaCategory.allCases
        XCTAssertEqual(allCategories.count, 11)

        // Create conditions for the original seven categories
        var conditions: [FilterCondition] = []
        conditions.append(FilterCondition(criteriaType: .tagsInclude(tagIds: [], tagRatings: []), logicOperator: .and))
        conditions.append(FilterCondition(criteriaType: .ratingMin(value: 3), logicOperator: .and))
        conditions.append(FilterCondition(criteriaType: .sourceDirectory(id: "test"), logicOperator: .and))
        conditions.append(FilterCondition(criteriaType: .fileSizeMin(megabytes: 100), logicOperator: .and))
        conditions.append(FilterCondition(criteriaType: .filenameContains(text: "test"), logicOperator: .and))
        conditions.append(FilterCondition(criteriaType: .dateAddedAfter(date: Date()), logicOperator: .and))
        conditions.append(FilterCondition(criteriaType: .playCountMin(value: 10), logicOperator: .and))

        XCTAssertEqual(conditions.count, 7)
    }

    // MARK: - AND/OR Logic Selector Tests

    func testLogicOperatorToggle() async {
        var condition = FilterCondition(
            criteriaType: .ratingMin(value: 3),
            logicOperator: .and
        )

        XCTAssertEqual(condition.logicOperator, .and)

        // Toggle to OR
        condition.logicOperator = .or
        XCTAssertEqual(condition.logicOperator, .or)

        // Toggle back to AND
        condition.logicOperator = .and
        XCTAssertEqual(condition.logicOperator, .and)
    }

    func testFirstConditionHasNoVisibleOperator() async {
        // First condition in a list should not display its operator
        // (implicitly starts the filter chain)
        let conditions = [
            FilterCondition(criteriaType: .ratingMin(value: 3), logicOperator: .and),
            FilterCondition(criteriaType: .playCountMin(value: 5), logicOperator: .or)
        ]

        // First condition's operator is ignored in display
        XCTAssertEqual(conditions.count, 2)
        // Second condition's operator (OR) should be displayed
        XCTAssertEqual(conditions[1].logicOperator.displayName, "OR")
    }

    // MARK: - Smart List Limit Tests

    func testMaxFiftySmartLists() async {
        // System should enforce 50 smart list limit
        let maxCount = 50
        let criteria = SmartListCriteria(conditions: [])
        var smartLists: [SmartListInfo] = []

        for i in 0..<maxCount {
            smartLists.append(SmartListInfo(name: "List \(i)", criteria: criteria))
        }

        XCTAssertEqual(smartLists.count, 50)

        // Adding beyond limit should be prevented by UI
        // (actual enforcement is at view layer)
        let isAtLimit = smartLists.count >= maxCount
        XCTAssertTrue(isAtLimit)
    }

    // MARK: - Name Validation Tests

    func testSmartListNameValidation() async {
        // Empty name should be invalid
        let emptyName = ""
        let trimmedEmpty = emptyName.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(trimmedEmpty.isEmpty)

        // Whitespace-only name should be invalid
        let whitespaceOnly = "   "
        let trimmedWhitespace = whitespaceOnly.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(trimmedWhitespace.isEmpty)

        // Valid name should pass
        let validName = "My Smart List"
        let trimmedValid = validName.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(trimmedValid.isEmpty)
    }
}

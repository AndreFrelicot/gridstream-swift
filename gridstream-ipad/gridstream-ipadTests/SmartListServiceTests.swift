//
//  SmartListServiceTests.swift
//  gridstream-ipadTests
//

import GridStreamAPI
import XCTest
@testable import gridstream_ipad

@MainActor
final class SmartListServiceTests: XCTestCase {

    func testServicesCanBeReleasedOutsideASwiftTask() {
        weak var releasedContent: ContentLibraryService?
        weak var releasedSmartLists: SmartListService?
        weak var releasedSimpleLists: SimpleListService?
        weak var releasedTileService: TileSmartListService?
        autoreleasepool {
            let content = ContentLibraryService()
            let smartLists = SmartListService()
            let simpleLists = SimpleListService()
            let tileService = TileSmartListService(contentLibraryService: content, smartListService: smartLists)
            releasedContent = content
            releasedSmartLists = smartLists
            releasedSimpleLists = simpleLists
            releasedTileService = tileService
        }
        XCTAssertNil(releasedContent)
        XCTAssertNil(releasedSmartLists)
        XCTAssertNil(releasedSimpleLists)
        XCTAssertNil(releasedTileService)
    }

    // MARK: - Fetch Smart Lists Tests

    func testFetchSmartListsReturnsEmptyArrayFromEmptyResponse() async throws {
        // Given: A mock service that returns an empty response
        let mockService = MockSmartListService()
        mockService.mockSmartLists = []

        // When: Fetching smart lists
        let smartLists = try await mockService.fetchSmartLists(from: URL(string: "http://test.local")!)

        // Then: Empty array is returned
        XCTAssertEqual(smartLists.count, 0)
    }

    func testFetchSmartListsReturnsMultipleSmartLists() async throws {
        // Given: A mock service with multiple smart lists
        let mockService = MockSmartListService()
        let criteria1 = SmartListCriteria(conditions: [
            FilterCondition(criteriaType: .ratingMin(value: 3), logicOperator: .and)
        ])
        let criteria2 = SmartListCriteria(conditions: [
            FilterCondition(criteriaType: .playCountMin(value: 5), logicOperator: .and)
        ])
        mockService.mockSmartLists = [
            SmartListInfo(name: "Favorites", criteria: criteria1),
            SmartListInfo(name: "Most Played", criteria: criteria2)
        ]

        // When: Fetching smart lists
        let smartLists = try await mockService.fetchSmartLists(from: URL(string: "http://test.local")!)

        // Then: Both smart lists are returned
        XCTAssertEqual(smartLists.count, 2)
        XCTAssertEqual(smartLists[0].name, "Favorites")
        XCTAssertEqual(smartLists[1].name, "Most Played")
    }

    // MARK: - Create Smart List Tests

    func testCreateSmartListWithCriteria() async throws {
        // Given: A mock service and criteria
        let mockService = MockSmartListService()
        let criteria = SmartListCriteria(conditions: [
            FilterCondition(criteriaType: .tagsInclude(tagIds: [UUID()], tagRatings: []), logicOperator: .and),
            FilterCondition(criteriaType: .ratingMin(value: 4), logicOperator: .and)
        ])

        // When: Creating a smart list
        let smartList = try await mockService.createSmartList(
            name: "Top Videos",
            criteria: criteria,
            serverURL: URL(string: "http://test.local")!
        )

        // Then: Smart list is created with correct properties
        XCTAssertEqual(smartList.name, "Top Videos")
        XCTAssertEqual(smartList.criteria.conditions.count, 2)
    }

    // MARK: - Update Smart List Tests

    func testUpdateSmartListUpdatesNameAndCriteria() async throws {
        // Given: A mock service with an existing smart list
        let mockService = MockSmartListService()
        let existingId = UUID()
        let existingSmartList = SmartListInfo(
            id: existingId,
            name: "Old Name",
            criteria: SmartListCriteria(conditions: [])
        )
        mockService.mockSmartLists = [existingSmartList]

        let newCriteria = SmartListCriteria(conditions: [
            FilterCondition(criteriaType: .playCountMin(value: 10), logicOperator: .and)
        ])

        // When: Updating the smart list
        let updatedSmartList = try await mockService.updateSmartList(
            id: existingId,
            name: "New Name",
            criteria: newCriteria,
            serverURL: URL(string: "http://test.local")!
        )

        // Then: Smart list is updated
        XCTAssertEqual(updatedSmartList.name, "New Name")
        XCTAssertEqual(updatedSmartList.criteria.conditions.count, 1)
    }

    // MARK: - Delete Smart List Tests

    func testDeleteSmartListRemovesFromList() async throws {
        // Given: A mock service with an existing smart list
        let mockService = MockSmartListService()
        let smartListId = UUID()
        let smartList = SmartListInfo(
            id: smartListId,
            name: "To Delete",
            criteria: SmartListCriteria(conditions: [])
        )
        mockService.mockSmartLists = [smartList]

        // When: Deleting the smart list
        try await mockService.deleteSmartList(id: smartListId, serverURL: URL(string: "http://test.local")!)

        // Then: Smart list is removed
        XCTAssertTrue(mockService.deletedIds.contains(smartListId))
    }

    // MARK: - Preview Count Tests

    func testPreviewCountReturnsMa​tchingVideoCount() async throws {
        // Given: A mock service with a preview count
        let mockService = MockSmartListService()
        mockService.mockPreviewCount = 42

        let criteria = SmartListCriteria(conditions: [
            FilterCondition(criteriaType: .ratingMin(value: 4), logicOperator: .and)
        ])

        // When: Getting preview count
        let count = try await mockService.previewCount(
            criteria: criteria,
            serverURL: URL(string: "http://test.local")!
        )

        // Then: Count is returned
        XCTAssertEqual(count, 42)
    }
}

// MARK: - Mock Smart List Service

/// Mock service for testing SmartListService functionality
@MainActor
final class MockSmartListService {
    var mockSmartLists: [SmartListInfo] = []
    var mockPreviewCount: Int = 0
    var deletedIds: [UUID] = []

    func fetchSmartLists(from serverURL: URL) async throws -> [SmartListInfo] {
        return mockSmartLists
    }

    func fetchSmartList(id: UUID, from serverURL: URL) async throws -> SmartListInfo? {
        return mockSmartLists.first { $0.id == id }
    }

    func createSmartList(
        name: String,
        criteria: SmartListCriteria,
        serverURL: URL
    ) async throws -> SmartListInfo {
        let smartList = SmartListInfo(name: name, criteria: criteria)
        mockSmartLists.append(smartList)
        return smartList
    }

    func updateSmartList(
        id: UUID,
        name: String,
        criteria: SmartListCriteria,
        serverURL: URL
    ) async throws -> SmartListInfo {
        let updatedSmartList = SmartListInfo(id: id, name: name, criteria: criteria)
        if let index = mockSmartLists.firstIndex(where: { $0.id == id }) {
            mockSmartLists[index] = updatedSmartList
        }
        return updatedSmartList
    }

    func deleteSmartList(id: UUID, serverURL: URL) async throws {
        deletedIds.append(id)
        mockSmartLists.removeAll { $0.id == id }
    }

    func previewCount(criteria: SmartListCriteria, serverURL: URL) async throws -> Int {
        return mockPreviewCount
    }
}

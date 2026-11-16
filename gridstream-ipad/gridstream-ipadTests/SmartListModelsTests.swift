import GridStreamAPI
import XCTest
@testable import gridstream_ipad

@MainActor
final class SmartListModelsTests: XCTestCase {

    // MARK: - SmartListInfo Tests

    func testSmartListInfoCreation() async {
        let criteria = SmartListCriteria(conditions: [])
        let smartList = SmartListInfo(
            id: UUID(),
            name: "Test List",
            criteria: criteria
        )

        XCTAssertEqual(smartList.name, "Test List")
        XCTAssertEqual(smartList.criteria.conditions.count, 0)
    }

    func testSmartListInfoCodable() async throws {
        let tagId = UUID()
        let conditions = [
            FilterCondition(
                criteriaType: .tagsInclude(tagIds: [tagId], tagRatings: []),
                logicOperator: .and
            )
        ]
        let criteria = SmartListCriteria(conditions: conditions)
        let smartList = SmartListInfo(
            id: UUID(),
            name: "Favorites",
            criteria: criteria
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(smartList)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SmartListInfo.self, from: data)

        XCTAssertEqual(decoded.id, smartList.id)
        XCTAssertEqual(decoded.name, smartList.name)
        XCTAssertEqual(decoded.criteria.conditions.count, 1)
    }

    // MARK: - SmartListCriteria Tests

    func testSmartListCriteriaSummaryEmpty() async {
        let criteria = SmartListCriteria(conditions: [])
        XCTAssertEqual(String(localized: criteria.summary), "No filters")
    }

    func testSmartListCriteriaSummarySingleCondition() async {
        let condition = FilterCondition(
            criteriaType: .ratingMin(value: 3),
            logicOperator: .and
        )
        let criteria = SmartListCriteria(conditions: [condition])
        XCTAssertEqual(String(localized: criteria.summary), "Min Rating")
    }

    func testSmartListCriteriaSummaryMultipleConditions() async {
        let conditions = [
            FilterCondition(criteriaType: .ratingMin(value: 3), logicOperator: .and),
            FilterCondition(criteriaType: .playCountMin(value: 5), logicOperator: .or)
        ]
        let criteria = SmartListCriteria(conditions: conditions)
        XCTAssertEqual(String(localized: criteria.summary), "2 filters")
    }

    // MARK: - FilterCondition Tests

    func testFilterConditionWithANDLogic() async {
        let condition = FilterCondition(
            criteriaType: .filenameContains(text: "test"),
            logicOperator: .and
        )

        XCTAssertEqual(condition.logicOperator, .and)
        XCTAssertEqual(condition.logicOperator.displayName, "AND")
    }

    func testFilterConditionWithORLogic() async {
        let condition = FilterCondition(
            criteriaType: .playCountMin(value: 10),
            logicOperator: .or
        )

        XCTAssertEqual(condition.logicOperator, .or)
        XCTAssertEqual(condition.logicOperator.displayName, "OR")
    }

    // MARK: - CriteriaType Encoding/Decoding Tests

    func testCriteriaTypeTagsIncludeEncodeDecode() async throws {
        let tagIds = [UUID(), UUID()]
        let criteria = CriteriaType.tagsInclude(tagIds: tagIds, tagRatings: [])

        let encoder = JSONEncoder()
        let data = try encoder.encode(criteria)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CriteriaType.self, from: data)

        if case .tagsInclude(let decodedTagIds, let decodedTagRatings) = decoded {
            XCTAssertEqual(decodedTagIds, tagIds)
            XCTAssertEqual(decodedTagRatings.count, 0)
        } else {
            XCTFail("Expected tagsInclude criteria type")
        }
    }

    func testCriteriaTypeTagsIncludeWithRatingsEncodeDecode() async throws {
        let tagIds = [UUID(), UUID()]
        let tagRatings = [TagRatingFilter(tagId: tagIds[0], minRating: 5, maxRating: 10)]
        let criteria = CriteriaType.tagsInclude(tagIds: tagIds, tagRatings: tagRatings)

        let encoder = JSONEncoder()
        let data = try encoder.encode(criteria)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CriteriaType.self, from: data)

        if case .tagsInclude(let decodedTagIds, let decodedTagRatings) = decoded {
            XCTAssertEqual(decodedTagIds, tagIds)
            XCTAssertEqual(decodedTagRatings.count, 1)
            XCTAssertEqual(decodedTagRatings[0].tagId, tagIds[0])
            XCTAssertEqual(decodedTagRatings[0].minRating, 5)
            XCTAssertEqual(decodedTagRatings[0].maxRating, 10)
        } else {
            XCTFail("Expected tagsInclude criteria type")
        }
    }

    func testCriteriaTypeRatingMinEncodeDecode() async throws {
        let criteria = CriteriaType.ratingMin(value: 4)

        let encoder = JSONEncoder()
        let data = try encoder.encode(criteria)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CriteriaType.self, from: data)

        if case .ratingMin(let value) = decoded {
            XCTAssertEqual(value, 4)
        } else {
            XCTFail("Expected ratingMin criteria type")
        }
    }

    func testCriteriaTypeDateAddedAfterEncodeDecode() async throws {
        let testDate = Date()
        let criteria = CriteriaType.dateAddedAfter(date: testDate)

        let encoder = JSONEncoder()
        let data = try encoder.encode(criteria)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CriteriaType.self, from: data)

        if case .dateAddedAfter(let date) = decoded {
            XCTAssertEqual(date.timeIntervalSince1970, testDate.timeIntervalSince1970, accuracy: 0.001)
        } else {
            XCTFail("Expected dateAddedAfter criteria type")
        }
    }

    func testCriteriaTypeFilenameRegexEncodeDecode() async throws {
        let pattern = "^test.*\\.mp4$"
        let criteria = CriteriaType.filenameRegex(pattern: pattern)

        let encoder = JSONEncoder()
        let data = try encoder.encode(criteria)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CriteriaType.self, from: data)

        if case .filenameRegex(let decodedPattern) = decoded {
            XCTAssertEqual(decodedPattern, pattern)
        } else {
            XCTFail("Expected filenameRegex criteria type")
        }
    }

    func testCriteriaTypeTextAnnotationEncodeDecode() async throws {
        let criteria = CriteriaType.annotationTextSearch(text: "blue marker")

        let encoder = JSONEncoder()
        let data = try encoder.encode(criteria)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CriteriaType.self, from: data)

        if case .annotationTextSearch(let text) = decoded {
            XCTAssertEqual(text, "blue marker")
        } else {
            XCTFail("Expected annotationTextSearch criteria type")
        }
    }

    func testCriteriaTypeHasTextAnnotationsEncodeDecode() async throws {
        let criteria = CriteriaType.hasTextAnnotations(value: false)

        let encoder = JSONEncoder()
        let data = try encoder.encode(criteria)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CriteriaType.self, from: data)

        if case .hasTextAnnotations(let value) = decoded {
            XCTAssertFalse(value)
        } else {
            XCTFail("Expected hasTextAnnotations criteria type")
        }
    }

    func testCriteriaTypeHasTimeRangesEncodeDecode() async throws {
        let criteria = CriteriaType.hasTimeRanges(value: true)

        let encoder = JSONEncoder()
        let data = try encoder.encode(criteria)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CriteriaType.self, from: data)

        if case .hasTimeRanges(let value) = decoded {
            XCTAssertTrue(value)
        } else {
            XCTFail("Expected hasTimeRanges criteria type")
        }
    }

    // MARK: - CriteriaType Display Name Tests

    func testCriteriaTypeDisplayNames() async {
        XCTAssertEqual(String(localized: CriteriaType.tagsInclude(tagIds: [], tagRatings: []).displayName), "Tags Include")
        XCTAssertEqual(String(localized: CriteriaType.tagsExclude(tagIds: []).displayName), "Tags Exclude")
        XCTAssertEqual(String(localized: CriteriaType.ratingMin(value: 0).displayName), "Min Rating")
        XCTAssertEqual(String(localized: CriteriaType.ratingMax(value: 0).displayName), "Max Rating")
        XCTAssertEqual(String(localized: CriteriaType.sourceDirectory(id: "").displayName), "Source Directory")
        XCTAssertEqual(String(localized: CriteriaType.fileSizeMin(megabytes: 0).displayName), "Min File Size")
        XCTAssertEqual(String(localized: CriteriaType.fileSizeMax(megabytes: 0).displayName), "Max File Size")
        XCTAssertEqual(String(localized: CriteriaType.filenameContains(text: "").displayName), "Filename Contains")
        XCTAssertEqual(String(localized: CriteriaType.playCountMin(value: 0).displayName), "Min Play Count")
        XCTAssertEqual(String(localized: CriteriaType.playCountMax(value: 0).displayName), "Max Play Count")
        XCTAssertEqual(String(localized: CriteriaType.hasTextAnnotations(value: true).displayName), "Has Text Annotation")
        XCTAssertEqual(String(localized: CriteriaType.annotationTextSearch(text: "").displayName), "Annotation Text Search")
        XCTAssertEqual(String(localized: CriteriaType.hasTimeRanges(value: true).displayName), "Has Segments")
    }

    // MARK: - CriteriaType Category Tests

    func testCriteriaTypeCategories() async {
        XCTAssertEqual(CriteriaType.tagsInclude(tagIds: [], tagRatings: []).category, .tags)
        XCTAssertEqual(CriteriaType.tagsExclude(tagIds: []).category, .tags)
        XCTAssertEqual(CriteriaType.ratingMin(value: 0).category, .rating)
        XCTAssertEqual(CriteriaType.sourceDirectory(id: "").category, .source)
        XCTAssertEqual(CriteriaType.fileSizeMin(megabytes: 0).category, .fileSize)
        XCTAssertEqual(CriteriaType.filenameContains(text: "").category, .filename)
        XCTAssertEqual(CriteriaType.dateAddedAfter(date: Date()).category, .date)
        XCTAssertEqual(CriteriaType.playCountMin(value: 0).category, .playCount)
        XCTAssertEqual(CriteriaType.hasTextAnnotations(value: true).category, .annotations)
        XCTAssertEqual(CriteriaType.annotationTextSearch(text: "").category, .annotations)
        XCTAssertEqual(CriteriaType.hasTimeRanges(value: true).category, .segments)
    }
}

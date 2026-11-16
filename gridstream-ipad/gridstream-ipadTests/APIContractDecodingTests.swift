//
//  APIContractDecodingTests.swift
//  gridstream-ipadTests
//
//  Wire-format tolerance required by contracts/decisions.md
//  (§1 dates, §2 criteria, §3 simple lists).
//

import GridStreamAPI
import XCTest
@testable import gridstream_ipad

@MainActor
final class APIContractDecodingTests: XCTestCase {

    private struct DateBox: Codable {
        let d: Date
    }

    private func decodeDate(_ json: String) throws -> Date {
        try JSONDecoder.gridStream().decode(DateBox.self, from: Data(json.utf8)).d
    }

    // MARK: - Dates (§1)

    func testDecodesISO8601WithFractionalSeconds() async throws {
        let date = try decodeDate(#"{"d":"2026-01-02T03:04:05.678Z"}"#)
        XCTAssertEqual(date.timeIntervalSince1970, 1_767_323_045.678, accuracy: 0.001)
    }

    func testDecodesISO8601WithoutFractionalSeconds() async throws {
        let date = try decodeDate(#"{"d":"2026-01-02T03:04:05Z"}"#)
        XCTAssertEqual(date.timeIntervalSince1970, 1_767_323_045, accuracy: 0.001)
    }

    func testDecodesDateOnlyAsStartOfLocalDay() async throws {
        let date = try decodeDate(#"{"d":"2026-01-02"}"#)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let expected = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2))
        XCTAssertEqual(date, expected)
    }

    func testDecodesLegacyReferenceDateNumber() async throws {
        let date = try decodeDate(#"{"d":12.5}"#)
        XCTAssertEqual(date, Date(timeIntervalSinceReferenceDate: 12.5))
    }

    func testRejectsGarbageDateString() async {
        XCTAssertThrowsError(try decodeDate(#"{"d":"yesterday"}"#))
    }

    func testEncodesDatesAsISO8601() async throws {
        let data = try JSONEncoder.gridStream().encode(DateBox(d: Date(timeIntervalSince1970: 1_767_323_045)))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"d":"2026-01-02T03:04:05Z"}"#)
    }

    // MARK: - Smart list criteria (§2)

    func testConditionWithNonUUIDIdDecodesWithFreshId() async throws {
        let json = #"""
        {"conditions":[{"id":"0.8123","criteriaType":{"type":"ratingMin","value":3}}]}
        """#
        let criteria = try JSONDecoder.gridStream().decode(SmartListCriteria.self, from: Data(json.utf8))

        XCTAssertEqual(criteria.conditions.count, 1)
        XCTAssertEqual(criteria.conditions[0].criteriaType, .ratingMin(value: 3))
        XCTAssertEqual(criteria.conditions[0].logicOperator, .and)
    }

    func testIntegerRatingsAcceptFractionalNumbers() async throws {
        let tagId = UUID()
        let json = """
        {"conditions":[
          {"id":"\(UUID().uuidString)","criteriaType":{"type":"ratingMax","value":4.0},"logicOperator":"AND"},
          {"id":"\(UUID().uuidString)","criteriaType":{"type":"tagsInclude","tagIds":["\(tagId.uuidString)"],
            "tagRatings":[{"tagId":"\(tagId.uuidString)","minRating":2.0}]},"logicOperator":"AND"}
        ]}
        """
        let criteria = try JSONDecoder.gridStream().decode(SmartListCriteria.self, from: Data(json.utf8))

        XCTAssertEqual(criteria.conditions.map(\.criteriaType), [
            .ratingMax(value: 4),
            .tagsInclude(tagIds: [tagId], tagRatings: [TagRatingFilter(tagId: tagId, minRating: 2)])
        ])
    }

    func testDateCriteriaAcceptDateOnlyStrings() async throws {
        let json = #"""
        {"conditions":[{"id":"x","criteriaType":{"type":"dateAddedAfter","date":"2026-01-02"}}]}
        """#
        let criteria = try JSONDecoder.gridStream().decode(SmartListCriteria.self, from: Data(json.utf8))

        guard case .dateAddedAfter = criteria.conditions.first?.criteriaType else {
            return XCTFail("Expected a dateAddedAfter condition")
        }
    }

    // MARK: - Simple lists (§3)

    func testSortOrderAcceptsCanonicalAliasesAndUnknownValues() async {
        XCTAssertEqual(SimpleListSortOrder(lenient: "date_added_desc"), .dateAddedDesc)
        XCTAssertEqual(SimpleListSortOrder(lenient: "dateAddedDesc"), .dateAddedDesc)
        XCTAssertEqual(SimpleListSortOrder(lenient: "PLAY_COUNT"), .playCount)
        XCTAssertEqual(SimpleListSortOrder(lenient: "fileSize"), .fileSize)
        XCTAssertEqual(SimpleListSortOrder(lenient: "random"), .filename)
    }

    func testSimpleListWithMissingFieldsDecodesWithDefaults() async throws {
        let id = UUID()
        let json = #"{"id":"\#(id.uuidString)","name":"Favorites","sortOrder":"playCountDesc"}"#
        let list = try JSONDecoder.gridStream().decode(SimpleListDTO.self, from: Data(json.utf8))

        XCTAssertEqual(list.id, id)
        XCTAssertEqual(list.videoIds, [])
        XCTAssertEqual(list.videoCount, 0)
        XCTAssertEqual(list.sortOrder, .playCountDesc)
    }

    func testLossyListSkipsUndecodableEntries() async throws {
        let good = UUID()
        let json = """
        [
          {"id":"\(good.uuidString)","name":"Good","videoIds":["a","b"],"sortOrder":"filename",
           "createdAt":"2026-01-02T03:04:05.000Z","updatedAt":"2026-01-02T03:04:05Z"},
          {"id":"not-a-uuid","name":"Bad"},
          {"name":"No id"}
        ]
        """
        let lists = try JSONDecoder.gridStream().decode(LossyArray<SimpleListDTO>.self, from: Data(json.utf8))

        XCTAssertEqual(lists.elements.map(\.id), [good])
        XCTAssertEqual(lists.elements.first?.videoCount, 2)
    }
}

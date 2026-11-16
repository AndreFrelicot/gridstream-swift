import Foundation
import XCTest
import GridStreamAPI

/// The shared contract rules (contracts/decisions.md).
final class ContractCodingTests: XCTestCase {

    // MARK: - §1 Dates

    func testTolerantDateDecodingAcceptsAllFourForms() throws {
        struct Wrapper: Decodable { let date: Date }
        func decode(_ json: String) throws -> Date {
            try JSONDecoder.gridStream().decode(Wrapper.self, from: Data(json.utf8)).date
        }

        let expected = Date(timeIntervalSince1970: 1_793_700_000) // 2026-11-03T10:00:00Z
        XCTAssertEqual(try decode(#"{"date":"2026-11-03T10:00:00.000Z"}"#), expected)
        XCTAssertEqual(try decode(#"{"date":"2026-11-03T10:00:00.250Z"}"#).timeIntervalSince1970,
                       expected.timeIntervalSince1970 + 0.25, accuracy: 0.0001)
        XCTAssertEqual(try decode(#"{"date":"2026-11-03T10:00:00Z"}"#), expected)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let startOfDay = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3))!
        XCTAssertEqual(try decode(#"{"date":"2026-11-03"}"#), startOfDay)

        XCTAssertEqual(try decode(#"{"date":\#(expected.timeIntervalSinceReferenceDate)}"#), expected)

        XCTAssertThrowsError(try decode(#"{"date":"03/11/2026"}"#))
        XCTAssertThrowsError(try decode(#"{"date":"2026-02-30"}"#))
    }

    func testEncoderEmitsISO8601WithoutFraction() throws {
        struct Wrapper: Encodable { let date: Date }
        let data = try JSONEncoder.gridStream().encode(Wrapper(date: Date(timeIntervalSince1970: 1_793_700_000.75)))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"date":"2026-11-03T10:00:00Z"}"#)
    }

    // MARK: - §2 Criteria

    func testLegacyCriteriaDecodeAndReencodeCanonically() throws {
        let legacy = #"""
        {"conditions":[
          {"id":"0.123456","criteriaType":{"type":"dateAddedAfter","date":"2026-11-03T10:00:00.250Z"},"logicOperator":"AND"},
          {"id":"not-a-uuid","criteriaType":{"type":"dateModifiedBefore","date":"2026-11-03"}},
          {"id":"C0000000-0000-4000-8000-000000000003","criteriaType":{"type":"dateAddedBefore","date":815047200},"logicOperator":"OR"},
          {"id":"C0000000-0000-4000-8000-000000000004","criteriaType":{"type":"ratingMin","value":7.5},"logicOperator":"AND"},
          {"id":"C0000000-0000-4000-8000-000000000005","criteriaType":{"type":"tagsInclude","tagIds":["3C9D1E2F-5A6B-4C7D-8E9F-0A1B2C3D4E5F"],"tagRatings":[{"tagId":"3C9D1E2F-5A6B-4C7D-8E9F-0A1B2C3D4E5F","minRating":5.6}]},"logicOperator":"AND"},
          {"id":"C0000000-0000-4000-8000-000000000006","criteriaType":{"type":"playCountMin","value":2.0},"logicOperator":"AND"},
          {"id":"C0000000-0000-4000-8000-000000000007","criteriaType":{"type":"tagsInclude","tagIds":["3C9D1E2F-5A6B-4C7D-8E9F-0A1B2C3D4E5F"]},"logicOperator":"AND"}
        ]}
        """#
        let criteria = try SmartListCriteria.parseValidated(json: legacy)
        XCTAssertEqual(criteria.conditions.count, 7)
        XCTAssertEqual(criteria.conditions[1].logicOperator, .and)
        XCTAssertEqual(criteria.conditions[3].criteriaType, .ratingMin(value: 8))
        XCTAssertEqual(criteria.conditions[5].criteriaType, .playCountMin(value: 2))
        let tagId = UUID(uuidString: "3C9D1E2F-5A6B-4C7D-8E9F-0A1B2C3D4E5F")!
        XCTAssertEqual(criteria.conditions[4].criteriaType,
                       .tagsInclude(tagIds: [tagId], tagRatings: [TagRatingFilter(tagId: tagId, minRating: 6)]))
        XCTAssertEqual(criteria.conditions[6].criteriaType, .tagsInclude(tagIds: [tagId], tagRatings: []))

        let canonical = try criteria.canonicalJSON()
        XCTAssertFalse(canonical.contains("0.123456"))
        XCTAssertFalse(canonical.contains("not-a-uuid"))
        XCTAssertFalse(canonical.contains(".250Z"))
        XCTAssertTrue(canonical.contains(#""date":"2026-11-03T10:00:00Z""#))
        XCTAssertTrue(canonical.contains(#""date":"2026-10-30T10:00:00Z""#)) // 815047200 s after 2001-01-01

        // Canonical form is stable (fractional seconds are dropped once).
        let reparsed = try SmartListCriteria.parseValidated(json: canonical)
        XCTAssertEqual(try reparsed.canonicalJSON(), canonical)
    }

    func testCriteriaValidationRejectsOutOfRangeValues() throws {
        func parse(_ type: String) throws -> SmartListCriteria {
            try SmartListCriteria.parseValidated(json: #"{"conditions":[{"id":"C0000000-0000-4000-8000-000000000001","criteriaType":\#(type),"logicOperator":"AND"}]}"#)
        }
        let long = String(repeating: "a", count: 257)

        XCTAssertThrowsError(try parse(#"{"type":"ratingMin","value":11}"#))
        XCTAssertThrowsError(try parse(#"{"type":"ratingMax","value":-1}"#))
        XCTAssertThrowsError(try parse(#"{"type":"fileSizeMin","megabytes":-5}"#))
        XCTAssertThrowsError(try parse(#"{"type":"fileSizeMax","megabytes":20000000}"#))
        XCTAssertThrowsError(try parse(#"{"type":"playCountMin","value":-1}"#))
        XCTAssertThrowsError(try parse(#"{"type":"filenameRegex","pattern":"\#(long)"}"#))
        XCTAssertThrowsError(try parse(#"{"type":"filenameRegex","pattern":"(unclosed"}"#))
        XCTAssertThrowsError(try parse(#"{"type":"filenameContains","text":"\#(long)"}"#))
        XCTAssertThrowsError(try parse(#"{"type":"ratingMin","value":1e300}"#))
        XCTAssertThrowsError(try parse(#"{"type":"nope"}"#)) { error in
            XCTAssertTrue(error is CriteriaValidationError)
        }
        XCTAssertNoThrow(try parse(#"{"type":"ratingMin","value":10}"#))
    }

    func testRemovingTagDropsEmptiedConditions() throws {
        let kept = UUID()
        let removed = UUID()
        let criteria = SmartListCriteria(conditions: [
            FilterCondition(criteriaType: .tagsInclude(tagIds: [kept, removed], tagRatings: [TagRatingFilter(tagId: removed, minRating: 3)])),
            FilterCondition(criteriaType: .tagsExclude(tagIds: [removed])),
            FilterCondition(criteriaType: .unrated),
        ])
        let result = try XCTUnwrap(criteria.removingTag(removed))
        XCTAssertEqual(result.conditions.map(\.criteriaType), [
            .tagsInclude(tagIds: [kept], tagRatings: []),
            .unrated,
        ])
        XCTAssertNil(criteria.removingTag(UUID()))
    }

    // MARK: - §3 Sort order

    func testSortOrderServerCanonicalization() {
        XCTAssertEqual(SimpleListSortOrder.canonical("filename_desc"), "filename_desc")
        XCTAssertEqual(SimpleListSortOrder.canonical("filenameDesc"), "filename_desc")
        XCTAssertEqual(SimpleListSortOrder.canonical(" playCountDesc "), "play_count_desc")
        XCTAssertNil(SimpleListSortOrder.canonical("random"))
        XCTAssertEqual(SimpleListSortOrder.defaultValue, "filename")
        XCTAssertEqual(SimpleListSortOrder.canonicalValues, [
            "filename", "filename_desc", "file_size", "file_size_desc", "play_count",
            "play_count_desc", "play_time", "play_time_desc", "date_added", "date_added_desc",
        ])
    }

    func testSortOrderClientDecodingIsTolerant() throws {
        func decode(_ value: String) throws -> SimpleListSortOrder {
            try JSONDecoder.gridStream().decode([SimpleListSortOrder].self, from: Data(#"["\#(value)"]"#.utf8))[0]
        }
        XCTAssertEqual(try decode("file_size_desc"), .fileSizeDesc)
        XCTAssertEqual(try decode("dateAddedDesc"), .dateAddedDesc)
        XCTAssertEqual(try decode("bogus"), .filename)

        let list = try JSONDecoder.gridStream().decode(
            SimpleListDTO.self,
            from: Data(#"{"id":"1D2C3B4A-5968-4776-8594-A3B2C1D0E9F8","name":"Bare"}"#.utf8)
        )
        XCTAssertEqual(list.videoIds, [])
        XCTAssertEqual(list.videoCount, 0)
        XCTAssertEqual(list.sortOrder, .filename)
    }

    // MARK: - §4 Tag requests

    func testBulkTagApplyRequestEncodesLowercaseTagIds() throws {
        let tagId = UUID(uuidString: "3C9D1E2F-5A6B-4C7D-8E9F-0A1B2C3D4E5F")!
        let request = BulkTagApplyRequest(fileIds: ["a1"], addTagIds: [tagId], removeTagIds: [])
        let encoded = String(decoding: try JSONEncoder.gridStreamCanonical().encode(request), as: UTF8.self)
        XCTAssertEqual(encoded, #"{"addTagIds":["3c9d1e2f-5a6b-4c7d-8e9f-0a1b2c3d4e5f"],"fileIds":["a1"],"removeTagIds":[]}"#)

        let decoded = try JSONDecoder.gridStream().decode(BulkTagApplyRequest.self, from: Data(encoded.utf8))
        XCTAssertEqual(decoded.addTagIds, [tagId])
    }

    // MARK: - Annotations

    func testUpsertAnnotationRequestAlwaysEncodesText() throws {
        let request = UpsertAnnotationRequest(frameTime: 1, frameRate: 30, strokesJSON: "[]", text: nil)
        let encoded = String(decoding: try JSONEncoder.gridStreamCanonical().encode(request), as: UTF8.self)
        XCTAssertEqual(encoded, #"{"frameRate":30,"frameTime":1,"strokesJSON":"[]","text":null}"#)
    }

    // MARK: - Videos

    func testVideoItemDecodingDefaultsMissingCounters() throws {
        let json = #"""
        {"id":"6F1A2B3C-4D5E-4F60-8172-93A4B5C6D7E8","fileId":"f","filename":"a.mp4","relativePath":"a.mp4",
         "sourceDirectoryId":"0A1B2C3D-4E5F-4061-8273-94A5B6C7D8E9","duration":1,"width":2,"height":3,
         "codec":"h264","fileSize":4,"lastModified":"2026-11-03T10:00:00Z"}
        """#
        let video = try JSONDecoder.gridStream().decode(VideoItem.self, from: Data(json.utf8))
        XCTAssertEqual(video.rating, 0)
        XCTAssertEqual(video.playCount, 0)
        XCTAssertEqual(video.totalViewTime, 0)
        XCTAssertEqual(video.annotationCount, 0)
        XCTAssertNil(video.tags)

        // nil optionals are omitted on encode.
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.gridStream().encode(video)) as? [String: Any])
        XCTAssertNil(encoded["lastPlayedAt"])
        XCTAssertNil(encoded["tags"])
        XCTAssertNil(encoded["thumbnailUrl"])
        XCTAssertNil(encoded["sourceDirectoryName"])
    }

    // MARK: - §9 Query strings

    func testQueryItemsEncodePlus() throws {
        var components = URLComponents(string: "http://host/api/v1/videos")!
        components.setQueryItemsEncodingPlus([
            URLQueryItem(name: "search", value: "C++ take"),
            URLQueryItem(name: "regex", value: #"\d+"#),
        ])
        XCTAssertEqual(components.percentEncodedQuery, "search=C%2B%2B%20take&regex=%5Cd%2B")

        components.setQueryItemsEncodingPlus([])
        XCTAssertNil(components.queryItems)
    }

    // MARK: - Palette

    func testTagColorPalette() {
        XCTAssertEqual(TagColorPalette.allColors.count, 10)
        XCTAssertTrue(TagColorPalette.isValidColor("#3B82F6"))
        XCTAssertFalse(TagColorPalette.isValidColor("red"))
        XCTAssertEqual(TagColorPalette.color(at: 11), TagColorPalette.orange)
    }
}

import Foundation
import XCTest
import GridStreamAPI

/// Every file in `contracts/fixtures` decodes into its wire type, and
/// re-encoding it gives the same JSON back (same keys, values, date format
/// and optionality).
final class FixtureTests: XCTestCase {
    /// Fixture file → its wire type.
    private static var fixtures: [String: any Codable.Type] {[
        "video.json": VideoItem.self,
        "videos-page.json": PaginatedVideosResponse.self,
        "tag.json": TagDTO.self,
        "tags.json": TagsResponse.self,
        "video-tags.json": VideoTagsResponse.self,
        "tag-create-request.json": CreateTagRequest.self,
        "tag-update-request.json": UpdateTagRequest.self,
        "tag-delete-response.json": TagDeleteResponse.self,
        "video-tags-replace-request.json": ApplyTagsRequest.self,
        "tags-apply-request.json": BulkTagApplyRequest.self,
        "tags-apply-response.json": BulkTagApplyResponse.self,
        "rating-request.json": RatingRequest.self,
        "rating.json": RatingDTO.self,
        "playback-stats-request.json": PlaybackStatsRequest.self,
        "playback-stats.json": PlaybackStatsDTO.self,
        "smart-list-criteria.json": SmartListCriteria.self,
        "smart-list.json": SmartListDTO.self,
        "smart-lists.json": SmartListsResponse.self,
        "smart-list-create-request.json": CreateSmartListRequest.self,
        "smart-list-update-request.json": UpdateSmartListRequest.self,
        "smart-list-memberships.json": SmartListMembershipsResponse.self,
        "smart-list-delete-response.json": SmartListDeleteResponse.self,
        "simple-list.json": SimpleListDTO.self,
        "simple-lists.json": SimpleListsResponse.self,
        "simple-list-create-request.json": CreateSimpleListRequest.self,
        "simple-list-update-request.json": UpdateSimpleListRequest.self,
        "simple-list-videos-request.json": AddVideosRequest.self,
        "time-range.json": TimeRangeDTO.self,
        "time-ranges.json": TimeRangeListResponse.self,
        "time-range-create-request.json": CreateTimeRangeRequest.self,
        "annotation.json": AnnotationDTO.self,
        "annotations.json": AnnotationListResponse.self,
        "annotation-times.json": AnnotationTimesResponse.self,
        "annotation-upsert-request.json": UpsertAnnotationRequest.self,
        "capture.json": FrameCaptureDTO.self,
        "captures.json": FrameCaptureListResponse.self,
        "capture-create-request.json": CreateFrameCaptureRequest.self,
        "catalog-status.json": CatalogStatusDTO.self,
        "source-directories.json": SourceDirectoriesResponse.self,
        "auth-session.json": AuthSessionResponse.self,
        "auth-login-request.json": LoginRequest.self,
    ]}

    func testEveryFixtureRoundTrips() throws {
        for (file, type) in Self.fixtures.sorted(by: { $0.key < $1.key }) {
            try assertRoundTrip(type, file)
        }
    }

    func testEveryFixtureFileIsCovered() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: Fixtures.directory.path)
            .filter { $0.hasSuffix(".json") }
        XCTAssertFalse(files.isEmpty, "no fixtures found in \(Fixtures.directory.path)")
        for file in files {
            XCTAssertNotNil(Self.fixtures[file], "\(file) has no round-trip check")
        }
    }

    // MARK: - Criteria

    func testCriteriaFixtureCoversEveryCriteriaTypeAndIsCanonical() throws {
        let data = try Fixtures.data("smart-list-criteria.json")
        let criteria = try JSONDecoder.gridStream().decode(SmartListCriteria.self, from: data)

        let types = try criteria.conditions.map { condition -> String in
            let encoded = try JSONEncoder.gridStream().encode(condition.criteriaType)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            return try XCTUnwrap(object["type"] as? String)
        }
        XCTAssertEqual(Set(types).count, 27)
        XCTAssertEqual(types.count, 27)

        try criteria.validate()
        XCTAssertEqual(try criteria.canonicalJSON(), try Fixtures.minifiedSortedJSON("smart-list-criteria.json"))
    }

    func testStoredCriteriaInSmartListFixtureIsCanonical() throws {
        let smartList = try JSONDecoder.gridStream().decode(SmartListDTO.self, from: Fixtures.data("smart-list.json"))
        let criteria = try SmartListCriteria.parseValidated(json: smartList.criteria)
        XCTAssertEqual(try criteria.canonicalJSON(), smartList.criteria)
    }

    // MARK: - Helpers

    private func assertRoundTrip<T: Codable>(_ type: T.Type, _ file: String) throws {
        let data = try Fixtures.data(file)
        let value: T
        do {
            value = try JSONDecoder.gridStream().decode(T.self, from: data)
        } catch {
            XCTFail("\(file) does not decode as \(T.self): \(error)")
            return
        }
        let reencoded = try JSONEncoder.gridStream().encode(value)
        let original = try JSONSerialization.jsonObject(with: data) as AnyObject
        let roundTripped = try JSONSerialization.jsonObject(with: reencoded) as AnyObject
        XCTAssertTrue(
            original.isEqual(roundTripped),
            "\(file) does not round-trip through \(T.self):\n\(String(decoding: reencoded, as: UTF8.self))"
        )
    }
}

enum Fixtures {
    /// `<repo>/contracts/fixtures`, found from this source file.
    static let directory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // GridStreamAPITests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // GridStreamKit
        .deletingLastPathComponent() // repo root
        .appendingPathComponent("contracts/fixtures", isDirectory: true)

    static func data(_ file: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(file))
    }

    /// The fixture as compact JSON with sorted keys (the canonical layout).
    static func minifiedSortedJSON(_ file: String) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data(file))
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}

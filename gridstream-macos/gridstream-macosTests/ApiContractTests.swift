import GridStreamAPI
import XCTest
import Vapor
import GRDB
@testable import gridstream_macos

/// Server side of contracts/decisions.md §1–§4 and §9.
final class ApiContractTests: XCTestCase {

    var testDir: URL!
    var databaseManager: DatabaseManager!
    var app: Application!
    var catalogProvider: TestVideoCatalogProvider!

    override func setUp() async throws {
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GridStreamApiContractTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        databaseManager = DatabaseManager(databasePath: testDir.appendingPathComponent("test.sqlite"))
        try await databaseManager.initialize()

        var env = try Environment.detect()
        env.arguments = ["vapor", "test"]
        app = try await Application.make(env)
        app.middleware.use(ErrorMiddleware.default(environment: app.environment))

        catalogProvider = TestVideoCatalogProvider(databaseManager: databaseManager)
        app.storage[VideoCatalogStorageKey.self] = catalogProvider

        try app.register(collection: VideoRoutes(databaseManager: databaseManager))
        try app.register(collection: SmartListRoutes(databaseManager: databaseManager))
        try app.register(collection: SimpleListRoutes(databaseManager: databaseManager))
        try app.register(collection: TagRoutes(databaseManager: databaseManager))
        try app.register(collection: VideoTagRoutes(databaseManager: databaseManager))
    }

    override func tearDown() async throws {
        try await databaseManager.close()
        try await app.asyncShutdown()
        try? FileManager.default.removeItem(at: testDir)
        databaseManager = nil
        app = nil
        catalogProvider = nil
        testDir = nil
    }

    // MARK: - Helpers

    @discardableResult
    private func insertVideo(_ fileId: String, filename: String, rating: Int = 0) async throws -> VideoFileRecord {
        let video = VideoFileRecord(
            fileId: fileId,
            path: "/test/\(filename)",
            sourceDirectoryId: UUID(),
            filename: filename,
            fileSize: 1000,
            duration: 60,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: Date().timeIntervalSince1970,
            rating: rating
        )
        try await databaseManager.write { db in
            try video.insert(db)
        }
        return video
    }

    private func insertTag(_ name: String) async throws -> TagRecord {
        let tag = TagRecord(name: name, color: "red")
        try await databaseManager.write { db in
            try tag.insert(db)
        }
        return tag
    }

    private func jsonBody(_ object: Any) throws -> ByteBuffer {
        ByteBuffer(bytes: Array(try JSONSerialization.data(withJSONObject: object)))
    }

    private var jsonHeaders: HTTPHeaders { ["Content-Type": "application/json"] }

    private func encodedQuery(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    }

    private func criteriaJSON(_ conditions: [[String: Any]]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["conditions": conditions])
        return String(decoding: data, as: UTF8.self)
    }

    private func condition(_ type: [String: Any], id: String = UUID().uuidString) -> [String: Any] {
        ["id": id, "criteriaType": type, "logicOperator": "AND"]
    }

    // MARK: - §1 Tolerant dates

    func testTolerantDateDecodingAcceptsAllFourForms() throws {
        struct Wrapper: Decodable { let date: Date }
        let decoder = TolerantDateDecoding.makeDecoder()
        func decode(_ json: String) throws -> Date {
            try decoder.decode(Wrapper.self, from: Data(json.utf8)).date
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

        let referenceSeconds = expected.timeIntervalSinceReferenceDate
        XCTAssertEqual(try decode(#"{"date":\#(referenceSeconds)}"#), expected)

        XCTAssertThrowsError(try decode(#"{"date":"03/11/2026"}"#))
        XCTAssertThrowsError(try decode(#"{"date":"2026-02-30"}"#))
    }

    // MARK: - §2 Criteria validation and canonical form

    func testCriteriaValidationRejectsOutOfRangeValues() throws {
        func parse(_ type: [String: Any]) throws -> SmartListCriteria {
            try SmartListCriteria.parseValidated(json: try criteriaJSON([condition(type)]))
        }

        XCTAssertThrowsError(try parse(["type": "ratingMin", "value": 11]))
        XCTAssertThrowsError(try parse(["type": "ratingMax", "value": -1]))
        XCTAssertThrowsError(try parse(["type": "fileSizeMin", "megabytes": -5]))
        XCTAssertThrowsError(try parse(["type": "fileSizeMax", "megabytes": 20_000_000]))
        XCTAssertThrowsError(try parse(["type": "playCountMin", "value": -1]))
        XCTAssertThrowsError(try parse(["type": "filenameRegex", "pattern": String(repeating: "a", count: 257)]))
        XCTAssertThrowsError(try parse(["type": "filenameRegex", "pattern": "(unclosed"]))
        XCTAssertThrowsError(try parse(["type": "filenameContains", "text": String(repeating: "a", count: 257)]))
        XCTAssertThrowsError(try SmartListCriteria.parseValidated(json: "not json")) { error in
            XCTAssertTrue(error is CriteriaValidationError)
        }

        XCTAssertNoThrow(try parse(["type": "ratingMin", "value": 10]))
        XCTAssertNoThrow(try parse(["type": "fileSizeMax", "megabytes": 10_000_000]))
    }

    func testCriteriaRoundsFractionalRatingsAndReplacesNonUUIDIds() throws {
        let tagId = UUID()
        let json = try criteriaJSON([
            condition(["type": "ratingMin", "value": 6.6], id: "0.123456789"),
            condition(["type": "tagsInclude", "tagIds": [tagId.uuidString],
                       "tagRatings": [["tagId": tagId.uuidString, "minRating": 2.4]]]),
        ])
        let criteria = try SmartListCriteria.parseValidated(json: json)

        guard case .ratingMin(let value) = criteria.conditions[0].criteriaType else {
            return XCTFail("Expected ratingMin")
        }
        XCTAssertEqual(value, 7)
        guard case .tagsInclude(_, let tagRatings) = criteria.conditions[1].criteriaType else {
            return XCTFail("Expected tagsInclude")
        }
        XCTAssertEqual(tagRatings.first?.minRating, 2)

        let canonical = try criteria.canonicalJSON()
        XCTAssertFalse(canonical.contains("0.123456789"))
        XCTAssertEqual(try SmartListCriteria.decode(json: canonical).conditions.count, 2)
    }

    func testCanonicalCriteriaStoresDatesWithoutFraction() throws {
        let json = try criteriaJSON([condition(["type": "dateAddedAfter", "date": "2026-11-03T08:00:00.123Z"])])
        let canonical = try SmartListCriteria.parseValidated(json: json).canonicalJSON()
        XCTAssertTrue(canonical.contains("2026-11-03T08:00:00Z"), canonical)
    }

    func testDuplicateTagRatingsDoNotCrash() async throws {
        let tag = try await insertTag("dup")
        try await insertVideo("dup_a", filename: "a.mp4")
        try await databaseManager.write { db in
            var link = VideoTagRecord(videoFileId: "dup_a", tagId: tag.id)
            link.rating = 5
            try link.insert(db)
        }

        let criteria = SmartListCriteria(conditions: [
            FilterCondition(
                criteriaType: .tagsInclude(tagIds: [tag.id], tagRatings: [
                    TagRatingFilter(tagId: tag.id, minRating: 9),
                    TagRatingFilter(tagId: tag.id, minRating: 1),
                ]),
                logicOperator: .and
            ),
        ])
        let matches = try await CriteriaEvaluator().evaluateCriteria(criteria, db: databaseManager)
        XCTAssertEqual(matches, ["dup_a"], "Last duplicate wins")

        let tagRatings = "\(tag.id.uuidString):9-10,\(tag.id.uuidString):1-10"
        let response = try await app.sendRequest(.GET, "/api/v1/videos?tags=\(tag.id.uuidString)&tagRatings=\(tagRatings)")
        XCTAssertEqual(response.status, .ok)
    }

    func testSmartListCreateRejectsInvalidCriteriaAndStoresCanonicalForm() async throws {
        let invalid = try jsonBody(["name": "bad", "criteria": try criteriaJSON([condition(["type": "ratingMin", "value": 42])])])
        let rejected = try await app.sendRequest(.POST, "/api/v1/smart-lists", headers: jsonHeaders, body: invalid)
        XCTAssertEqual(rejected.status, .badRequest)

        let criteria = try criteriaJSON([condition(["type": "dateAddedAfter", "date": "2026-11-03"], id: "web-id")])
        let valid = try jsonBody(["name": "good", "criteria": criteria])
        let created = try await app.sendRequest(.POST, "/api/v1/smart-lists", headers: jsonHeaders, body: valid)
        XCTAssertEqual(created.status, .created)

        let stored = try await databaseManager.read { db in SmartListRecord.findByName("good", in: db) }
        let storedCriteria = try XCTUnwrap(stored?.criteria)
        XCTAssertFalse(storedCriteria.contains("web-id"))
        XCTAssertNotNil(try? JSONDecoder.iso8601Strict.decode(SmartListCriteria.self, from: Data(storedCriteria.utf8)))

        let badUpdate = try jsonBody(["criteria": "{\"conditions\": 3}"])
        let updateResponse = try await app.sendRequest(.PUT, "/api/v1/smart-lists/\(stored!.id.uuidString)", headers: jsonHeaders, body: badUpdate)
        XCTAssertEqual(updateResponse.status, .badRequest)
    }

    func testCriteriaNormalizationMigrationRewritesDecodableRowsOnly() async throws {
        let legacy = try criteriaJSON([condition(["type": "dateAddedAfter", "date": "2026-11-03T08:00:00.500Z"], id: "0.5")])
        let broken = "{\"conditions\":[{\"oops\":true}]}"
        try await databaseManager.write { db in
            try SmartListRecord(name: "legacy", criteria: legacy).insert(db)
            try SmartListRecord(name: "broken", criteria: broken).insert(db)
            try V28_NormalizeSmartListCriteria.migrate(db)
        }

        let lists = try await databaseManager.read { db in SmartListRecord.findAll(in: db) }
        let migrated = try XCTUnwrap(lists.first { $0.name == "legacy" })
        XCTAssertTrue(migrated.criteria.contains("2026-11-03T08:00:00Z"), migrated.criteria)
        XCTAssertFalse(migrated.criteria.contains("\"0.5\""))
        XCTAssertEqual(lists.first { $0.name == "broken" }?.criteria, broken)
    }

    func testDeletingTagRemovesItFromSmartListCriteria() async throws {
        let keep = try await insertTag("keep")
        let gone = try await insertTag("gone")
        let criteria = try criteriaJSON([
            condition(["type": "tagsInclude", "tagIds": [keep.id.uuidString, gone.id.uuidString.lowercased()],
                       "tagRatings": [["tagId": gone.id.uuidString, "minRating": 3]]]),
            condition(["type": "tagsExclude", "tagIds": [gone.id.uuidString]]),
            condition(["type": "ratingMin", "value": 2]),
        ])
        try await databaseManager.write { db in
            try SmartListRecord(name: "mixed", criteria: criteria).insert(db)
        }

        let response = try await app.sendRequest(.DELETE, "/api/v1/tags/\(gone.id.uuidString)")
        XCTAssertEqual(response.status, .ok)

        let stored = try await databaseManager.read { db in SmartListRecord.findByName("mixed", in: db) }
        let updated = try SmartListCriteria.decode(json: try XCTUnwrap(stored?.criteria))
        XCTAssertEqual(updated.conditions.count, 2, "Empty tagsExclude condition is dropped")
        guard case .tagsInclude(let tagIds, let tagRatings) = updated.conditions[0].criteriaType else {
            return XCTFail("Expected tagsInclude")
        }
        XCTAssertEqual(tagIds, [keep.id])
        XCTAssertTrue(tagRatings.isEmpty)
    }

    // MARK: - §2 Flat params ∩ criteria

    func testCriteriaAndFlatParamsAreIntersected() async throws {
        try await insertVideo("i_1", filename: "holiday_beach.mp4", rating: 8)
        try await insertVideo("i_2", filename: "holiday_city.mp4", rating: 2)
        try await insertVideo("i_3", filename: "work_meeting.mp4", rating: 9)

        let criteria = try criteriaJSON([condition(["type": "ratingMin", "value": 5])])
        let response = try await app.sendRequest(.GET, "/api/v1/videos?criteria=\(encodedQuery(criteria))&search=holiday")
        XCTAssertEqual(response.status, .ok)
        let result = try response.content.decode(PaginatedVideosResponse.self)
        XCTAssertEqual(result.videos.map(\.fileId), ["i_1"])

        let invalid = try criteriaJSON([condition(["type": "ratingMin", "value": 99])])
        let rejected = try await app.sendRequest(.GET, "/api/v1/videos?criteria=\(encodedQuery(invalid))")
        XCTAssertEqual(rejected.status, .badRequest)
    }

    func testSearchMatchesLikeWildcardsLiterally() async throws {
        try await insertVideo("w_1", filename: "100%_done.mp4")
        try await insertVideo("w_2", filename: "1000_done.mp4")

        let response = try await app.sendRequest(.GET, "/api/v1/videos?search=\(encodedQuery("100%_"))")
        let result = try response.content.decode(PaginatedVideosResponse.self)
        XCTAssertEqual(result.videos.map(\.fileId), ["w_1"])
    }

    // MARK: - §9 Limit / offset

    func testLimitIsClampedAndNegativeOffsetIsRejected() async throws {
        try await insertVideo("p_1", filename: "a.mp4")
        try await insertVideo("p_2", filename: "b.mp4")

        let negative = try await app.sendRequest(.GET, "/api/v1/videos?offset=-1")
        XCTAssertEqual(negative.status, .badRequest)

        let zero = try await app.sendRequest(.GET, "/api/v1/videos?limit=0")
        let zeroResult = try zero.content.decode(PaginatedVideosResponse.self)
        XCTAssertEqual(zeroResult.limit, 1)
        XCTAssertEqual(zeroResult.videos.count, 1)

        let huge = try await app.sendRequest(.GET, "/api/v1/videos?limit=999999999")
        XCTAssertEqual(try huge.content.decode(PaginatedVideosResponse.self).limit, 10_000)
    }

    // MARK: - §3 Simple list sortOrder

    func testSortOrderCanonicalization() {
        XCTAssertEqual(SimpleListSortOrder.canonical("filename_desc"), "filename_desc")
        XCTAssertEqual(SimpleListSortOrder.canonical("filenameDesc"), "filename_desc")
        XCTAssertEqual(SimpleListSortOrder.canonical("dateAddedDesc"), "date_added_desc")
        XCTAssertEqual(SimpleListSortOrder.canonical("playTime"), "play_time")
        XCTAssertNil(SimpleListSortOrder.canonical("random"))
    }

    func testSimpleListRoutesValidateSortOrder() async throws {
        let created = try await app.sendRequest(.POST, "/api/v1/simple-lists", headers: jsonHeaders,
                                                body: try jsonBody(["name": "faves", "sortOrder": "fileSizeDesc"]))
        XCTAssertEqual(created.status, .created)
        let stored = try await databaseManager.read { db in SimpleListRecord.findByName("faves", in: db) }
        XCTAssertEqual(stored?.sortOrder, "file_size_desc")

        let rejected = try await app.sendRequest(.POST, "/api/v1/simple-lists", headers: jsonHeaders,
                                                 body: try jsonBody(["name": "other", "sortOrder": "shuffle"]))
        XCTAssertEqual(rejected.status, .badRequest)

        let badUpdate = try await app.sendRequest(.PUT, "/api/v1/simple-lists/\(stored!.id.uuidString)", headers: jsonHeaders,
                                                  body: try jsonBody(["sortOrder": "shuffle"]))
        XCTAssertEqual(badUpdate.status, .badRequest)
    }

    func testSortOrderMigrationNormalizesExistingRows() async throws {
        try await databaseManager.write { db in
            try SimpleListRecord(name: "camel", sortOrder: "playCountDesc").insert(db)
            try SimpleListRecord(name: "unknown", sortOrder: "shuffle").insert(db)
            try SimpleListRecord(name: "fine", sortOrder: "date_added").insert(db)
            try V29_NormalizeSimpleListSortOrder.migrate(db)
        }
        let lists = try await databaseManager.read { db in
            Dictionary(uniqueKeysWithValues: try SimpleListRecord.fetchAll(db).map { ($0.name, $0.sortOrder) })
        }
        XCTAssertEqual(lists["camel"], "play_count_desc")
        XCTAssertEqual(lists["unknown"], "filename")
        XCTAssertEqual(lists["fine"], "date_added")
    }

    // MARK: - §4 Video tags

    func testAttachEndpointIsIdempotentAndReturnsTagList() async throws {
        try await insertVideo("t_1", filename: "a.mp4")
        let tag = try await insertTag("drama")

        for _ in 0..<2 {
            let response = try await app.sendRequest(.POST, "/api/v1/videos/t_1/tags/\(tag.id.uuidString)")
            XCTAssertEqual(response.status, .ok)
            let body = try response.content.decode(VideoTagsResponse.self)
            XCTAssertEqual(body.tags.map(\.id), [tag.id])
        }

        let unknownTag = try await app.sendRequest(.POST, "/api/v1/videos/t_1/tags/\(UUID().uuidString)")
        XCTAssertEqual(unknownTag.status, .notFound)
        let unknownVideo = try await app.sendRequest(.POST, "/api/v1/videos/nope/tags/\(tag.id.uuidString)")
        XCTAssertEqual(unknownVideo.status, .notFound)
    }

    func testBulkTagApplyAddsAndRemovesInOneTransaction() async throws {
        try await insertVideo("b_1", filename: "a.mp4")
        try await insertVideo("b_2", filename: "b.mp4")
        let add = try await insertTag("add")
        let remove = try await insertTag("remove")
        try await databaseManager.write { db in
            try VideoTagRecord(videoFileId: "b_1", tagId: remove.id).insert(db)
        }
        try await databaseManager.updateCatalogVersion(1)

        let response = try await app.sendRequest(.POST, "/api/v1/tags/apply", headers: jsonHeaders, body: try jsonBody([
            "fileIds": ["b_1", "b_2"],
            "addTagIds": [add.id.uuidString],
            "removeTagIds": [remove.id.uuidString],
        ]))
        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(try response.content.decode(BulkTagApplyResponse.self).updated, 2)

        let links = try await databaseManager.read { db in
            try VideoTagRecord.fetchAll(db).map { "\($0.videoFileId):\($0.tagId == add.id ? "add" : "remove")" }.sorted()
        }
        XCTAssertEqual(links, ["b_1:add", "b_2:add"])
        let versionAfter = try await databaseManager.fetchCatalogVersion()
        XCTAssertNotEqual(versionAfter, 1, "Catalog version is bumped")

        // Unknown fileId → 400, nothing applied
        let rejected = try await app.sendRequest(.POST, "/api/v1/tags/apply", headers: jsonHeaders, body: try jsonBody([
            "fileIds": ["b_1", "missing"],
            "addTagIds": [remove.id.uuidString],
        ]))
        XCTAssertEqual(rejected.status, .badRequest)
        let unknownTag = try await app.sendRequest(.POST, "/api/v1/tags/apply", headers: jsonHeaders, body: try jsonBody([
            "fileIds": ["b_1"],
            "addTagIds": [UUID().uuidString],
        ]))
        XCTAssertEqual(unknownTag.status, .badRequest)
        let count = try await databaseManager.read { db in try VideoTagRecord.fetchCount(db) }
        XCTAssertEqual(count, 2)
    }
}

private extension JSONDecoder {
    /// Strict Swift `.iso8601` decoder: canonical criteria must decode with it.
    static var iso8601Strict: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

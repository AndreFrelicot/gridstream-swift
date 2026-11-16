//
//  DemoServerTests.swift
//  gridstream-ipadTests
//

import GridStreamAPI
import XCTest
@testable import gridstream_ipad

/// A small catalog: three videos, two tags, lists, annotations and ranges.
enum DemoFixture {
    static let sourceDirectoryId = UUID(uuidString: "00000000-0000-0000-0000-0000000000D0")!
    static let favorites = UUID(uuidString: "00000000-0000-0000-0000-0000000000F1")!
    static let outdoor = UUID(uuidString: "00000000-0000-0000-0000-0000000000F2")!
    static let goodList = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    static let loopList = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
    static let pickedList = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!

    static func date(_ string: String) -> Date {
        TolerantDateDecoding.date(from: string)!
    }

    static func criteria(_ conditions: [FilterCondition]) -> String {
        try! SmartListCriteria(conditions: conditions).canonicalJSON()
    }

    static func video(_ fileId: String, _ filename: String, duration: Double, megabytes: Int64,
                      created: String, modified: String, rating: Int, playCount: Int) -> DemoStore.Video {
        DemoStore.Video(
            id: UUID(), fileId: fileId, filename: filename, duration: duration, width: 1280, height: 720,
            codec: "h264", fileSize: megabytes * 1024 * 1024, lastModified: date(modified), createdAt: date(created),
            rating: rating, playCount: playCount, totalViewTime: playCount * 20,
            lastPlayedAt: playCount > 0 ? date("2026-04-01T10:00:00Z") : nil
        )
    }

    static func store() -> DemoStore {
        let now = date("2026-04-01T00:00:00Z")
        return DemoStore(
            catalogVersion: 1,
            sourceDirectoryId: sourceDirectoryId,
            sourceDirectoryName: "Demo",
            videos: [
                video("aaaa", "Alpha_take_01.mov", duration: 30, megabytes: 10,
                      created: "2026-01-01T00:00:00Z", modified: "2026-01-05T00:00:00Z", rating: 8, playCount: 3),
                video("bbbb", "beta_take_02.mp4", duration: 60, megabytes: 50,
                      created: "2026-02-01T00:00:00Z", modified: "2026-02-05T00:00:00Z", rating: 0, playCount: 0),
                video("cccc", "Gamma 03.mov", duration: 45, megabytes: 100,
                      created: "2026-03-01T00:00:00Z", modified: "2026-03-05T00:00:00Z", rating: 4, playCount: 1)
            ],
            tags: [
                DemoStore.Tag(id: favorites, name: "favorites", color: "#ef4444", description: nil,
                              ratingEnabled: true, createdAt: now, updatedAt: now),
                DemoStore.Tag(id: outdoor, name: "outdoor", color: "#22c55e", description: nil,
                              ratingEnabled: false, createdAt: now, updatedAt: now)
            ],
            videoTags: [
                DemoStore.VideoTag(fileId: "aaaa", tagId: favorites, rating: 9),
                DemoStore.VideoTag(fileId: "bbbb", tagId: favorites, rating: 3),
                DemoStore.VideoTag(fileId: "aaaa", tagId: outdoor, rating: nil),
                DemoStore.VideoTag(fileId: "cccc", tagId: outdoor, rating: nil)
            ],
            smartLists: [
                DemoStore.SmartList(id: goodList, name: "good", criteria: criteria([
                    FilterCondition(criteriaType: .ratingMin(value: 4))
                ]), createdAt: now, updatedAt: now),
                // Includes itself: the cycle contributes nothing.
                DemoStore.SmartList(id: loopList, name: "loop", criteria: criteria([
                    FilterCondition(criteriaType: .smartListInclude(smartListId: goodList)),
                    FilterCondition(criteriaType: .smartListInclude(smartListId: loopList), logicOperator: .or)
                ]), createdAt: now, updatedAt: now)
            ],
            simpleLists: [
                DemoStore.SimpleList(id: pickedList, name: "picked", sortOrder: "filename",
                                     videoIds: ["cccc", "aaaa"], createdAt: now, updatedAt: now)
            ],
            annotations: [
                AnnotationDTO(id: UUID(), videoFileId: "aaaa", frameTime: 1, frameRate: 25, strokesJSON: "[]",
                              text: "Nice café shot", createdAt: now, updatedAt: now),
                AnnotationDTO(id: UUID(), videoFileId: "cccc", frameTime: 2, frameRate: 25, strokesJSON: "[]",
                              text: nil, createdAt: now, updatedAt: now)
            ],
            timeRanges: [
                TimeRangeDTO(id: UUID(), videoFileId: "bbbb", startTime: 5, endTime: 10, label: nil,
                             createdAt: now, updatedAt: now),
                // Starts after the end of the video: not playable.
                TimeRangeDTO(id: UUID(), videoFileId: "cccc", startTime: 50, endTime: 60, label: nil,
                             createdAt: now, updatedAt: now)
            ],
            captures: []
        )
    }
}

@MainActor
final class DemoCriteriaEvaluatorTests: XCTestCase {
    private let evaluator = DemoCriteriaEvaluator(store: DemoFixture.store())

    private func assertMatches(_ type: CriteriaType, _ expected: Set<String>, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(evaluator.fileIds(matching: type), expected, "\(type)", file: file, line: line)
    }

    func testTagsInclude() async {
        assertMatches(.tagsInclude(tagIds: [DemoFixture.favorites], tagRatings: []), ["aaaa", "bbbb"])
        assertMatches(.tagsInclude(tagIds: [DemoFixture.favorites, DemoFixture.outdoor], tagRatings: []), ["aaaa"])
        assertMatches(.tagsInclude(tagIds: [DemoFixture.favorites],
                                   tagRatings: [TagRatingFilter(tagId: DemoFixture.favorites, minRating: 5)]), ["aaaa"])
        assertMatches(.tagsInclude(tagIds: [DemoFixture.outdoor],
                                   tagRatings: [TagRatingFilter(tagId: DemoFixture.outdoor, maxRating: 10)]), [])
    }

    func testTagsExclude() async {
        assertMatches(.tagsExclude(tagIds: [DemoFixture.outdoor]), ["bbbb"])
    }

    func testRatingBounds() async {
        assertMatches(.ratingMin(value: 4), ["aaaa", "cccc"])
        assertMatches(.ratingMax(value: 4), ["bbbb", "cccc"])
        assertMatches(.unrated, ["bbbb"])
    }

    func testSourceDirectory() async {
        assertMatches(.sourceDirectory(id: DemoFixture.sourceDirectoryId.uuidString), ["aaaa", "bbbb", "cccc"])
        assertMatches(.sourceDirectory(id: UUID().uuidString), [])
        assertMatches(.sourceDirectory(id: "not-a-uuid"), [])
    }

    func testFileSize() async {
        assertMatches(.fileSizeMin(megabytes: 40), ["bbbb", "cccc"])
        assertMatches(.fileSizeMax(megabytes: 50), ["aaaa", "bbbb"])
    }

    func testFilenameMatchesIgnoreASCIICaseLikeSQLite() async {
        assertMatches(.filenameContains(text: "TAKE"), ["aaaa", "bbbb"])
        assertMatches(.filenameStartsWith(text: "alpha"), ["aaaa"])
        assertMatches(.filenameEndsWith(text: ".MOV"), ["aaaa", "cccc"])
    }

    func testFilenameRegexIsCaseSensitive() async {
        assertMatches(.filenameRegex(pattern: "^[a-z]+_take"), ["bbbb"])
        assertMatches(.filenameRegex(pattern: "("), [])
    }

    func testDates() async {
        assertMatches(.dateAddedAfter(date: DemoFixture.date("2026-01-15")), ["bbbb", "cccc"])
        assertMatches(.dateAddedBefore(date: DemoFixture.date("2026-01-15")), ["aaaa"])
        assertMatches(.dateModifiedAfter(date: DemoFixture.date("2026-02-10")), ["cccc"])
        assertMatches(.dateModifiedBefore(date: DemoFixture.date("2026-02-10")), ["aaaa", "bbbb"])
    }

    func testPlayCount() async {
        assertMatches(.playCountMin(value: 1), ["aaaa", "cccc"])
        assertMatches(.playCountMax(value: 0), ["bbbb"])
        assertMatches(.unplayed, ["bbbb"])
    }

    func testAnnotations() async {
        assertMatches(.hasAnnotations(value: true), ["aaaa", "cccc"])
        assertMatches(.hasAnnotations(value: false), ["bbbb"])
        assertMatches(.annotationCountMin(value: 1), ["aaaa", "cccc"])
        assertMatches(.annotationCountMax(value: 0), ["bbbb"])
        assertMatches(.hasTextAnnotations(value: true), ["aaaa"])
        assertMatches(.hasTextAnnotations(value: false), ["bbbb", "cccc"])
    }

    func testAnnotationTextSearchMatchesAPhraseLikeFTS() async {
        assertMatches(.annotationTextSearch(text: "cafe SHOT"), ["aaaa"])
        assertMatches(.annotationTextSearch(text: "shot nice"), [])
        assertMatches(.annotationTextSearch(text: "  "), [])
    }

    func testTimeRangesMustBePlayable() async {
        assertMatches(.hasTimeRanges(value: true), ["bbbb"])
        assertMatches(.hasTimeRanges(value: false), ["aaaa", "cccc"])
    }

    func testLists() async {
        assertMatches(.simpleListInclude(simpleListId: DemoFixture.pickedList), ["aaaa", "cccc"])
        assertMatches(.smartListInclude(smartListId: DemoFixture.goodList), ["aaaa", "cccc"])
        assertMatches(.smartListInclude(smartListId: DemoFixture.loopList), ["aaaa", "cccc"])
        assertMatches(.smartListInclude(smartListId: UUID()), [])
    }

    func testConditionsCombineLeftToRight() async {
        XCTAssertEqual(evaluator.fileIds(matching: SmartListCriteria()), ["aaaa", "bbbb", "cccc"])
        XCTAssertEqual(evaluator.fileIds(matching: SmartListCriteria(conditions: [
            FilterCondition(criteriaType: .ratingMin(value: 4)),
            FilterCondition(criteriaType: .unplayed, logicOperator: .or)
        ])), ["aaaa", "bbbb", "cccc"])
        XCTAssertEqual(evaluator.fileIds(matching: SmartListCriteria(conditions: [
            FilterCondition(criteriaType: .tagsInclude(tagIds: [DemoFixture.favorites], tagRatings: [])),
            FilterCondition(criteriaType: .ratingMin(value: 4))
        ])), ["aaaa"])
    }
}

@MainActor
final class DemoServerTests: XCTestCase {
    private func makeServer(store: DemoStore? = DemoFixture.store(), stateURL: URL? = nil) -> DemoServer {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("demo-\(UUID().uuidString)")
        return DemoServer(packDirectory: folder, stateURL: stateURL, capturesDirectory: folder.appendingPathComponent("captures"), store: store)
    }

    private func request(
        _ server: DemoServer, _ method: String, _ path: String,
        query: [URLQueryItem] = [], body: (any Encodable)? = nil
    ) async throws -> DemoResponse {
        var components = URLComponents(url: DemoMode.serverURL.appendingPathComponent("api/v1/" + path), resolvingAgainstBaseURL: false)!
        components.setQueryItemsEncodingPlus(query)
        let data = try body.map { try JSONEncoder.gridStream().encode($0) }
        return await server.handle(method: method, url: components.url!, body: data)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ response: DemoResponse, file: StaticString = #filePath, line: UInt = #line) throws -> T {
        try JSONDecoder.gridStream().decode(type, from: response.body)
    }

    private func reason(_ response: DemoResponse) -> String? {
        (try? JSONSerialization.jsonObject(with: response.body) as? [String: Any])?["reason"] as? String
    }

    private func catalogVersion(_ server: DemoServer) async throws -> Int64 {
        try decode(CatalogStatusDTO.self, try await request(server, "GET", "catalog/status")).version
    }

    // MARK: - Routing

    func testPathPatternsCaptureParameters() async {
        XCTAssertEqual(DemoServer.match("videos/:id/tags/:tagId", ["videos", "abc", "tags", "t1"]), ["abc", "t1"])
        XCTAssertNil(DemoServer.match("videos/:id/tags", ["videos", "abc"]))
        XCTAssertNil(DemoServer.match("smart-lists/memberships", ["smart-lists", "other"]))
    }

    func testUnknownRouteIs404() async throws {
        let response = try await request(makeServer(), "GET", "nothing/here")
        XCTAssertEqual(response.status, 404)
    }

    func testMissingPackAnswers503() async throws {
        let response = try await request(makeServer(store: nil), "GET", "auth/session")
        XCTAssertEqual(response.status, 503)
    }

    func testSessionNeedsNoPIN() async throws {
        let session = try decode(AuthSessionResponse.self, try await request(makeServer(), "GET", "auth/session"))
        XCTAssertFalse(session.authEnabled)
        XCTAssertTrue(session.authenticated)
    }

    // MARK: - Videos

    func testVideosAreSortedAndPaged() async throws {
        let server = makeServer()
        let sorted = try decode(PaginatedVideosResponse.self, try await request(server, "GET", "videos", query: [
            URLQueryItem(name: "sort", value: "rating_desc")
        ]))
        XCTAssertEqual(sorted.videos.map(\.fileId), ["aaaa", "cccc", "bbbb"])

        let page = try decode(PaginatedVideosResponse.self, try await request(server, "GET", "videos", query: [
            URLQueryItem(name: "limit", value: "1"), URLQueryItem(name: "offset", value: "1")
        ]))
        XCTAssertEqual(page.videos.map(\.fileId), ["bbbb"], "Default order is the filename, ignoring case")
        XCTAssertEqual(page.total, 3)
    }

    func testVideoFiltersCombine() async throws {
        let server = makeServer()
        let tagged = try decode(PaginatedVideosResponse.self, try await request(server, "GET", "videos", query: [
            URLQueryItem(name: "tags", value: DemoFixture.favorites.uuidString),
            URLQueryItem(name: "tagRatings", value: "\(DemoFixture.favorites.uuidString):5-")
        ]))
        XCTAssertEqual(tagged.videos.map(\.fileId), ["aaaa"])

        let criteria = DemoFixture.criteria([FilterCondition(criteriaType: .ratingMin(value: 4))])
        let searched = try decode(PaginatedVideosResponse.self, try await request(server, "GET", "videos", query: [
            URLQueryItem(name: "criteria", value: criteria),
            URLQueryItem(name: "search", value: "gamma")
        ]))
        XCTAssertEqual(searched.videos.map(\.fileId), ["cccc"])
    }

    func testInvalidCriteriaIs400() async throws {
        let response = try await request(makeServer(), "GET", "videos", query: [URLQueryItem(name: "criteria", value: "{")])
        XCTAssertEqual(response.status, 400)
    }

    func testVideoItemCarriesDerivedFields() async throws {
        let video = try decode(VideoItem.self, try await request(makeServer(), "GET", "videos/by-file-id/aaaa"))
        XCTAssertEqual(video.annotationCount, 1)
        XCTAssertEqual(video.tags?.first { $0.id == DemoFixture.favorites }?.rating, 9)
        XCTAssertEqual(video.thumbnailUrl, "/api/v1/videos/aaaa/thumbnail?v=1")
        XCTAssertEqual(video.sourceDirectoryName, "Demo")
    }

    func testUnknownVideoIs404() async throws {
        let response = try await request(makeServer(), "GET", "videos/by-file-id/zzzz")
        XCTAssertEqual(response.status, 404)
    }

    // MARK: - Writes

    func testRatingIsSavedAndBumpsTheCatalogVersion() async throws {
        let server = makeServer()
        let before = try await catalogVersion(server)

        let response = try await request(server, "PUT", "videos/bbbb/rating", body: RatingRequest(rating: 7))
        XCTAssertEqual(try decode(RatingDTO.self, response).rating, 7)
        let after = try await catalogVersion(server)
        XCTAssertGreaterThan(after, before)

        let invalid = try await request(server, "PUT", "videos/bbbb/rating", body: RatingRequest(rating: 11))
        XCTAssertEqual(invalid.status, 400)
        XCTAssertEqual(reason(invalid), "Rating must be between 0 and 10")
    }

    func testPlaybackStatsAccumulate() async throws {
        let server = makeServer()
        let stats = try decode(PlaybackStatsDTO.self, try await request(
            server, "POST", "videos/bbbb/playback-stats",
            body: PlaybackStatsRequest(incrementPlayCount: true, addViewTime: 12)
        ))
        XCTAssertEqual(stats.playCount, 1)
        XCTAssertEqual(stats.totalViewTime, 12)
    }

    func testTagsAreCreatedLowercasedAndUnique() async throws {
        let server = makeServer()
        let created = try await request(server, "POST", "tags", body: CreateTagRequest(
            name: "Close-Up", color: TagColorPalette.allColors[0], description: nil, ratingEnabled: nil
        ))
        XCTAssertEqual(created.status, 201)
        XCTAssertEqual(try decode(TagDTO.self, created).name, "close-up")

        let duplicate = try await request(server, "POST", "tags", body: CreateTagRequest(
            name: "close-up", color: TagColorPalette.allColors[0], description: nil, ratingEnabled: nil
        ))
        XCTAssertEqual(duplicate.status, 400)
    }

    func testDeletingATagRemovesItFromSmartLists() async throws {
        let server = makeServer()
        let created = try decode(SmartListDTO.self, try await request(server, "POST", "smart-lists", body: CreateSmartListRequest(
            name: "Outdoor",
            criteria: DemoFixture.criteria([FilterCondition(criteriaType: .tagsExclude(tagIds: [DemoFixture.outdoor]))])
        )))

        let deleted = try await request(server, "DELETE", "tags/\(DemoFixture.outdoor.uuidString)")
        XCTAssertEqual(try decode(TagDeleteResponse.self, deleted).affectedVideoCount, 2)

        let list = try decode(SmartListDTO.self, try await request(server, "GET", "smart-lists/\(created.id.uuidString)"))
        XCTAssertEqual(try SmartListCriteria.decode(json: list.criteria).conditions.count, 0)
    }

    func testTagRatingNeedsAnAssignedRatingTag() async throws {
        let server = makeServer()
        let notAssigned = try await request(
            server, "PUT", "videos/cccc/tags/\(DemoFixture.favorites.uuidString)/rating", body: RatingRequest(rating: 5)
        )
        XCTAssertEqual(notAssigned.status, 404)

        let notRated = try await request(
            server, "PUT", "videos/aaaa/tags/\(DemoFixture.outdoor.uuidString)/rating", body: RatingRequest(rating: 5)
        )
        XCTAssertEqual(notRated.status, 400)
    }

    func testBulkTagApplyCountsChangedVideos() async throws {
        let server = makeServer()
        let response = try decode(BulkTagApplyResponse.self, try await request(server, "POST", "tags/apply", body: BulkTagApplyRequest(
            fileIds: ["aaaa", "bbbb"], addTagIds: [DemoFixture.outdoor], removeTagIds: nil
        )))
        XCTAssertEqual(response.updated, 1, "Only bbbb did not have the tag")
    }

    func testSmartListMemberships() async throws {
        let response = try decode(SmartListMembershipsResponse.self, try await request(makeServer(), "GET", "smart-lists/memberships"))
        XCTAssertEqual(Set(response.memberships["aaaa"] ?? []), [DemoFixture.goodList, DemoFixture.loopList])
        XCTAssertNil(response.memberships["bbbb"])
    }

    func testInvalidSmartListCriteriaIs400() async throws {
        let response = try await request(makeServer(), "POST", "smart-lists", body: CreateSmartListRequest(
            name: "bad", criteria: DemoFixture.criteria([FilterCondition(criteriaType: .ratingMin(value: 42))])
        ))
        XCTAssertEqual(response.status, 400)
    }

    func testSimpleListAppendsNewVideosOnly() async throws {
        let list = try decode(SimpleListDTO.self, try await request(
            makeServer(), "POST", "simple-lists/\(DemoFixture.pickedList.uuidString)/videos",
            body: AddVideosRequest(videoIds: ["aaaa", "bbbb"])
        ))
        XCTAssertEqual(list.videoIds, ["cccc", "aaaa", "bbbb"])
    }

    func testAnnotationUpsertReplacesTheSameFrame() async throws {
        let server = makeServer()
        let first = try decode(AnnotationDTO.self, try await request(server, "PUT", "videos/bbbb/annotations", body: UpsertAnnotationRequest(
            frameTime: 3, frameRate: 25, strokesJSON: "[]", text: "first"
        )))
        let second = try decode(AnnotationDTO.self, try await request(server, "PUT", "videos/bbbb/annotations", body: UpsertAnnotationRequest(
            frameTime: 3, frameRate: 25, strokesJSON: "[]", text: ""
        )))
        XCTAssertEqual(first.id, second.id)
        XCTAssertNil(second.text, "An empty text clears it")

        let deleted = try await request(server, "DELETE", "videos/bbbb/annotations/\(first.id.uuidString)")
        XCTAssertEqual(deleted.status, 204)
    }

    func testTimeRangeValidation() async throws {
        let server = makeServer()
        let created = try await request(server, "POST", "videos/aaaa/time-ranges", body: CreateTimeRangeRequest(startTime: 1, endTime: 2, label: nil))
        XCTAssertEqual(created.status, 201)

        let invalid = try await request(server, "POST", "videos/aaaa/time-ranges", body: CreateTimeRangeRequest(startTime: 2, endTime: 1, label: nil))
        XCTAssertEqual(invalid.status, 400)
        XCTAssertEqual(reason(invalid), "Start time must be less than end time")
    }

    func testCachedTimesCoverTheWholeVideo() async throws {
        let response = try await request(makeServer(), "GET", "videos/aaaa/scrub/cached-times")
        let times = try JSONDecoder().decode(DemoCachedTimes.self, from: response.body)
        XCTAssertEqual(times.times.first, 0)
        XCTAssertEqual(times.cachedCount, times.totalFrames)
        XCTAssertEqual(times.totalFrames, 15)
    }

    // MARK: - Persistence

    func testStateIsSavedAndReloaded() async throws {
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("demo-state-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: stateURL) }

        let server = makeServer(stateURL: stateURL)
        _ = try await request(server, "PUT", "videos/bbbb/rating", body: RatingRequest(rating: 6))

        let reloaded = makeServer(store: nil, stateURL: stateURL)
        let video = try decode(VideoItem.self, try await request(reloaded, "GET", "videos/by-file-id/bbbb"))
        XCTAssertEqual(video.rating, 6)
    }

    func testResetRestoresTheSeedWithAHigherVersion() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("demo-pack-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try DemoFixture.store().encoded().write(to: folder.appendingPathComponent("seed.json"))

        let server = DemoServer(
            packDirectory: folder, stateURL: folder.appendingPathComponent("state.json"),
            capturesDirectory: folder.appendingPathComponent("captures")
        )
        _ = try await request(server, "PUT", "videos/bbbb/rating", body: RatingRequest(rating: 6))
        let versionBeforeReset = try await catalogVersion(server)

        try await server.reset()

        let video = try decode(VideoItem.self, try await request(server, "GET", "videos/by-file-id/bbbb"))
        XCTAssertEqual(video.rating, 0)
        let versionAfterReset = try await catalogVersion(server)
        XCTAssertGreaterThan(versionAfterReset, versionBeforeReset)
    }

    // MARK: - URL loading

    func testAPISessionReachesTheDemoServer() async throws {
        let previous = DemoURLProtocol.server
        DemoURLProtocol.server = makeServer()
        defer { DemoURLProtocol.server = previous }

        let session = ServerSessionManager.makeAPISession()
        let url = DemoMode.serverURL.appendingPathComponent("api/v1/catalog/status")
        let (data, response) = try await session.data(from: url)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(try JSONDecoder.gridStream().decode(CatalogStatusDTO.self, from: data).version, 1)
    }

    func testRequestBodiesReachTheDemoServer() async throws {
        let previous = DemoURLProtocol.server
        DemoURLProtocol.server = makeServer()
        defer { DemoURLProtocol.server = previous }

        var request = URLRequest(url: DemoMode.serverURL.appendingPathComponent("api/v1/videos/bbbb/rating"))
        request.httpMethod = "PUT"
        request.httpBody = try JSONEncoder.gridStream().encode(RatingRequest(rating: 5))
        let (data, _) = try await ServerSessionManager.makeAPISession().data(for: request)

        XCTAssertEqual(try JSONDecoder.gridStream().decode(RatingDTO.self, from: data).rating, 5)
    }

    func testOnlyDemoStreamsMapToFiles() async {
        let real = URL(string: "http://mozart.local:8080/api/v1/videos/aaaa/stream")!
        XCTAssertEqual(DemoMode.playableURL(for: real), real)

        let missing = DemoMode.serverURL.appendingPathComponent("api/v1/videos/no-such-clip/stream")
        XCTAssertEqual(DemoMode.playableURL(for: missing), missing, "No clip, no mapping")
    }
}

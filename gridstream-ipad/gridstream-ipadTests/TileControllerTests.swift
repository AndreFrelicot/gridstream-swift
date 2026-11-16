//
//  TileControllerTests.swift
//  gridstream-ipadTests
//
//  Per-tile metadata: responses for a video the tile has left are dropped,
//  and failed rating saves roll back.
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class TileControllerTests: XCTestCase {

    private let serverURL = URL(string: "http://studio.local:8080")!
    private let otherServerURL = URL(string: "http://other.local:8080")!
    private var keychainService = ""
    /// Released in `tearDown`, inside a Swift task.
    private var outlivingTheTest: [AnyObject] = []

    override func tearDown() async throws {
        outlivingTheTest = []
        StubURLProtocol.reset { _ in .init() }
        try await super.tearDown()
    }

    private func makeController(playCount: Int = 0, viewTime: Int = 0) -> TileController {
        keychainService = "com.gridstream.ipad.tests.\(UUID().uuidString)"
        let session = ServerSessionManager(
            urlSession: ServerSessionManager.makeAPISession(protocolClasses: [StubURLProtocol.self]),
            keychainService: keychainService
        )
        return TileController(
            playCount: playCount,
            viewTime: viewTime,
            session: session,
            membershipStore: SmartListMembershipStore(service: SmartListService(sessionManager: session))
        )
    }

    /// A tile view makes a controller every time SwiftUI builds it and keeps
    /// only the first: the others are dropped during a view update, outside
    /// any Swift task, where a compiler-made isolated deinit aborts.
    func testAControllerCanBeReleasedOutsideASwiftTask() {
        let session = ServerSessionManager(
            urlSession: ServerSessionManager.makeAPISession(protocolClasses: [StubURLProtocol.self]),
            keychainService: "com.gridstream.ipad.tests.\(UUID().uuidString)"
        )
        let store = SmartListMembershipStore(service: SmartListService(sessionManager: session))
        outlivingTheTest = [session, store]

        weak var released: TileController?
        autoreleasepool {
            let controller = TileController(session: session, membershipStore: store)
            released = controller
        }
        XCTAssertNil(released)
    }

    private func videoInfoJSON(
        fileId: String, rating: Int, playCount: Int = 0, viewTime: Int = 0, tagId: UUID, tagRating: Int = 6
    ) -> Data {
        Data("""
        {"id":"\(UUID().uuidString)","fileId":"\(fileId)","filename":"a.mp4","relativePath":"a.mp4",
         "duration":10,"width":1920,"height":1080,"codec":"h264","fileSize":100,
         "sourceDirectoryId":"\(UUID().uuidString)","lastModified":"2026-01-01T00:00:00Z",
         "rating":\(rating),"playCount":\(playCount),"totalViewTime":\(viewTime),
         "tags":[{"id":"\(tagId.uuidString)","name":"Take","color":"#FF0000","ratingEnabled":true,"rating":\(tagRating)}]}
        """.utf8)
    }

    /// Shows file-a with its ratings loaded from the server, then answers
    /// later requests with `reply`.
    private func showLoadedVideo(
        _ controller: TileController,
        rating: Int,
        tagId: UUID = UUID(),
        tagRating: Int = 6,
        then reply: @escaping (URLRequest) -> StubURLProtocol.Reply
    ) async {
        let body = videoInfoJSON(fileId: "file-a", rating: rating, tagId: tagId, tagRating: tagRating)
        StubURLProtocol.reset { _ in .init(body: body) }
        controller.show(videoId: "file-a", serverURL: serverURL)
        await controller.loadRating()?.value
        StubURLProtocol.reset(reply)
    }

    private func timeRangeJSON(fileId: String, start: Double, end: Double) -> Data {
        Data("""
        {"id":"\(UUID().uuidString)","videoFileId":"\(fileId)","startTime":\(start),"endTime":\(end),
         "label":null,"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}
        """.utf8)
    }

    // MARK: - Loading

    func testLoadRatingAppliesTheShownVideo() async {
        let controller = makeController()
        let tagId = UUID()
        StubURLProtocol.reset { [self] _ in
            .init(body: videoInfoJSON(fileId: "file-a", rating: 7, playCount: 3, viewTime: 42, tagId: tagId))
        }
        controller.show(videoId: "file-a", serverURL: serverURL)

        await controller.loadRating()?.value

        XCTAssertEqual(controller.ratingInfo.globalRating, 7)
        XCTAssertEqual(controller.ratingInfo.tagRatings[tagId], 6)
        XCTAssertEqual(controller.videoTags.map(\.id), [tagId])
        XCTAssertEqual(controller.playCount, 3)
        XCTAssertEqual(controller.viewTime, 42)
        XCTAssertEqual(StubURLProtocol.requests.first?.url?.path, "/api/v1/videos/by-file-id/file-a")
    }

    func testLoadRatingDropsAResponseForAPreviousVideo() async {
        let controller = makeController(playCount: 1, viewTime: 2)
        StubURLProtocol.reset { [self] _ in
            .init(body: videoInfoJSON(fileId: "file-a", rating: 7, playCount: 3, viewTime: 42, tagId: UUID()))
        }
        controller.show(videoId: "file-a", serverURL: serverURL)
        let load = controller.loadRating()

        // The tile moves on before the response for file-a arrives.
        controller.show(videoId: "file-b", serverURL: serverURL)
        await load?.value

        XCTAssertEqual(controller.ratingInfo, VideoRatingInfo())
        XCTAssertTrue(controller.videoTags.isEmpty)
        XCTAssertEqual(controller.playCount, 1)
        XCTAssertEqual(controller.viewTime, 2)
    }

    func testLoadRatingDropsAResponseFromAPreviousServer() async {
        let controller = makeController()
        StubURLProtocol.reset { [self] _ in
            .init(body: videoInfoJSON(fileId: "file-a", rating: 7, playCount: 3, viewTime: 42, tagId: UUID()))
        }
        controller.show(videoId: "file-a", serverURL: serverURL)
        let load = controller.loadRating()

        controller.show(videoId: "file-a", serverURL: otherServerURL)
        await load?.value

        XCTAssertEqual(controller.ratingInfo.globalRating, 0)
    }

    func testLoadTimeRangesDropsAResponseForAPreviousVideo() async {
        let controller = makeController()
        StubURLProtocol.reset { [self] _ in
            let range = String(decoding: timeRangeJSON(fileId: "file-a", start: 1, end: 2), as: UTF8.self)
            return .init(body: Data(#"{"timeRanges":[\#(range)],"total":1}"#.utf8))
        }
        controller.show(videoId: "file-a", serverURL: serverURL)
        let load = controller.loadTimeRanges()

        controller.show(videoId: "file-b", serverURL: serverURL)
        await load?.value

        XCTAssertTrue(controller.timeRanges.isEmpty)
    }

    func testTimeRangeCreatedOnAPreviousVideoIsNotShown() async {
        let controller = makeController()
        StubURLProtocol.reset { [self] _ in
            .init(status: 201, body: timeRangeJSON(fileId: "file-a", start: 1, end: 2))
        }
        controller.show(videoId: "file-a", serverURL: serverURL)
        let create = controller.createTimeRange(start: 1, end: 2)

        controller.show(videoId: "file-b", serverURL: serverURL)
        await create?.value

        XCTAssertTrue(controller.timeRanges.isEmpty)
        XCTAssertEqual(StubURLProtocol.requests.first?.url?.path, "/api/v1/videos/file-a/time-ranges")
    }

    func testTimeRangeCreatedOnTheShownVideoIsAddedInOrder() async {
        let controller = makeController()
        StubURLProtocol.reset { [self] request in
            if request.httpMethod == "POST" {
                return .init(status: 201, body: timeRangeJSON(fileId: "file-a", start: 1, end: 2))
            }
            let later = String(decoding: timeRangeJSON(fileId: "file-a", start: 5, end: 6), as: UTF8.self)
            return .init(body: Data(#"{"timeRanges":[\#(later)],"total":1}"#.utf8))
        }
        controller.show(videoId: "file-a", serverURL: serverURL)
        await controller.loadTimeRanges()?.value
        controller.pendingToIStart = 1

        await controller.createTimeRange(start: 1, end: 2)?.value

        XCTAssertEqual(controller.timeRanges.map(\.startTime), [1, 5])
        XCTAssertNil(controller.pendingToIStart)
    }

    func testShowingAnotherVideoResetsToIEditing() async {
        let controller = makeController()
        controller.show(videoId: "file-a", serverURL: serverURL)
        controller.pendingToIStart = 3
        controller.editingToIRangeId = UUID()

        controller.show(videoId: "file-a", serverURL: serverURL)
        XCTAssertEqual(controller.pendingToIStart, 3)

        controller.show(videoId: "file-b", serverURL: serverURL)
        XCTAssertNil(controller.pendingToIStart)
        XCTAssertNil(controller.editingToIRangeId)
    }

    // MARK: - Rating Saves

    func testFailedRatingSaveRollsBack() async {
        let controller = makeController()
        await showLoadedVideo(controller, rating: 4) { _ in .init(status: 500, body: Data()) }

        let save = controller.setGlobalRating(8)
        XCTAssertEqual(controller.ratingInfo.globalRating, 8)
        await save?.value

        XCTAssertEqual(controller.ratingInfo.globalRating, 4)
        XCTAssertTrue(controller.ratingSaveFailed)
        XCTAssertEqual(StubURLProtocol.requests.first?.httpMethod, "PUT")
        XCTAssertEqual(StubURLProtocol.requests.first?.url?.path, "/api/v1/videos/file-a/rating")
    }

    /// The hearts write the new rating through the binding before they call
    /// the change handler.
    func testFailedRatingSaveRollsBackWhenTheBindingWasWrittenFirst() async {
        let controller = makeController()
        await showLoadedVideo(controller, rating: 4) { _ in .init(status: 500, body: Data()) }

        controller.ratingInfo.globalRating = 8
        await controller.setGlobalRating(8)?.value

        XCTAssertEqual(controller.ratingInfo.globalRating, 4)
        XCTAssertTrue(controller.ratingSaveFailed)
    }

    func testFailedRatingSaveRollsBackToTheLastSavedRating() async {
        let controller = makeController()
        await showLoadedVideo(controller, rating: 4) { _ in .init(body: Data(#"{"memberships":{}}"#.utf8)) }
        controller.ratingInfo.globalRating = 6
        await controller.setGlobalRating(6)?.value

        StubURLProtocol.reset { _ in .init(status: 500, body: Data()) }
        controller.ratingInfo.globalRating = 9
        await controller.setGlobalRating(9)?.value

        XCTAssertEqual(controller.ratingInfo.globalRating, 6)
    }

    func testSuccessfulRatingSaveKeepsTheNewRating() async {
        let controller = makeController()
        await showLoadedVideo(controller, rating: 4) { _ in .init(body: Data(#"{"memberships":{}}"#.utf8)) }

        await controller.setGlobalRating(8)?.value

        XCTAssertEqual(controller.ratingInfo.globalRating, 8)
        XCTAssertFalse(controller.ratingSaveFailed)
    }

    func testFailedRatingSaveKeepsARatingPickedMeanwhile() async {
        let controller = makeController()
        await showLoadedVideo(controller, rating: 4) { _ in .init(status: 500, body: Data()) }

        let save = controller.setGlobalRating(8)
        controller.ratingInfo.globalRating = 9
        await save?.value

        XCTAssertEqual(controller.ratingInfo.globalRating, 9)
        XCTAssertTrue(controller.ratingSaveFailed)
    }

    func testFailedRatingSaveForAPreviousVideoLeavesTheShownVideoAlone() async {
        let controller = makeController()
        await showLoadedVideo(controller, rating: 4) { _ in .init(status: 500, body: Data()) }

        let save = controller.setGlobalRating(8)
        controller.show(videoId: "file-b", serverURL: serverURL)
        controller.ratingInfo.globalRating = 8
        await save?.value

        XCTAssertEqual(controller.ratingInfo.globalRating, 8)
        XCTAssertFalse(controller.ratingSaveFailed)
    }

    func testFailedTagRatingSaveRollsBack() async {
        let controller = makeController()
        let tagId = UUID()
        await showLoadedVideo(controller, rating: 4, tagId: tagId, tagRating: 2) { _ in
            .init(status: 500, body: Data())
        }

        let save = controller.setTagRating(tagId, 9)
        XCTAssertEqual(controller.ratingInfo.tagRatings[tagId], 9)
        await save?.value

        XCTAssertEqual(controller.ratingInfo.tagRatings[tagId], 2)
        XCTAssertTrue(controller.ratingSaveFailed)
    }

    func testFailedTagRatingSaveRollsBackWhenTheBindingWasWrittenFirst() async {
        let controller = makeController()
        let tagId = UUID()
        await showLoadedVideo(controller, rating: 4, tagId: tagId, tagRating: 2) { _ in
            .init(status: 500, body: Data())
        }

        controller.ratingInfo.tagRatings[tagId] = 9
        await controller.setTagRating(tagId, 9)?.value

        XCTAssertEqual(controller.ratingInfo.tagRatings[tagId], 2)
    }

    // MARK: - Rating Display Edge Cases

    /// A load that was in flight when the rating was picked answers with the
    /// server's state from before the PUT: it must not put the old rating back.
    func testLateLoadDoesNotOverwriteARatingPickedMeanwhile() async {
        let controller = makeController()
        StubURLProtocol.reset { [self] request in
            if request.httpMethod == "GET", request.url?.path.contains("by-file-id") == true {
                return .init(body: videoInfoJSON(fileId: "file-a", rating: 0, tagId: UUID()))
            }
            return .init(body: Data(#"{"memberships":{}}"#.utf8))
        }
        controller.show(videoId: "file-a", serverURL: serverURL)
        let load = controller.loadRating()

        // The user rates before the load answers.
        controller.ratingInfo.globalRating = 7
        let save = controller.setGlobalRating(7)
        await load?.value
        await save?.value

        XCTAssertEqual(controller.ratingInfo.globalRating, 7)
    }

    /// Until the new video's ratings load, the tile must not show the
    /// previous video's hearts: tapping the heart that matches them toggles
    /// the new video's rating to 0 on the server.
    func testShowingAnotherVideoDoesNotKeepThePreviousRatings() async {
        let controller = makeController()
        let tagId = UUID()
        await showLoadedVideo(controller, rating: 6, tagId: tagId, tagRating: 3) { _ in
            .init(error: URLError(.notConnectedToInternet))
        }

        controller.show(videoId: "file-b", serverURL: serverURL)
        await controller.loadRating()?.value

        XCTAssertEqual(controller.ratingInfo, VideoRatingInfo())
    }

    func testNoTargetMeansNoRequest() async {
        let controller = makeController()
        StubURLProtocol.reset { _ in .init() }

        XCTAssertNil(controller.loadRating())
        XCTAssertNil(controller.setGlobalRating(5))
        XCTAssertNil(controller.loadTimeRanges())
        XCTAssertNil(controller.captureFrame(at: 1))

        XCTAssertEqual(controller.ratingInfo.globalRating, 0)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }
}

//
//  NetworkingContractTests.swift
//  gridstream-ipadTests
//
//  Media URL authorization and query encoding (contract §6, §7, §9),
//  server identity (§8), session 401/429 handling (§7) and tag request
//  shapes (§4).
//

import GridStreamAPI
import XCTest
@testable import gridstream_ipad

// MARK: - URLProtocol stub

nonisolated final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Reply {
        var status: Int = 200
        var headers: [String: String] = ["Content-Type": "application/json"]
        var body: Data = Data("{}".utf8)
        var error: URLError?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _reply: (URLRequest) -> Reply = { _ in Reply() }
    nonisolated(unsafe) private static var _requests: [URLRequest] = []
    nonisolated(unsafe) private static var _bodies: [Data] = []

    static func reset(_ reply: @escaping (URLRequest) -> Reply) {
        lock.withLock {
            _reply = reply
            _requests = []
            _bodies = []
        }
    }

    static var requests: [URLRequest] { lock.withLock { _requests } }
    static var bodies: [Data] { lock.withLock { _bodies } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.readBody(of: request)
        let reply = Self.lock.withLock { () -> Reply in
            Self._requests.append(request)
            Self._bodies.append(body)
            return Self._reply(request)
        }

        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: reply.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession moves `httpBody` into `httpBodyStream` before the protocol
    /// sees the request.
    private static func readBody(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

@MainActor
final class NetworkingContractTests: XCTestCase {

    private let serverURL = URL(string: "http://studio.local:8080")!

    private func makeSessionManager() -> (ServerSessionManager, String) {
        let keychainService = "com.gridstream.ipad.tests.\(UUID().uuidString)"
        let manager = ServerSessionManager(
            urlSession: ServerSessionManager.makeAPISession(protocolClasses: [StubURLProtocol.self]),
            keychainService: keychainService
        )
        return (manager, keychainService)
    }

    // MARK: - Media URLs (§6, §7, §9)

    func testStreamURLCarriesEncodedTokenQueryItem() async {
        let original = VideoURLBuilder.tokenProvider
        VideoURLBuilder.tokenProvider = { _ in "a+b/c=" }
        defer { VideoURLBuilder.tokenProvider = original }

        let url = VideoURLBuilder.buildStreamURL(from: serverURL, videoId: "file-1")

        XCTAssertEqual(
            url?.absoluteString,
            "http://studio.local:8080/api/v1/videos/file-1/stream?stats=client&token=a%2Bb/c%3D"
        )
    }

    func testMediaURLsHaveNoTokenWithoutSession() async {
        let original = VideoURLBuilder.tokenProvider
        VideoURLBuilder.tokenProvider = { _ in nil }
        defer { VideoURLBuilder.tokenProvider = original }

        let url = VideoURLBuilder.buildThumbnailURL(from: serverURL, videoId: "file-1")

        XCTAssertEqual(url?.absoluteString, "http://studio.local:8080/api/v1/videos/file-1/thumbnail")
    }

    func testAuthorizeReplacesExistingToken() async {
        let original = VideoURLBuilder.tokenProvider
        VideoURLBuilder.tokenProvider = { _ in "new" }
        defer { VideoURLBuilder.tokenProvider = original }

        let url = URL(string: "http://studio.local:8080/api/v1/videos/f/thumbnail?v=7&token=old")!

        XCTAssertEqual(
            VideoURLBuilder.authorize(url).absoluteString,
            "http://studio.local:8080/api/v1/videos/f/thumbnail?v=7&token=new"
        )
    }

    func testThumbnailCacheKeyIgnoresTokenButKeepsVersion() async {
        let a = URL(string: "http://studio.local:8080/api/v1/videos/f/thumbnail?v=7&token=one")!
        let b = URL(string: "http://studio.local:8080/api/v1/videos/f/thumbnail?v=7&token=two")!
        let newer = URL(string: "http://studio.local:8080/api/v1/videos/f/thumbnail?v=8&token=one")!

        XCTAssertEqual(ThumbnailPrefetcher.cacheKey(for: a), ThumbnailPrefetcher.cacheKey(for: b))
        XCTAssertNotEqual(ThumbnailPrefetcher.cacheKey(for: a), ThumbnailPrefetcher.cacheKey(for: newer))
        XCTAssertEqual(
            VideoURLBuilder.removingToken(from: a).absoluteString,
            "http://studio.local:8080/api/v1/videos/f/thumbnail?v=7"
        )
    }

    func testQueryItemsEncodePlus() async {
        var components = URLComponents(string: "http://studio.local:8080/api/v1/videos")!
        components.setQueryItemsEncodingPlus([
            URLQueryItem(name: "search", value: "C++ & more"),
            URLQueryItem(name: "fileSizeMin", value: "1e+3")
        ])

        XCTAssertEqual(components.percentEncodedQuery, "search=C%2B%2B%20%26%20more&fileSizeMin=1e%2B3")
    }

    func testStoringATokenBumpsTokenRevision() async {
        let (manager, _) = makeSessionManager()
        defer { manager.clearToken(for: serverURL) }
        let before = manager.tokenRevision

        XCTAssertTrue(manager.storeToken("fresh", for: serverURL))

        XCTAssertEqual(manager.tokenRevision, before + 1)
    }

    func testRefreshStreamURLsCarriesTheNewTokenOnThisServerOnly() async {
        let original = VideoURLBuilder.tokenProvider
        var token = "old"
        VideoURLBuilder.tokenProvider = { _ in token }
        defer { VideoURLBuilder.tokenProvider = original }
        let otherServer = URL(string: "http://other.local:8080")!
        let state = GridState()
        state.setTileCount(2)
        state.setVideoURL(VideoURLBuilder.buildStreamURL(from: serverURL, videoId: "a"), videoId: "a", playCount: 3, at: 0)
        let otherURL = VideoURLBuilder.buildStreamURL(from: otherServer, videoId: "b")
        state.setVideoURL(otherURL, videoId: "b", at: 1)

        token = "new"
        state.refreshStreamURLs(serverURL: serverURL)

        XCTAssertEqual(state.tiles[0].videoURL, VideoURLBuilder.buildStreamURL(from: serverURL, videoId: "a"))
        XCTAssertTrue(state.tiles[0].videoURL?.absoluteString.contains("token=new") == true)
        XCTAssertEqual(state.tiles[0].playCount, 3)
        XCTAssertEqual(state.tiles[1].videoURL, otherURL)
    }

    // MARK: - Server identity (§8)

    func testDiscoveredServerEqualityUsesNameHostAndPort() async {
        let server = DiscoveredServer(name: "Studio", hostname: "studio.local", port: 8080)

        XCTAssertEqual(server, DiscoveredServer(name: "Studio", hostname: "studio.local", port: 8080))
        XCTAssertNotEqual(server, DiscoveredServer(name: "Studio", hostname: "studio.local", port: 8081))
        XCTAssertNotEqual(server, DiscoveredServer(name: "Studio", hostname: "other.local", port: 8080))
        XCTAssertNotEqual(server, DiscoveredServer(name: "Office", hostname: "studio.local", port: 8080))
        XCTAssertEqual(server.id, "Studio|studio.local|8080")
        XCTAssertEqual(server.url?.absoluteString, "http://studio.local:8080")
    }

    // MARK: - 401 handling (§7)

    func testUnauthorizedWithStaleTokenKeepsCurrentSession() async {
        let (manager, _) = makeSessionManager()
        XCTAssertTrue(manager.storeToken("current", for: serverURL))
        defer { manager.clearToken(for: serverURL) }
        var expiredCount = 0
        manager.onSessionExpired = { _ in expiredCount += 1 }

        manager.handleUnauthorized(serverURL: serverURL, sentToken: "stale")

        XCTAssertEqual(manager.sessionToken(for: serverURL), "current")
        XCTAssertNotEqual(manager.state, .locked)
        XCTAssertEqual(expiredCount, 0)
    }

    func testUnauthorizedWithoutTokenWhileHoldingOneIsIgnored() async {
        let (manager, _) = makeSessionManager()
        XCTAssertTrue(manager.storeToken("current", for: serverURL))
        defer { manager.clearToken(for: serverURL) }

        manager.handleUnauthorized(serverURL: serverURL, sentToken: nil)

        XCTAssertEqual(manager.sessionToken(for: serverURL), "current")
        XCTAssertNotEqual(manager.state, .locked)
    }

    func testUnauthorizedWithoutAnySessionLocksWithoutExpiryCallback() async {
        let (manager, _) = makeSessionManager()
        var expiredCount = 0
        manager.onSessionExpired = { _ in expiredCount += 1 }

        manager.handleUnauthorized(serverURL: serverURL, sentToken: nil)

        XCTAssertEqual(manager.state, .locked)
        XCTAssertNil(manager.errorMessage)
        XCTAssertEqual(expiredCount, 0)
    }

    func testUnauthorizedWithCurrentTokenExpiresSessionOnce() async {
        let (manager, _) = makeSessionManager()
        XCTAssertTrue(manager.storeToken("current", for: serverURL))
        defer { manager.clearToken(for: serverURL) }
        var expiredCount = 0
        manager.onSessionExpired = { _ in expiredCount += 1 }

        manager.handleUnauthorized(serverURL: serverURL, sentToken: "current")
        XCTAssertEqual(manager.state, .locked)
        XCTAssertNil(manager.sessionToken(for: serverURL))
        XCTAssertEqual(expiredCount, 1)

        // Further 401s while already locked must not re-trigger rediscovery.
        XCTAssertTrue(manager.storeToken("next", for: serverURL))
        manager.handleUnauthorized(serverURL: serverURL, sentToken: "next")
        manager.handleUnauthorized(serverURL: serverURL, sentToken: nil)
        XCTAssertEqual(expiredCount, 1)
    }

    func testDataForRequestIgnores401ForSupersededToken() async throws {
        let (manager, _) = makeSessionManager()
        XCTAssertTrue(manager.storeToken("current", for: serverURL))
        defer { manager.clearToken(for: serverURL) }
        StubURLProtocol.reset { _ in .init(status: 401) }

        var request = URLRequest(url: serverURL.appendingPathComponent("api/v1/videos"))
        request.setValue("Bearer stale", forHTTPHeaderField: "Authorization")
        _ = try await manager.data(for: request, serverURL: serverURL)

        XCTAssertEqual(manager.sessionToken(for: serverURL), "current")
        XCTAssertNotEqual(manager.state, .locked)
    }

    // MARK: - Login (§7)

    func testRetryAfterParsesSecondsAndHTTPDate() async {
        let seconds = HTTPURLResponse(url: serverURL, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "120"])!
        XCTAssertEqual(ServerSessionManager.retryAfterSeconds(from: seconds), 120)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let httpDate = formatter.string(from: Date().addingTimeInterval(300))
        let dated = HTTPURLResponse(url: serverURL, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": httpDate])!
        let parsed = ServerSessionManager.retryAfterSeconds(from: dated)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed ?? 0, 300, accuracy: 5)

        let missing = HTTPURLResponse(url: serverURL, statusCode: 429, httpVersion: nil, headerFields: [:])!
        XCTAssertNil(ServerSessionManager.retryAfterSeconds(from: missing))
    }

    func testLoginRateLimitedSetsRetryAfter() async {
        let (manager, _) = makeSessionManager()
        StubURLProtocol.reset { _ in .init(status: 429, headers: ["Retry-After": "90"]) }

        let succeeded = await manager.login(pin: "1234", serverURL: serverURL)

        XCTAssertFalse(succeeded)
        XCTAssertEqual(manager.state, .locked)
        let remaining = manager.loginRetryAfter?.timeIntervalSinceNow ?? 0
        XCTAssertEqual(remaining, 90, accuracy: 5)
        XCTAssertTrue(manager.errorMessage?.contains("Too many attempts") ?? false)

        // While locked out, no request is sent.
        StubURLProtocol.reset { _ in .init(status: 200) }
        _ = await manager.login(pin: "1234", serverURL: serverURL)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testLoginDistinguishesWrongPinFromNetworkError() async {
        let (manager, _) = makeSessionManager()

        StubURLProtocol.reset { _ in .init(status: 401) }
        _ = await manager.login(pin: "0000", serverURL: serverURL)
        XCTAssertEqual(manager.errorMessage, "Incorrect PIN.")

        StubURLProtocol.reset { _ in .init(error: URLError(.cannotConnectToHost)) }
        _ = await manager.login(pin: "0000", serverURL: serverURL)
        XCTAssertTrue(manager.errorMessage?.hasPrefix("Can't reach the server") ?? false)
    }

    // MARK: - Tag request shapes (§4)

    func testAttachTagPostsToVideoTagRoute() async throws {
        let (manager, _) = makeSessionManager()
        XCTAssertTrue(manager.storeToken("tok", for: serverURL))
        defer { manager.clearToken(for: serverURL) }
        let tagId = UUID()
        let otherTag = UUID()
        StubURLProtocol.reset { _ in
            .init(body: Data(#"{"tags":[{"id":"\#(tagId.uuidString.lowercased())","name":"a"},{"id":"\#(otherTag.uuidString)","name":"b"}]}"#.utf8))
        }

        let tags = try await ContentLibraryService(sessionManager: manager)
            .attachTag(fileId: "file-1", tagId: tagId, serverURL: serverURL)

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/videos/file-1/tags/\(tagId.uuidString.lowercased())")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(tags, [tagId, otherTag])
    }

    func testDetachTagToleratesAlreadyDetached() async throws {
        let (manager, _) = makeSessionManager()
        let tagId = UUID()
        StubURLProtocol.reset { _ in .init(status: 404) }

        try await ContentLibraryService(sessionManager: manager)
            .detachTag(fileId: "file-1", tagId: tagId, serverURL: serverURL)

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/api/v1/videos/file-1/tags/\(tagId.uuidString.lowercased())")
    }

    func testBulkTagChangesPostToTagsApply() async throws {
        let (manager, _) = makeSessionManager()
        let add = UUID()
        let remove = UUID()
        StubURLProtocol.reset { _ in .init(body: Data(#"{"updated":2}"#.utf8)) }

        let updated = try await ContentLibraryService(sessionManager: manager).applyTagChanges(
            toFileIds: ["f1", "f2"],
            addTagIds: [add],
            removeTagIds: [remove],
            serverURL: serverURL
        )

        XCTAssertEqual(updated, 2)
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/tags/apply")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(StubURLProtocol.bodies.first)) as? [String: Any]
        )
        XCTAssertEqual(body["fileIds"] as? [String], ["f1", "f2"])
        XCTAssertEqual(body["addTagIds"] as? [String], [add.uuidString.lowercased()])
        XCTAssertEqual(body["removeTagIds"] as? [String], [remove.uuidString.lowercased()])
    }

    func testBulkTagChangesSurfaceServerReason() async {
        let (manager, _) = makeSessionManager()
        StubURLProtocol.reset { _ in
            .init(status: 400, body: Data(#"{"error":true,"reason":"Unknown tag id"}"#.utf8))
        }

        do {
            _ = try await ContentLibraryService(sessionManager: manager)
                .applyTagChanges(toFileIds: ["f1"], addTagIds: [UUID()], serverURL: serverURL)
            XCTFail("Expected an error")
        } catch APIError.serverError(let message) {
            XCTAssertEqual(message, "Unknown tag id")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - APIClient (§1, §7, §9)

    private struct DatedBody: Codable, Equatable {
        let when: Date
    }

    func testClientGetEncodesQueryPlusAndSendsBearer() async throws {
        let (manager, _) = makeSessionManager()
        XCTAssertTrue(manager.storeToken("tok", for: serverURL))
        defer { manager.clearToken(for: serverURL) }
        StubURLProtocol.reset { _ in .init(body: Data(#"{"version":7}"#.utf8)) }

        let status = try await APIClient(serverURL: serverURL, session: manager).fetch(
            CatalogStatusDTO.self, "catalog/status",
            query: [URLQueryItem(name: "search", value: "C++")]
        )

        XCTAssertEqual(status.version, 7)
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/v1/catalog/status")
        XCTAssertEqual(request.url?.query, "search=C%2B%2B")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertEqual(StubURLProtocol.bodies.first, Data())
    }

    func testClientEncodesBodyAsJSONWithISODates() async throws {
        let (manager, _) = makeSessionManager()
        StubURLProtocol.reset { _ in .init(status: 201) }

        try await APIClient(serverURL: serverURL, session: manager).send(
            .post, "things", body: DatedBody(when: Date(timeIntervalSince1970: 0)), expecting: [201]
        )

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(StubURLProtocol.bodies.first)) as? [String: Any]
        )
        XCTAssertEqual(body["when"] as? String, "1970-01-01T00:00:00Z")
    }

    func testClientDecodesTolerantDates() async throws {
        let (manager, _) = makeSessionManager()
        StubURLProtocol.reset { _ in .init(body: Data(#"{"when":"1970-01-01T00:00:01.500Z"}"#.utf8)) }

        let value = try await APIClient(serverURL: serverURL, session: manager).fetch(DatedBody.self, "things")

        XCTAssertEqual(value.when.timeIntervalSince1970, 1.5, accuracy: 0.001)
    }

    func testClientMapsFailuresToServerReasonOrStatus() async {
        let (manager, _) = makeSessionManager()
        let client = APIClient(serverURL: serverURL, session: manager)

        StubURLProtocol.reset { _ in .init(status: 400, body: Data(#"{"error":true,"reason":"Bad name"}"#.utf8)) }
        do {
            try await client.send(.delete, "tags/x")
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .serverError(message: "Bad name"))
        }

        StubURLProtocol.reset { _ in .init(status: 503, body: Data()) }
        do {
            try await client.send(.delete, "tags/x")
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .httpError(statusCode: 503))
        }
    }

    func testClientFetchIfPresentReturnsNilOn404() async throws {
        let (manager, _) = makeSessionManager()
        StubURLProtocol.reset { _ in .init(status: 404, body: Data(#"{"error":true,"reason":"Not Found"}"#.utf8)) }

        let value = try await APIClient(serverURL: serverURL, session: manager)
            .fetchIfPresent(DatedBody.self, "things/1")

        XCTAssertNil(value)
    }

    func testClient401WithCurrentTokenLocksTheSession() async {
        let (manager, _) = makeSessionManager()
        XCTAssertTrue(manager.storeToken("tok", for: serverURL))
        defer { manager.clearToken(for: serverURL) }
        StubURLProtocol.reset { _ in .init(status: 401, body: Data()) }

        do {
            try await APIClient(serverURL: serverURL, session: manager).send(.get, "tags")
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .httpError(statusCode: 401))
        }

        XCTAssertEqual(manager.state, .locked)
        XCTAssertNil(manager.sessionToken(for: serverURL))
    }

    // MARK: - Request shapes kept by the client migration

    func testAnnotationUpsertSendsNullText() async throws {
        let (manager, _) = makeSessionManager()
        StubURLProtocol.reset { _ in
            .init(body: Data(#"{"id":"A0000000-0000-4000-8000-000000000001","videoFileId":"file-1","frameTime":1.5,"frameRate":30,"strokesJSON":"[]","text":null,"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}"#.utf8))
        }

        let annotation = try await AnnotationAPIService(sessionManager: manager).upsertAnnotation(
            forFileId: "file-1", frameTime: 1.5, frameRate: 30, strokesJSON: "[]", text: nil, serverURL: serverURL
        )

        XCTAssertEqual(annotation.id.uuidString, "A0000000-0000-4000-8000-000000000001")
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/v1/videos/file-1/annotations")
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(StubURLProtocol.bodies.first)) as? [String: Any]
        )
        XCTAssertEqual(body["frameTime"] as? Double, 1.5)
        XCTAssertEqual(body["frameRate"] as? Double, 30)
        XCTAssertEqual(body["strokesJSON"] as? String, "[]")
        XCTAssertTrue(body.keys.contains("text"))
        XCTAssertTrue(body["text"] is NSNull)
    }

    func testCaptureFramePostsTimestampAndExpects201() async throws {
        let (manager, _) = makeSessionManager()
        StubURLProtocol.reset { _ in
            .init(status: 201, body: Data(#"{"id":"c1","fileId":"file-1","timestamp":2.5,"width":1920,"height":1080,"fileSize":10,"createdAt":"2026-01-01T00:00:00.123Z","filename":null}"#.utf8))
        }

        let capture = try await VideoAPIService(sessionManager: manager)
            .captureFrame(fileId: "file-1", timestamp: 2.5, serverURL: serverURL)

        XCTAssertEqual(capture.id, "c1")
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/videos/file-1/captures")
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(StubURLProtocol.bodies.first)) as? [String: Any]
        )
        XCTAssertEqual(body as NSDictionary, ["timestamp": 2.5] as NSDictionary)
    }

    func testCheckVideoExistsTreatsOnly404AsAbsent() async {
        let (manager, _) = makeSessionManager()
        let service = VideoAPIService(sessionManager: manager)

        StubURLProtocol.reset { _ in .init(status: 404) }
        let absent = await service.checkVideoExists(fileId: "file-1", serverURL: serverURL)
        XCTAssertFalse(absent)
        XCTAssertEqual(StubURLProtocol.requests.first?.url?.path, "/api/v1/videos/by-file-id/file-1")
        XCTAssertEqual(StubURLProtocol.requests.first?.timeoutInterval, 4)

        StubURLProtocol.reset { _ in .init(status: 500) }
        let transient = await service.checkVideoExists(fileId: "file-1", serverURL: serverURL)
        XCTAssertTrue(transient)
    }
}

import GridStreamAPI
import XCTest
import Vapor
import GRDB
@testable import gridstream_macos

final class VideoCatalogAPITests: XCTestCase {

    var testDatabaseURL: URL!
    var databaseManager: DatabaseManager!
    var app: Application!
    var catalogProvider: TestVideoCatalogProvider!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GridStreamCatalogTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        testDatabaseURL = testDir.appendingPathComponent("test_gridstream.sqlite")
        databaseManager = DatabaseManager(databasePath: testDatabaseURL)
        try await databaseManager.initialize()

        var env = try Environment.detect()
        env.arguments = ["vapor", "test"]
        app = try await Application.make(env)
        app.middleware.use(ErrorMiddleware.default(environment: app.environment))

        catalogProvider = TestVideoCatalogProvider(databaseManager: databaseManager)
        app.storage[VideoCatalogStorageKey.self] = catalogProvider

        try app.register(collection: VideoRoutes(databaseManager: databaseManager))
    }

    override func tearDown() async throws {
        try await databaseManager.close()
        try await app.asyncShutdown()
        let testDir = testDatabaseURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: testDir)
        databaseManager = nil
        testDatabaseURL = nil
        app = nil
        catalogProvider = nil
    }

    // MARK: - Test Helpers

    private func createTestSourceDirectory(
        id: UUID = UUID(),
        name: String = "Movies"
    ) -> SourceDirectory {
        SourceDirectory(
            id: id,
            path: "/test/\(name)",
            isEnabled: true
        )
    }

    private func createTestVideo(
        fileId: String,
        filename: String,
        sourceDirectoryId: UUID,
        rating: Int = 0,
        duration: Double = 120.0
    ) async throws -> VideoFileRecord {
        let video = VideoFileRecord(
            fileId: fileId,
            path: "/test/path/\(filename)",
            sourceDirectoryId: sourceDirectoryId,
            filename: filename,
            fileSize: 1000,
            duration: duration,
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

    private func createTestTag(name: String, color: String = TagColorPalette.blue) async throws -> TagRecord {
        let tag = TagRecord(name: name, color: color)
        try await databaseManager.write { db in
            try tag.insert(db)
        }
        return tag
    }

    private func assignTagToVideo(fileId: String, tagId: UUID) async throws {
        let videoTag = VideoTagRecord(videoFileId: fileId, tagId: tagId)
        try await databaseManager.write { db in
            let mutableVideoTag = videoTag
            try mutableVideoTag.insert(db)
        }
    }

    private func createAnnotation(fileId: String, frameTime: Double, text: String?) async throws {
        let annotation = AnnotationRecord(
            videoFileId: fileId,
            frameTime: frameTime,
            frameRate: 24,
            strokesJSON: "[]",
            text: text
        )

        try await databaseManager.write { db in
            try annotation.insert(db)
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM video_annotations WHERE video_file_id = ?", arguments: [fileId]) ?? 0
            try db.execute(sql: "UPDATE video_files SET annotation_count = ? WHERE file_id = ?", arguments: [count, fileId])
        }
    }

    private func createTimeRange(fileId: String, startTime: Double, endTime: Double) async throws {
        let range = TimeRangeRecord(videoFileId: fileId, startTime: startTime, endTime: endTime)

        try await databaseManager.write { db in
            try range.insert(db)
        }
    }

    private func videosPath(queryItems: [URLQueryItem]) -> String {
        var components = URLComponents()
        components.path = "/api/v1/videos"
        components.queryItems = queryItems
        return components.string ?? "/api/v1/videos"
    }

    // MARK: - Test 1: Search by video filename (case-insensitive)

    func testSearchByVideoFilenameCaseInsensitive() async throws {
        let sourceDir = createTestSourceDirectory()
        catalogProvider.sourceDirectories = [sourceDir]

        _ = try await createTestVideo(
            fileId: "file1",
            filename: "Action_Movie.mp4",
            sourceDirectoryId: sourceDir.id
        )
        _ = try await createTestVideo(
            fileId: "file2",
            filename: "comedy_film.mp4",
            sourceDirectoryId: sourceDir.id
        )
        _ = try await createTestVideo(
            fileId: "file3",
            filename: "Documentary.mp4",
            sourceDirectoryId: sourceDir.id
        )

        // Refresh catalog provider videos from database
        try await catalogProvider.refreshVideos()

        // Test lowercase search finds uppercase filename
        let response1 = try await app.sendRequest(.GET, "/api/v1/videos?search=action")
        XCTAssertEqual(response1.status, .ok)
        let result1 = try response1.content.decode(PaginatedVideosResponse.self)
        XCTAssertEqual(result1.videos.count, 1)
        XCTAssertEqual(result1.videos.first?.filename, "Action_Movie.mp4")

        // Test uppercase search finds lowercase filename
        let response2 = try await app.sendRequest(.GET, "/api/v1/videos?search=COMEDY")
        XCTAssertEqual(response2.status, .ok)
        let result2 = try response2.content.decode(PaginatedVideosResponse.self)
        XCTAssertEqual(result2.videos.count, 1)
        XCTAssertEqual(result2.videos.first?.filename, "comedy_film.mp4")
    }

    // MARK: - Test 2: Search by source directory name

    func testSearchBySourceDirectoryName() async throws {
        let sourceDir1 = createTestSourceDirectory(name: "Action_Movies")
        let sourceDir2 = createTestSourceDirectory(name: "Comedies")
        catalogProvider.sourceDirectories = [sourceDir1, sourceDir2]

        _ = try await createTestVideo(
            fileId: "file1",
            filename: "video1.mp4",
            sourceDirectoryId: sourceDir1.id
        )
        _ = try await createTestVideo(
            fileId: "file2",
            filename: "video2.mp4",
            sourceDirectoryId: sourceDir2.id
        )

        try await catalogProvider.refreshVideos()

        // Search by source directory name
        let response = try await app.sendRequest(.GET, "/api/v1/videos?search=action")
        XCTAssertEqual(response.status, .ok)
        let result = try response.content.decode(PaginatedVideosResponse.self)
        XCTAssertEqual(result.videos.count, 1)
        XCTAssertEqual(result.videos.first?.sourceDirectoryId, sourceDir1.id)
    }

    // MARK: - Test 3: Filter by tag IDs (multi-select)

    func testFilterByTagIds() async throws {
        let sourceDir = createTestSourceDirectory()
        catalogProvider.sourceDirectories = [sourceDir]

        let actionTag = try await createTestTag(name: "action", color: TagColorPalette.red)
        let comedyTag = try await createTestTag(name: "comedy", color: TagColorPalette.blue)
        let dramaTag = try await createTestTag(name: "drama", color: TagColorPalette.green)

        let video1 = try await createTestVideo(fileId: "file1", filename: "video1.mp4", sourceDirectoryId: sourceDir.id)
        let video2 = try await createTestVideo(fileId: "file2", filename: "video2.mp4", sourceDirectoryId: sourceDir.id)
        let video3 = try await createTestVideo(fileId: "file3", filename: "video3.mp4", sourceDirectoryId: sourceDir.id)

        // video1 has action and comedy tags
        try await assignTagToVideo(fileId: video1.fileId, tagId: actionTag.id)
        try await assignTagToVideo(fileId: video1.fileId, tagId: comedyTag.id)
        // video2 has action tag only
        try await assignTagToVideo(fileId: video2.fileId, tagId: actionTag.id)
        // video3 has drama tag only
        try await assignTagToVideo(fileId: video3.fileId, tagId: dramaTag.id)

        try await catalogProvider.refreshVideos()

        // Filter by single tag
        let response1 = try await app.sendRequest(.GET, "/api/v1/videos?tags=\(actionTag.id.uuidString)")
        XCTAssertEqual(response1.status, .ok)
        let result1 = try response1.content.decode(PaginatedVideosResponse.self)
        XCTAssertEqual(result1.videos.count, 2)

        // Filter by multiple tags (videos must have ALL specified tags)
        let response2 = try await app.sendRequest(.GET, "/api/v1/videos?tags=\(actionTag.id.uuidString),\(comedyTag.id.uuidString)")
        XCTAssertEqual(response2.status, .ok)
        let result2 = try response2.content.decode(PaginatedVideosResponse.self)
        XCTAssertEqual(result2.videos.count, 1)
        XCTAssertEqual(result2.videos.first?.fileId, "file1")
    }

    // MARK: - Test 4: Filter by rating range

    func testFilterByRatingRange() async throws {
        let sourceDir = createTestSourceDirectory()
        catalogProvider.sourceDirectories = [sourceDir]

        _ = try await createTestVideo(fileId: "file1", filename: "low.mp4", sourceDirectoryId: sourceDir.id, rating: 2)
        _ = try await createTestVideo(fileId: "file2", filename: "medium.mp4", sourceDirectoryId: sourceDir.id, rating: 5)
        _ = try await createTestVideo(fileId: "file3", filename: "high.mp4", sourceDirectoryId: sourceDir.id, rating: 9)

        try await catalogProvider.refreshVideos()

        // Filter by minRating
        let response1 = try await app.sendRequest(.GET, "/api/v1/videos?minRating=5")
        XCTAssertEqual(response1.status, .ok)
        let result1 = try response1.content.decode(PaginatedVideosResponse.self)
        XCTAssertEqual(result1.videos.count, 2)

        // Filter by maxRating
        let response2 = try await app.sendRequest(.GET, "/api/v1/videos?maxRating=5")
        XCTAssertEqual(response2.status, .ok)
        let result2 = try response2.content.decode(PaginatedVideosResponse.self)
        XCTAssertEqual(result2.videos.count, 2)

        // Filter by rating range
        let response3 = try await app.sendRequest(.GET, "/api/v1/videos?minRating=3&maxRating=7")
        XCTAssertEqual(response3.status, .ok)
        let result3 = try response3.content.decode(PaginatedVideosResponse.self)
        XCTAssertEqual(result3.videos.count, 1)
        XCTAssertEqual(result3.videos.first?.rating, 5)
    }

    // MARK: - Test 5: Combined filters return correct results

    func testCombinedFiltersReturnCorrectResults() async throws {
        let sourceDir1 = createTestSourceDirectory(name: "Movies")
        let sourceDir2 = createTestSourceDirectory(name: "TV_Shows")
        catalogProvider.sourceDirectories = [sourceDir1, sourceDir2]

        let actionTag = try await createTestTag(name: "action")

        // Movie with action tag and high rating
        let video1 = try await createTestVideo(
            fileId: "file1",
            filename: "Action_Movie.mp4",
            sourceDirectoryId: sourceDir1.id,
            rating: 8
        )
        try await assignTagToVideo(fileId: video1.fileId, tagId: actionTag.id)

        // Movie with action tag and low rating
        let video2 = try await createTestVideo(
            fileId: "file2",
            filename: "Bad_Action.mp4",
            sourceDirectoryId: sourceDir1.id,
            rating: 3
        )
        try await assignTagToVideo(fileId: video2.fileId, tagId: actionTag.id)

        // TV Show with action tag
        let video3 = try await createTestVideo(
            fileId: "file3",
            filename: "Action_Show.mp4",
            sourceDirectoryId: sourceDir2.id,
            rating: 9
        )
        try await assignTagToVideo(fileId: video3.fileId, tagId: actionTag.id)

        try await catalogProvider.refreshVideos()

        // Combine search, tag filter, and rating range
        let response = try await app.sendRequest(
            .GET,
            "/api/v1/videos?search=movie&tags=\(actionTag.id.uuidString)&minRating=5"
        )
        XCTAssertEqual(response.status, .ok)
        let result = try response.content.decode(PaginatedVideosResponse.self)
        XCTAssertEqual(result.videos.count, 1)
        XCTAssertEqual(result.videos.first?.fileId, "file1")
    }

    func testTextAnnotationFlatParamsFilterVideos() async throws {
        let sourceDir = createTestSourceDirectory()
        catalogProvider.sourceDirectories = [sourceDir]

        _ = try await createTestVideo(fileId: "text-video", filename: "text.mp4", sourceDirectoryId: sourceDir.id)
        _ = try await createTestVideo(fileId: "pencil-video", filename: "pencil.mp4", sourceDirectoryId: sourceDir.id)
        _ = try await createTestVideo(fileId: "whitespace-video", filename: "whitespace.mp4", sourceDirectoryId: sourceDir.id)
        try await createAnnotation(fileId: "text-video", frameTime: 1, text: "blue corner note")
        try await createAnnotation(fileId: "pencil-video", frameTime: 1, text: nil)
        try await createAnnotation(fileId: "whitespace-video", frameTime: 1, text: "   ")

        try await catalogProvider.refreshVideos()

        let hasTextResponse = try await app.sendRequest(.GET, "/api/v1/videos?hasTextAnnotations=true")
        XCTAssertEqual(hasTextResponse.status, .ok)
        let hasTextResult = try hasTextResponse.content.decode(PaginatedVideosResponse.self)
        XCTAssertEqual(hasTextResult.videos.map(\.fileId), ["text-video"])

        let noTextResponse = try await app.sendRequest(.GET, "/api/v1/videos?hasTextAnnotations=false")
        XCTAssertEqual(noTextResponse.status, .ok)
        let noTextResult = try noTextResponse.content.decode(PaginatedVideosResponse.self)
        XCTAssertEqual(Set(noTextResult.videos.map(\.fileId)), ["pencil-video", "whitespace-video"])

        let searchResponse = try await app.sendRequest(.GET, "/api/v1/videos?annotationTextSearch=corner")
        XCTAssertEqual(searchResponse.status, .ok)
        let searchResult = try searchResponse.content.decode(PaginatedVideosResponse.self)
        XCTAssertEqual(searchResult.videos.map(\.fileId), ["text-video"])
    }

    func testCriteriaJSONForTextAnnotationsIsIntersectedWithFlatParams() async throws {
        let sourceDir = createTestSourceDirectory()
        catalogProvider.sourceDirectories = [sourceDir]

        _ = try await createTestVideo(fileId: "text-video", filename: "text.mp4", sourceDirectoryId: sourceDir.id)
        _ = try await createTestVideo(fileId: "plain-video", filename: "plain.mp4", sourceDirectoryId: sourceDir.id)
        try await createAnnotation(fileId: "text-video", frameTime: 1, text: "priority marker")

        try await catalogProvider.refreshVideos()

        let criteria = SmartListCriteria(conditions: [
            FilterCondition(id: UUID(), criteriaType: .hasTextAnnotations(value: true), logicOperator: .and)
        ])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let criteriaJSON = String(data: try encoder.encode(criteria), encoding: .utf8)!
        // Contradictory flat param: the intersection is empty
        let conflictingPath = videosPath(queryItems: [
            URLQueryItem(name: "criteria", value: criteriaJSON),
            URLQueryItem(name: "hasTextAnnotations", value: "false"),
        ])
        let conflicting = try await app.sendRequest(.GET, conflictingPath)
        XCTAssertEqual(conflicting.status, .ok)
        XCTAssertEqual(try conflicting.content.decode(PaginatedVideosResponse.self).videos.count, 0)

        // Compatible flat param narrows nothing further
        let path = videosPath(queryItems: [
            URLQueryItem(name: "criteria", value: criteriaJSON),
            URLQueryItem(name: "search", value: "text"),
        ])

        let response = try await app.sendRequest(.GET, path)
        XCTAssertEqual(response.status, .ok)
        let result = try response.content.decode(PaginatedVideosResponse.self)
        XCTAssertEqual(result.videos.map(\.fileId), ["text-video"])
    }

    func testHasTimeRangesFlatAndCriteriaFilters() async throws {
        let sourceDir = createTestSourceDirectory()
        catalogProvider.sourceDirectories = [sourceDir]

        _ = try await createTestVideo(fileId: "segment-video", filename: "segment.mp4", sourceDirectoryId: sourceDir.id)
        _ = try await createTestVideo(fileId: "plain-video", filename: "plain.mp4", sourceDirectoryId: sourceDir.id)
        _ = try await createTestVideo(fileId: "invalid-segment-video", filename: "invalid.mp4", sourceDirectoryId: sourceDir.id)
        try await createTimeRange(fileId: "segment-video", startTime: 10, endTime: 20)
        try await createTimeRange(fileId: "invalid-segment-video", startTime: 90, endTime: 80)

        try await catalogProvider.refreshVideos()

        let flatResponse = try await app.sendRequest(.GET, "/api/v1/videos?hasTimeRanges=true")
        XCTAssertEqual(flatResponse.status, .ok)
        let flatResult = try flatResponse.content.decode(PaginatedVideosResponse.self)
        XCTAssertEqual(flatResult.videos.map(\.fileId), ["segment-video"])

        let aliasResponse = try await app.sendRequest(.GET, "/api/v1/videos?hasSegments=false")
        XCTAssertEqual(aliasResponse.status, .ok)
        let aliasResult = try aliasResponse.content.decode(PaginatedVideosResponse.self)
        XCTAssertEqual(Set(aliasResult.videos.map(\.fileId)), ["invalid-segment-video", "plain-video"])

        let criteria = SmartListCriteria(conditions: [
            FilterCondition(id: UUID(), criteriaType: .hasTimeRanges(value: true), logicOperator: .and)
        ])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let criteriaJSON = String(data: try encoder.encode(criteria), encoding: .utf8)!
        let criteriaPath = videosPath(queryItems: [URLQueryItem(name: "criteria", value: criteriaJSON)])

        let criteriaResponse = try await app.sendRequest(.GET, criteriaPath)
        XCTAssertEqual(criteriaResponse.status, .ok)
        let criteriaResult = try criteriaResponse.content.decode(PaginatedVideosResponse.self)
        XCTAssertEqual(criteriaResult.videos.map(\.fileId), ["segment-video"])
    }

    // MARK: - Test 6: Pagination support

    func testPaginationSupport() async throws {
        let sourceDir = createTestSourceDirectory()
        catalogProvider.sourceDirectories = [sourceDir]

        // Create 10 videos
        for i in 1...10 {
            _ = try await createTestVideo(
                fileId: "file\(i)",
                filename: "video\(String(format: "%02d", i)).mp4",
                sourceDirectoryId: sourceDir.id
            )
        }

        try await catalogProvider.refreshVideos()

        // Test limit
        let response1 = try await app.sendRequest(.GET, "/api/v1/videos?limit=3")
        XCTAssertEqual(response1.status, .ok)
        let result1 = try response1.content.decode(PaginatedVideosResponse.self)
        XCTAssertEqual(result1.videos.count, 3)
        XCTAssertEqual(result1.total, 10)

        // Test offset
        let response2 = try await app.sendRequest(.GET, "/api/v1/videos?limit=3&offset=3")
        XCTAssertEqual(response2.status, .ok)
        let result2 = try response2.content.decode(PaginatedVideosResponse.self)
        XCTAssertEqual(result2.videos.count, 3)
        XCTAssertEqual(result2.total, 10)

        // Verify different pages have different videos
        let firstPageFileIds = Set(result1.videos.map { $0.fileId })
        let secondPageFileIds = Set(result2.videos.map { $0.fileId })
        XCTAssertTrue(firstPageFileIds.isDisjoint(with: secondPageFileIds))
    }
}

// MARK: - Test Video Catalog Provider

final class TestVideoCatalogProvider: VideoCatalogProvider, @unchecked Sendable {
    private let databaseManager: DatabaseManager
    private let lock = NSLock()
    private var _videos: [VideoItem] = []
    var sourceDirectories: [SourceDirectory] = []

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func refreshVideos() async throws {
        let records = try await databaseManager.read { db in
            try VideoFileRecord.fetchAll(db)
        }

        let items = records.map { record in
            VideoItem(
                id: record.id,
                fileId: record.fileId,
                filename: record.filename,
                relativePath: record.path,
                sourceDirectoryId: record.sourceDirectoryId,
                duration: record.duration,
                width: record.width,
                height: record.height,
                codec: record.codec,
                fileSize: record.fileSize,
                lastModified: Date(timeIntervalSince1970: record.lastModified),
                rating: record.rating
            )
        }

        lock.withLock {
            _videos = items
        }
    }

    func getVideos() -> [VideoItem] {
        lock.lock()
        defer { lock.unlock() }
        return _videos
    }

    func getSourceDirectories() -> [SourceDirectory] {
        sourceDirectories
    }

    func getVideoByFileId(_ fileId: String) -> VideoItem? {
        lock.lock()
        defer { lock.unlock() }
        return _videos.first { $0.fileId == fileId }
    }
}

// MARK: - Vapor Test Helpers

extension Application {
    func sendRequest(
        _ method: HTTPMethod,
        _ path: String,
        headers: HTTPHeaders = [:],
        body: ByteBuffer? = nil
    ) async throws -> Response {
        let request = Request(
            application: self,
            method: method,
            url: URI(string: path),
            headers: headers,
            collectedBody: body,
            on: self.eventLoopGroup.next()
        )
        return try await self.responder.respond(to: request).get()
    }
}

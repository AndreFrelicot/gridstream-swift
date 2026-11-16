import GridStreamAPI
import XCTest
import Vapor
import GRDB
@testable import gridstream_macos

/// Walks every catalog write endpoint and checks that each successful call
/// moves the catalog version, so clients polling `/catalog/status` see it.
///
/// Not covered here: `PUT /videos/:id/thumbnail` and `POST /videos/:id/captures`
/// need a decodable video file on disk; their bump goes through the same
/// `writeCatalog` helper as every other route.
final class CatalogVersionBumpTests: XCTestCase {

    private var testDirectory: URL!
    private var databaseManager: DatabaseManager!
    private var app: Application!

    private let fileId = "bump-video"
    private let sourceDirectoryId = UUID()
    private let ratedTag = TagRecord(name: "rated", color: TagColorPalette.red, ratingEnabled: true)
    private let plainTag = TagRecord(name: "plain", color: TagColorPalette.blue)

    private struct Identified: Decodable { let id: UUID }

    override func setUp() async throws {
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GridStreamCatalogVersionBumpTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        databaseManager = DatabaseManager(databasePath: testDirectory.appendingPathComponent("test.sqlite"))
        try await databaseManager.initialize()

        var env = try Environment.detect()
        env.arguments = ["vapor", "test"]
        app = try await Application.make(env)
        app.middleware.use(ErrorMiddleware.default(environment: app.environment))

        let database = databaseManager!
        try app.register(collection: TagRoutes(databaseManager: database))
        try app.register(collection: VideoTagRoutes(databaseManager: database))
        try app.register(collection: RatingRoutes(databaseManager: database))
        try app.register(collection: PlaybackStatsRoutes(databaseManager: database))
        try app.register(collection: SmartListRoutes(databaseManager: database))
        try app.register(collection: SimpleListRoutes(databaseManager: database))
        try app.register(collection: TimeRangeRoutes(databaseManager: database))
        try app.register(collection: AnnotationRoutes(databaseManager: database))
        try app.register(collection: FrameCaptureRoutes(databaseManager: database))

        let video = VideoFileRecord(
            fileId: fileId,
            path: "/test/\(fileId).mp4",
            sourceDirectoryId: sourceDirectoryId,
            filename: "\(fileId).mp4",
            fileSize: 1000,
            duration: 120,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: 1_000
        )
        let ratedTag = ratedTag
        let plainTag = plainTag
        try await databaseManager.write { db in
            try video.insert(db)
            try ratedTag.insert(db)
            try plainTag.insert(db)
            try VideoTagRecord(videoFileId: video.fileId, tagId: ratedTag.id).insert(db)
        }
    }

    override func tearDown() async throws {
        try await databaseManager.close()
        try await app.asyncShutdown()
        try? FileManager.default.removeItem(at: testDirectory)
        databaseManager = nil
        app = nil
        testDirectory = nil
    }

    // MARK: - Helpers

    @discardableResult
    private func send(
        _ method: HTTPMethod,
        _ path: String,
        json: String? = nil,
        expectBump: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> Response {
        try await databaseManager.updateCatalogVersion(1)

        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        let body = json.map { ByteBuffer(string: $0) }
        let response = try await app.sendRequest(method, path, headers: headers, body: body)

        XCTAssertLessThan(
            response.status.code, 300,
            "\(method) \(path) failed: \(response.body.string ?? "")", file: file, line: line
        )
        let version = try await databaseManager.fetchCatalogVersion()
        if expectBump {
            XCTAssertNotEqual(version, 1, "\(method) \(path) did not bump the catalog version", file: file, line: line)
        } else {
            XCTAssertEqual(version, 1, "\(method) \(path) bumped the catalog version without a change", file: file, line: line)
        }
        return response
    }

    private func createdId(_ response: Response) throws -> UUID {
        try response.content.decode(Identified.self).id
    }

    // MARK: - writeCatalog

    func testWriteCatalogBumpsOnlyWhenTheBlockReportsAChange() async throws {
        try await databaseManager.updateCatalogVersion(1)
        let value = try await databaseManager.writeCatalog { _ in CatalogWrite.unchanged(7) }
        XCTAssertEqual(value, 7)
        let unchangedVersion = try await databaseManager.fetchCatalogVersion()
        XCTAssertEqual(unchangedVersion, 1)

        try await databaseManager.writeCatalog { _ in .changed }
        let changedVersion = try await databaseManager.fetchCatalogVersion()
        XCTAssertNotEqual(changedVersion, 1)
    }

    func testWriteCatalogDoesNotBumpWhenTheBlockThrows() async throws {
        try await databaseManager.updateCatalogVersion(1)
        struct Failure: Error {}

        do {
            try await databaseManager.writeCatalog { _ -> CatalogWrite<Void> in throw Failure() }
            XCTFail("Expected the write to throw")
        } catch is Failure {}

        let version = try await databaseManager.fetchCatalogVersion()
        XCTAssertEqual(version, 1)
    }

    // MARK: - Tags

    func testTagWritesBumpTheVersion() async throws {
        let created = try await send(.POST, "/api/v1/tags", json: #"{"name":"new","color":"\#(TagColorPalette.green)"}"#, expectBump: true)
        let tagId = try createdId(created)

        try await send(.PUT, "/api/v1/tags/\(tagId)", json: #"{"name":"renamed"}"#, expectBump: true)
        try await send(.DELETE, "/api/v1/tags/\(tagId)", expectBump: true)
    }

    // MARK: - Video tags

    func testVideoTagWritesBumpTheVersion() async throws {
        let base = "/api/v1/videos/\(fileId)/tags"

        try await send(.POST, "\(base)/\(plainTag.id)", expectBump: true)
        try await send(.DELETE, "\(base)/\(plainTag.id)", expectBump: true)
        try await send(.POST, base, json: #"{"tagIds":["\#(plainTag.id)"]}"#, expectBump: true)
        try await send(
            .POST, "/api/v1/tags/apply",
            json: #"{"fileIds":["\#(fileId)"],"removeTagIds":["\#(plainTag.id)"]}"#,
            expectBump: true
        )
        try await send(
            .POST, "/api/v1/source-directories/\(sourceDirectoryId)/tags",
            json: #"{"tagIds":["\#(plainTag.id)"]}"#,
            expectBump: true
        )
    }

    // MARK: - Ratings

    func testRatingWritesBumpTheVersion() async throws {
        try await send(.PUT, "/api/v1/videos/\(fileId)/rating", json: #"{"rating":6}"#, expectBump: true)
        try await send(.PUT, "/api/v1/videos/\(fileId)/tags/\(ratedTag.id)/rating", json: #"{"rating":4}"#, expectBump: true)
        try await send(
            .POST, "/api/v1/source-directories/\(sourceDirectoryId)/ratings",
            json: #"{"rating":8}"#,
            expectBump: true
        )
        try await send(
            .POST, "/api/v1/source-directories/\(sourceDirectoryId)/tag-ratings",
            json: #"{"tagId":"\#(ratedTag.id)","rating":2}"#,
            expectBump: true
        )
    }

    // MARK: - Playback stats

    func testPlaybackStatsBumpOnlyWhenTheyChange() async throws {
        let path = "/api/v1/videos/\(fileId)/playback-stats"

        try await send(.POST, path, json: #"{"incrementPlayCount":true,"addViewTime":0}"#, expectBump: true)
        try await send(.POST, path, json: #"{"incrementPlayCount":false,"addViewTime":30}"#, expectBump: true)
        try await send(.POST, path, json: #"{"incrementPlayCount":false,"addViewTime":0}"#, expectBump: false)
    }

    // MARK: - Smart lists

    func testSmartListWritesBumpTheVersion() async throws {
        let criteria = #"{"conditions":[{"id":"\#(UUID())","criteriaType":{"type":"ratingMin","value":5},"logicOperator":"AND"}]}"#
        let body = try JSONEncoder().encode(CreateSmartListRequest(name: "smart", criteria: criteria))
        let created = try await send(.POST, "/api/v1/smart-lists", json: String(decoding: body, as: UTF8.self), expectBump: true)
        let listId = try createdId(created)

        try await send(.PUT, "/api/v1/smart-lists/\(listId)", json: #"{"name":"smarter"}"#, expectBump: true)
        try await send(.DELETE, "/api/v1/smart-lists/\(listId)", expectBump: true)
    }

    // MARK: - Simple lists

    func testSimpleListWritesBumpTheVersion() async throws {
        let created = try await send(.POST, "/api/v1/simple-lists", json: #"{"name":"simple"}"#, expectBump: true)
        let listId = try createdId(created)
        let path = "/api/v1/simple-lists/\(listId)"

        try await send(.PUT, path, json: #"{"name":"simpler"}"#, expectBump: true)
        try await send(.POST, "\(path)/videos", json: #"{"videoIds":["\#(fileId)"]}"#, expectBump: true)
        try await send(.DELETE, "\(path)/videos/\(fileId)", expectBump: true)
        try await send(.DELETE, path, expectBump: true)
    }

    // MARK: - Time ranges

    func testTimeRangeWritesBumpTheVersion() async throws {
        let base = "/api/v1/videos/\(fileId)/time-ranges"
        let created = try await send(.POST, base, json: #"{"startTime":1,"endTime":5}"#, expectBump: true)
        let rangeId = try createdId(created)

        try await send(.PUT, "\(base)/\(rangeId)", json: #"{"startTime":2,"endTime":6,"label":"x"}"#, expectBump: true)
        try await send(.DELETE, "\(base)/\(rangeId)", expectBump: true)
    }

    // MARK: - Annotations

    func testAnnotationWritesBumpTheVersion() async throws {
        let base = "/api/v1/videos/\(fileId)/annotations"
        let created = try await send(
            .PUT, base,
            json: #"{"frameTime":1,"frameRate":24,"strokesJSON":"[]","text":"note"}"#,
            expectBump: true
        )
        let annotationId = try createdId(created)

        try await send(.DELETE, "\(base)/\(annotationId)", expectBump: true)
    }

    // MARK: - Captures

    func testCaptureDeleteBumpsTheVersion() async throws {
        let capture = FrameCaptureRecord(
            fileId: fileId, timestamp: 1, imageData: Data([0xFF]), width: 1, height: 1, fileSize: 1
        )
        try await databaseManager.write { db in try capture.insert(db) }

        try await send(.DELETE, "/api/v1/captures/\(capture.id)", expectBump: true)
    }
}

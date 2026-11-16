import GridStreamAPI
import XCTest
import Vapor
import GRDB
@testable import gridstream_macos

/// Checks real route output against the shared JSON fixtures in
/// `contracts/fixtures/`: every response must have the same keys, nesting and
/// value kinds as its fixture. The data is seeded so optional keys are present.
final class ContractFixtureRouteTests: XCTestCase {

    var testDir: URL!
    var databaseManager: DatabaseManager!
    var app: Application!
    var catalogProvider: TestVideoCatalogProvider!

    private let sourceDirectory = SourceDirectory(path: "/Volumes/Media/Footage")
    private let playedFileId = "a1b2c3d4e5f60718"
    private let unplayedFileId = "0f1e2d3c4b5a6978"

    override func setUp() async throws {
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GridStreamContractFixtureRouteTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        databaseManager = DatabaseManager(databasePath: testDir.appendingPathComponent("test.sqlite"))
        try await databaseManager.initialize()

        var env = try Environment.detect()
        env.arguments = ["vapor", "test"]
        app = try await Application.make(env)
        app.middleware.use(ErrorMiddleware.default(environment: app.environment))

        catalogProvider = TestVideoCatalogProvider(databaseManager: databaseManager)
        catalogProvider.sourceDirectories = [sourceDirectory]
        app.storage[VideoCatalogStorageKey.self] = catalogProvider

        try app.register(collection: VideoRoutes(databaseManager: databaseManager))
        try app.register(collection: TagRoutes(databaseManager: databaseManager))
        try app.register(collection: VideoTagRoutes(databaseManager: databaseManager))
        try app.register(collection: RatingRoutes(databaseManager: databaseManager))
        try app.register(collection: PlaybackStatsRoutes(databaseManager: databaseManager))
        try app.register(collection: CatalogRoutes(databaseManager: databaseManager))
        try app.register(collection: SmartListRoutes(databaseManager: databaseManager))
        try app.register(collection: SimpleListRoutes(databaseManager: databaseManager))
        try app.register(collection: TimeRangeRoutes(databaseManager: databaseManager))
        try app.register(collection: AnnotationRoutes(databaseManager: databaseManager))
        try app.register(collection: FrameCaptureRoutes(databaseManager: databaseManager))
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

    // MARK: - Fixtures

    private static var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // gridstream-macosTests
            .deletingLastPathComponent() // gridstream-macos
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("contracts/fixtures")
    }

    private func fixture(_ name: String) throws -> Any {
        let data = try Data(contentsOf: Self.fixturesDirectory.appendingPathComponent("\(name).json"))
        return try JSONSerialization.jsonObject(with: data)
    }

    /// A request fixture as a mutable object, so ids can point at seeded rows.
    private func requestFixture(_ name: String) throws -> [String: Any] {
        try XCTUnwrap(try fixture(name) as? [String: Any], name)
    }

    // MARK: - Shapes

    /// Keys, nesting and value kinds of a JSON value. Arrays take the shape of
    /// their first element; objects under `mapKeys` have dynamic keys and take
    /// the shape of their first value.
    private static func shape(_ value: Any, key: String? = nil, mapKeys: Set<String>) -> String {
        switch value {
        case let object as [String: Any]:
            if let key, mapKeys.contains(key) {
                return "{*: " + (object.values.first.map { shape($0, mapKeys: mapKeys) } ?? "?") + "}"
            }
            let members = object.keys.sorted().map { "\($0): " + shape(object[$0]!, key: $0, mapKeys: mapKeys) }
            return "{" + members.joined(separator: ", ") + "}"
        case let array as [Any]:
            return "[" + (array.first.map { shape($0, mapKeys: mapKeys) } ?? "") + "]"
        case is NSNull:
            return "null"
        case is String:
            return "string"
        case let number as NSNumber:
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? "bool" : "number"
        default:
            return "unknown"
        }
    }

    private func assertMatchesFixture(
        _ response: Response,
        _ name: String,
        status: HTTPResponseStatus = .ok,
        mapKeys: Set<String> = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(response.status, status, "\(name): \(response.body.string ?? "")", file: file, line: line)
        let body = try JSONSerialization.jsonObject(with: response.body.data ?? Data())
        XCTAssertEqual(
            Self.shape(body, mapKeys: mapKeys),
            Self.shape(try fixture(name), mapKeys: mapKeys),
            "route output does not match contracts/fixtures/\(name).json",
            file: file,
            line: line
        )
    }

    // MARK: - Requests

    private var jsonHeaders: HTTPHeaders { ["Content-Type": "application/json"] }

    private func send(_ method: HTTPMethod, _ path: String, json: Any? = nil) async throws -> Response {
        let body = try json.map { ByteBuffer(bytes: Array(try JSONSerialization.data(withJSONObject: $0))) }
        return try await app.sendRequest(method, "/api/v1/\(path)", headers: json == nil ? [:] : jsonHeaders, body: body)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ response: Response) throws -> T {
        try JSONDecoder.gridStream().decode(type, from: response.body.data ?? Data())
    }

    // MARK: - Seed

    private func insertVideo(_ fileId: String, filename: String, played: Bool) async throws {
        let video = VideoFileRecord(
            fileId: fileId,
            path: "\(sourceDirectory.path)/Sessions/\(filename)",
            sourceDirectoryId: sourceDirectory.id,
            filename: filename,
            fileSize: 734_003_200,
            duration: 312.48,
            width: 1920,
            height: 1080,
            codec: "hvc1",
            lastModified: Date().timeIntervalSince1970,
            rating: 8,
            playCount: played ? 5 : 0,
            totalViewTime: played ? 1260 : 0,
            lastPlayedAt: played ? Date().timeIntervalSince1970 : nil
        )
        try await databaseManager.write { db in
            try video.insert(db)
        }
    }

    // MARK: - Test

    func testRouteOutputMatchesContractFixtures() async throws {
        try await insertVideo(playedFileId, filename: "Rehearsal Take 3.mp4", played: true)
        try await insertVideo(unplayedFileId, filename: "Rehearsal Take 4.mp4", played: false)
        try await catalogProvider.refreshVideos()

        // Tags
        let createdTag = try await send(.POST, "tags", json: try requestFixture("tag-create-request"))
        try assertMatchesFixture(createdTag, "tag", status: .created)
        let tag = try decode(TagDTO.self, createdTag)

        var tagUpdate = try requestFixture("tag-update-request")
        tagUpdate["name"] = "Keeper 2"
        tagUpdate["ratingEnabled"] = true
        try assertMatchesFixture(try await send(.PUT, "tags/\(tag.id.uuidString)", json: tagUpdate), "tag")

        // `/videos/:id/tags` lists tags without the per-video rating (the video item carries it).
        try assertMatchesFixture(
            try await send(.POST, "videos/\(playedFileId)/tags/\(tag.id.uuidString)"), "video-tags"
        )
        try assertMatchesFixture(
            try await send(.PUT, "videos/\(playedFileId)/tags/\(tag.id.uuidString)/rating", json: ["rating": 9]),
            "rating"
        )
        try assertMatchesFixture(try await send(.GET, "videos/\(playedFileId)/tags"), "video-tags")
        try assertMatchesFixture(try await send(.GET, "tags"), "tags")

        var bulkApply = try requestFixture("tags-apply-request")
        bulkApply["fileIds"] = [unplayedFileId]
        bulkApply["addTagIds"] = [tag.id.uuidString.lowercased()]
        bulkApply["removeTagIds"] = [String]()
        try assertMatchesFixture(try await send(.POST, "tags/apply", json: bulkApply), "tags-apply-response")

        // Ratings and playback stats
        try assertMatchesFixture(
            try await send(.PUT, "videos/\(playedFileId)/rating", json: try requestFixture("rating-request")), "rating"
        )
        try assertMatchesFixture(
            try await send(.POST, "videos/\(playedFileId)/playback-stats",
                           json: try requestFixture("playback-stats-request")),
            "playback-stats"
        )

        // Time ranges
        try assertMatchesFixture(
            try await send(.POST, "videos/\(playedFileId)/time-ranges",
                           json: try requestFixture("time-range-create-request")),
            "time-range",
            status: .created
        )
        try assertMatchesFixture(try await send(.GET, "videos/\(playedFileId)/time-ranges"), "time-ranges")

        // Annotations (with text, so the optional key is present)
        var upsert = try requestFixture("annotation-upsert-request")
        upsert["text"] = "Watch the left hand"
        try assertMatchesFixture(try await send(.PUT, "videos/\(playedFileId)/annotations", json: upsert), "annotation")
        try assertMatchesFixture(try await send(.GET, "videos/\(playedFileId)/annotations"), "annotations")
        try assertMatchesFixture(try await send(.GET, "videos/\(playedFileId)/annotations/times"), "annotation-times")

        // Captures (seeded directly: creating one needs a real video file)
        let capture = FrameCaptureRecord(
            fileId: playedFileId, timestamp: 95.2, imageData: Data([0xFF]), width: 1920, height: 1080, fileSize: 1
        )
        try await databaseManager.write { db in
            try capture.insert(db)
        }
        try assertMatchesFixture(try await send(.GET, "videos/\(playedFileId)/captures"), "captures")
        try assertMatchesFixture(try await send(.GET, "captures"), "captures")

        // Videos and source directories
        try await catalogProvider.refreshVideos()
        try assertMatchesFixture(try await send(.GET, "videos/by-file-id/\(playedFileId)"), "video")
        try assertMatchesFixture(try await send(.GET, "videos?search=Take%203"), "videos-page")
        try assertMatchesFixture(try await send(.GET, "source-directories"), "source-directories")
        try assertMatchesFixture(try await send(.GET, "catalog/status"), "catalog-status")

        // Smart lists
        let createdSmartList = try await send(.POST, "smart-lists", json: try requestFixture("smart-list-create-request"))
        try assertMatchesFixture(createdSmartList, "smart-list", status: .created)
        let smartList = try decode(SmartListDTO.self, createdSmartList)
        try assertMatchesFixture(
            try await send(.PUT, "smart-lists/\(smartList.id.uuidString)",
                           json: try requestFixture("smart-list-update-request")),
            "smart-list"
        )
        try assertMatchesFixture(try await send(.GET, "smart-lists"), "smart-lists")
        try assertMatchesFixture(
            try await send(.GET, "smart-lists/memberships"), "smart-list-memberships", mapKeys: ["memberships"]
        )

        // Simple lists (a new list has no videos yet; its shape is checked once it has some)
        let createdSimpleList = try await send(.POST, "simple-lists", json: try requestFixture("simple-list-create-request"))
        XCTAssertEqual(createdSimpleList.status, .created)
        let simpleList = try decode(SimpleListDTO.self, createdSimpleList)
        try assertMatchesFixture(
            try await send(.POST, "simple-lists/\(simpleList.id.uuidString)/videos",
                           json: try requestFixture("simple-list-videos-request")),
            "simple-list"
        )
        try assertMatchesFixture(
            try await send(.PUT, "simple-lists/\(simpleList.id.uuidString)",
                           json: try requestFixture("simple-list-update-request")),
            "simple-list"
        )
        try assertMatchesFixture(try await send(.GET, "simple-lists"), "simple-lists")

        // Deletes
        try assertMatchesFixture(
            try await send(.DELETE, "smart-lists/\(smartList.id.uuidString)"), "smart-list-delete-response"
        )
        try assertMatchesFixture(try await send(.DELETE, "tags/\(tag.id.uuidString)"), "tag-delete-response")
    }
}

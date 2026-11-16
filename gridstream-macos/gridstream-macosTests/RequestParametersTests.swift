import XCTest
import Vapor
@testable import gridstream_macos

/// `Request` parameter helpers shared by the route collections.
final class RequestParametersTests: XCTestCase {
    private var app: Application!

    private struct ErrorBody: Decodable {
        let error: Bool
        let reason: String
    }

    override func setUp() async throws {
        var env = try Environment.detect()
        env.arguments = ["vapor", "test"]
        app = try await Application.make(env)
        app.middleware.use(ErrorMiddleware.default(environment: app.environment))

        app.get("videos", ":id") { req in try req.requireFileId() }
        app.get("tags", ":tagId") { req in try req.requireUUID("tagId", label: "tag").uuidString }
        app.get("captures", ":captureId") { req in
            try req.requireParameter("captureId", reason: "Missing capture ID")
        }
        app.get("missing") { req in try req.requireParameter("absent", reason: "Missing thing") }
        app.get("page") { req -> String in
            let page = try req.pagination(defaultLimit: 50)
            return "\(page.limit),\(page.offset)"
        }
        app.get("catalog") { req -> String in
            _ = try req.catalogProvider()
            return "ok"
        }
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
    }

    private func get(_ path: String) async throws -> Response {
        try await app.sendRequest(.GET, path)
    }

    private func assertBadRequest(_ path: String, reason: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        let response = try await get(path)
        XCTAssertEqual(response.status, .badRequest, file: file, line: line)
        XCTAssertEqual(try response.content.decode(ErrorBody.self).reason, reason, file: file, line: line)
    }

    func testRequireFileIdReturnsThePathSegment() async throws {
        let response = try await get("/videos/abc123")
        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(response.body.string, "abc123")
    }

    func testRequireUUIDParsesOrRejectsWithTheLabel() async throws {
        let id = UUID()
        let response = try await get("/tags/\(id.uuidString)")
        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(response.body.string, id.uuidString)

        try await assertBadRequest("/tags/not-a-uuid", reason: "Invalid tag ID format")
    }

    func testRequireParameterRejectsAMissingParameter() async throws {
        let response = try await get("/captures/cap-1")
        XCTAssertEqual(response.body.string, "cap-1")

        try await assertBadRequest("/missing", reason: "Missing thing")
    }

    func testPaginationClampsLimitAndRejectsNegativeOffset() async throws {
        for (query, expected) in [("", "50,0"), ("?limit=0&offset=5", "1,5"), ("?limit=99999", "10000,0"), ("?limit=-3", "1,0")] {
            let body = try await get("/page\(query)").body.string
            XCTAssertEqual(body, expected, query)
        }

        try await assertBadRequest("/page?offset=-1", reason: "offset must not be negative")
    }

    func testCatalogProviderIsRequired() async throws {
        let response = try await get("/catalog")
        XCTAssertEqual(response.status, .internalServerError)
    }
}

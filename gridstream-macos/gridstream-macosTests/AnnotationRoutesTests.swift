import GridStreamAPI
import XCTest
import Vapor
import NIOFoundationCompat
import GRDB
@testable import gridstream_macos

final class AnnotationRoutesTests: XCTestCase {

    var testDatabaseURL: URL!
    var databaseManager: DatabaseManager!
    var app: Application!
    var authDefaults: UserDefaults!
    var authDefaultsSuiteName: String!

    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GridStreamAnnotationRoutesTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        testDatabaseURL = testDir.appendingPathComponent("test_gridstream.sqlite")
        databaseManager = DatabaseManager(databasePath: testDatabaseURL)
        try await databaseManager.initialize()

        var env = try Environment.detect()
        env.arguments = ["vapor", "test"]
        app = try await Application.make(env)
        app.middleware.use(ErrorMiddleware.default(environment: app.environment))
        authDefaultsSuiteName = "AnnotationRoutesTests-\(UUID().uuidString)"
        authDefaults = UserDefaults(suiteName: authDefaultsSuiteName)
        let authStore = ServerAuthConfigurationStore(defaults: authDefaults, secrets: InMemorySecretStore())
        authStore.save(
            ServerAuthConfiguration(
                isEnabled: true,
                pinHash: try ServerPINSecurity.hash(pin: "123456"),
                pinRevision: 1,
                sessionTTLDays: 30,
                tokenSecret: "annotation-test-secret"
            )
        )
        app.serverAuthManager = ServerAuthManager(store: authStore)
        try app.register(collection: AuthRoutes())

        let authenticated = app.grouped(SessionAuthMiddleware())
        try authenticated.register(collection: AnnotationRoutes(databaseManager: databaseManager))
    }

    override func tearDown() async throws {
        try await databaseManager.close()
        try await app.asyncShutdown()
        let testDir = testDatabaseURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: testDir)
        if let authDefaults {
            authDefaults.removePersistentDomain(forName: authDefaultsSuiteName)
        }
        databaseManager = nil
        testDatabaseURL = nil
        app = nil
        authDefaults = nil
        authDefaultsSuiteName = nil
    }

    private func authHeader() async throws -> HTTPHeaders {
        let body = ByteBuffer(data: #"{"pin":"123456"}"#.data(using: .utf8)!)
        var loginHeaders = HTTPHeaders()
        loginHeaders.add(name: .contentType, value: "application/json")

        let response = try await app.sendRequest(
            .POST,
            "/api/v1/auth/login",
            headers: loginHeaders,
            body: body
        )
        XCTAssertEqual(response.status, .ok)

        let session = try response.content.decode(AuthSessionResponse.self)
        var headers = HTTPHeaders()
        headers.add(name: .authorization, value: "Bearer \(session.token ?? "")")
        headers.add(name: .contentType, value: "application/json")
        return headers
    }

    private func createTestVideo(fileId: String) async throws {
        let video = VideoFileRecord(
            fileId: fileId,
            path: "/test/path/\(fileId).mp4",
            sourceDirectoryId: UUID(),
            filename: "\(fileId).mp4",
            fileSize: 1000,
            duration: 120,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: Date().timeIntervalSince1970
        )

        try await databaseManager.write { db in
            try video.insert(db)
        }
    }

    private func upsertBody(
        frameTime: Double,
        frameRate: Double = 24,
        strokesJSON: String = "[]",
        text: String? = nil
    ) throws -> ByteBuffer {
        let payload = UpsertAnnotationRequest(
            frameTime: frameTime,
            frameRate: frameRate,
            strokesJSON: strokesJSON,
            text: text
        )
        let data = try JSONEncoder().encode(payload)
        return ByteBuffer(data: data)
    }

    func testUpsertCreatesPersistedAnnotationWithText() async throws {
        let fileId = "annotated-video"
        try await createTestVideo(fileId: fileId)

        let response = try await app.sendRequest(
            .PUT,
            "/api/v1/videos/\(fileId)/annotations",
            headers: try await authHeader(),
            body: try upsertBody(frameTime: 1.25, strokesJSON: "[{\"width\":1}]", text: "Corner note")
        )

        XCTAssertEqual(response.status, .ok)

        let saved = try response.content.decode(AnnotationDTO.self)
        XCTAssertEqual(saved.text, "Corner note")
        XCTAssertEqual(saved.strokesJSON, "[{\"width\":1}]")

        let stored = try await databaseManager.read { db in
            try AnnotationRecord.findByVideoFileIdAndFrameTime(fileId, frameTime: 1.25, in: db)
        }
        XCTAssertEqual(stored?.text, "Corner note")
        XCTAssertEqual(stored?.strokesJSON, "[{\"width\":1}]")
    }

    func testUpsertUpdatesTextWithoutLosingStrokes() async throws {
        let fileId = "text-update-video"
        try await createTestVideo(fileId: fileId)

        _ = try await app.sendRequest(
            .PUT,
            "/api/v1/videos/\(fileId)/annotations",
            headers: try await authHeader(),
            body: try upsertBody(frameTime: 2.0, strokesJSON: "[{\"color\":\"#FF0000\"}]", text: nil)
        )

        let updateResponse = try await app.sendRequest(
            .PUT,
            "/api/v1/videos/\(fileId)/annotations",
            headers: try await authHeader(),
            body: try upsertBody(frameTime: 2.0, strokesJSON: "[{\"color\":\"#FF0000\"}]", text: "Updated text")
        )

        XCTAssertEqual(updateResponse.status, .ok)
        let updated = try updateResponse.content.decode(AnnotationDTO.self)
        XCTAssertEqual(updated.text, "Updated text")
        XCTAssertEqual(updated.strokesJSON, "[{\"color\":\"#FF0000\"}]")
    }

    func testUpsertUpdatesStrokesWithoutLosingText() async throws {
        let fileId = "stroke-update-video"
        try await createTestVideo(fileId: fileId)

        _ = try await app.sendRequest(
            .PUT,
            "/api/v1/videos/\(fileId)/annotations",
            headers: try await authHeader(),
            body: try upsertBody(frameTime: 3.0, strokesJSON: "[{\"color\":\"#00FF00\"}]", text: "Persistent text")
        )

        let updateResponse = try await app.sendRequest(
            .PUT,
            "/api/v1/videos/\(fileId)/annotations",
            headers: try await authHeader(),
            body: try upsertBody(frameTime: 3.0, strokesJSON: "[{\"color\":\"#0000FF\"}]", text: "Persistent text")
        )

        XCTAssertEqual(updateResponse.status, .ok)

        let stored = try await databaseManager.read { db in
            try AnnotationRecord.findByVideoFileIdAndFrameTime(fileId, frameTime: 3.0, in: db)
        }
        XCTAssertEqual(stored?.text, "Persistent text")
        XCTAssertEqual(stored?.strokesJSON, "[{\"color\":\"#0000FF\"}]")
    }

    func testGetAnnotationsReturnsNullTextWhenAbsent() async throws {
        let fileId = "nil-text-video"
        try await createTestVideo(fileId: fileId)

        _ = try await app.sendRequest(
            .PUT,
            "/api/v1/videos/\(fileId)/annotations",
            headers: try await authHeader(),
            body: try upsertBody(frameTime: 4.0, strokesJSON: "[{\"color\":\"#FFFFFF\"}]")
        )

        let response = try await app.sendRequest(
            .GET,
            "/api/v1/videos/\(fileId)/annotations",
            headers: authHeader()
        )

        XCTAssertEqual(response.status, .ok)
        let list = try response.content.decode(AnnotationListResponse.self)
        XCTAssertEqual(list.annotations.count, 1)
        XCTAssertNil(list.annotations[0].text)
    }

    func testAnnotationTextFTSSyncsThroughCreateUpdateClearAndDelete() async throws {
        let fileId = "fts-sync-video"
        try await createTestVideo(fileId: fileId)
        let headers = try await authHeader()

        let createResponse = try await app.sendRequest(
            .PUT,
            "/api/v1/videos/\(fileId)/annotations",
            headers: headers,
            body: try upsertBody(frameTime: 1.0, text: "blue corner note")
        )
        XCTAssertEqual(createResponse.status, .ok)
        let created = try createResponse.content.decode(AnnotationDTO.self)

        var searchResult = try await CriteriaEvaluator().evaluateCondition(
            .annotationTextSearch(text: "blue"),
            db: databaseManager
        )
        XCTAssertEqual(searchResult, [fileId])

        let updateResponse = try await app.sendRequest(
            .PUT,
            "/api/v1/videos/\(fileId)/annotations",
            headers: headers,
            body: try upsertBody(frameTime: 1.0, text: "green edge note")
        )
        XCTAssertEqual(updateResponse.status, .ok)

        let oldTermResult = try await CriteriaEvaluator().evaluateCondition(
            .annotationTextSearch(text: "blue"),
            db: databaseManager
        )
        XCTAssertTrue(oldTermResult.isEmpty)

        searchResult = try await CriteriaEvaluator().evaluateCondition(
            .annotationTextSearch(text: "green"),
            db: databaseManager
        )
        XCTAssertEqual(searchResult, [fileId])

        let clearResponse = try await app.sendRequest(
            .PUT,
            "/api/v1/videos/\(fileId)/annotations",
            headers: headers,
            body: try upsertBody(frameTime: 1.0, text: "")
        )
        XCTAssertEqual(clearResponse.status, .ok)

        let hasTextResult = try await CriteriaEvaluator().evaluateCondition(
            .hasTextAnnotations(value: true),
            db: databaseManager
        )
        XCTAssertFalse(hasTextResult.contains(fileId))

        _ = try await app.sendRequest(
            .PUT,
            "/api/v1/videos/\(fileId)/annotations",
            headers: headers,
            body: try upsertBody(frameTime: 1.0, text: "delete marker")
        )

        let deleteResponse = try await app.sendRequest(
            .DELETE,
            "/api/v1/videos/\(fileId)/annotations/\(created.id.uuidString)",
            headers: headers
        )
        XCTAssertEqual(deleteResponse.status, .noContent)

        let deletedResult = try await CriteriaEvaluator().evaluateCondition(
            .annotationTextSearch(text: "delete"),
            db: databaseManager
        )
        XCTAssertFalse(deletedResult.contains(fileId))
    }

    func testAnnotationTextSearchMigrationBackfillsExistingTextAnnotations() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GridStreamAnnotationFTSMigrationTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        let databaseURL = testDir.appendingPathComponent("test_gridstream.sqlite")

        defer { try? FileManager.default.removeItem(at: testDir) }

        let pool = try DatabasePool(path: databaseURL.path)
        try pool.write { db in
            try V16_CreateAnnotationsTable.migrate(db)
            try V21_AddAnnotationText.migrate(db)
            try db.execute(
                sql: """
                    INSERT INTO video_annotations
                    (id, video_file_id, frame_time, frame_rate, strokes_json, text, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    UUID().uuidString,
                    "legacy-text-video",
                    1.0,
                    24.0,
                    "[]",
                    "historic marker text",
                    Date().timeIntervalSince1970,
                    Date().timeIntervalSince1970,
                ]
            )

            try V22_CreateAnnotationTextSearch.migrate(db)
        }

        let fileIds = try pool.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT video_file_id
                    FROM video_annotation_text_fts
                    WHERE video_annotation_text_fts MATCH ?
                    """,
                arguments: ["historic"]
            )
        }

        XCTAssertEqual(Set(fileIds), ["legacy-text-video"])
    }

    func testMigrationKeepsExistingAnnotationsCompatible() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GridStreamAnnotationMigrationTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        let databaseURL = testDir.appendingPathComponent("test_gridstream.sqlite")

        defer { try? FileManager.default.removeItem(at: testDir) }

        var migrator = DatabaseMigrator()
        migrator.registerMigration(V1_CreateVideoFilesTable.migrationIdentifier) { db in
            try V1_CreateVideoFilesTable.migrate(db)
        }
        migrator.registerMigration(V2_CreateTagsTable.migrationIdentifier) { db in
            try V2_CreateTagsTable.migrate(db)
        }
        migrator.registerMigration(V3_AddRatings.migrationIdentifier) { db in
            try V3_AddRatings.migrate(db)
        }
        migrator.registerMigration(V4_CreateThumbnailsTable.migrationIdentifier) { db in
            try V4_CreateThumbnailsTable.migrate(db)
        }
        migrator.registerMigration(V5_CreateAppMetadataTable.migrationIdentifier) { db in
            try V5_CreateAppMetadataTable.migrate(db)
        }
        migrator.registerMigration(V6_AddPlayCountTracking.migrationIdentifier) { db in
            try V6_AddPlayCountTracking.migrate(db)
        }
        migrator.registerMigration(V7_CreateSmartListsTable.migrationIdentifier) { db in
            try V7_CreateSmartListsTable.migrate(db)
        }
        migrator.registerMigration(V8_CreateSimpleListsTable.migrationIdentifier) { db in
            try V8_CreateSimpleListsTable.migrate(db)
        }
        migrator.registerMigration(V9_CreateSimpleListVideosTable.migrationIdentifier) { db in
            try V9_CreateSimpleListVideosTable.migrate(db)
        }
        migrator.registerMigration("v10_create_scrub_videos") { db in
            try db.execute(sql: "DROP TABLE IF EXISTS scrub_videos")
        }
        migrator.registerMigration("v11_create_scrub_queue") { db in
            try db.execute(sql: "DROP TABLE IF EXISTS scrub_queue")
        }
        migrator.registerMigration(V12_CreateScrubFramesTable.migrationIdentifier) { db in
            try V12_CreateScrubFramesTable.migrate(db)
        }
        migrator.registerMigration(V13_CreateSourceDirectoriesTable.migrationIdentifier) { db in
            try V13_CreateSourceDirectoriesTable.migrate(db)
        }
        migrator.registerMigration(V14_CreateTimeRangesTable.migrationIdentifier) { db in
            try V14_CreateTimeRangesTable.migrate(db)
        }
        migrator.registerMigration(V15_AddLastPlayedAt.migrationIdentifier) { db in
            try V15_AddLastPlayedAt.migrate(db)
        }
        migrator.registerMigration(V16_CreateAnnotationsTable.migrationIdentifier) { db in
            try V16_CreateAnnotationsTable.migrate(db)
        }
        migrator.registerMigration(V17_AddAnnotationCount.migrationIdentifier) { db in
            try V17_AddAnnotationCount.migrate(db)
        }
        migrator.registerMigration(V18_AddScrubFrameFormat.migrationIdentifier) { db in
            try V18_AddScrubFrameFormat.migrate(db)
        }
        migrator.registerMigration(V19_AddFilterIndexes.migrationIdentifier) { db in
            try V19_AddFilterIndexes.migrate(db)
        }
        migrator.registerMigration(V20_CreateFrameCapturesTable.migrationIdentifier) { db in
            try V20_CreateFrameCapturesTable.migrate(db)
        }

        let pool = try DatabasePool(path: databaseURL.path)
        try migrator.migrate(pool)

        try pool.write { db in
            // Raw insert: the current VideoFileRecord has columns added after V20
            let now = Date().timeIntervalSince1970
            try db.execute(
                sql: """
                    INSERT INTO video_files
                    (id, file_id, path, source_directory_id, filename, file_size, duration,
                     width, height, codec, last_modified, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [UUID(), "legacy-video", "/test/path/legacy.mp4", UUID(), "legacy.mp4",
                            1000, 10.0, 1920, 1080, "h264", now, now, now]
            )

            try db.execute(
                sql: """
                    INSERT INTO video_annotations
                    (id, video_file_id, frame_time, frame_rate, strokes_json, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    UUID().uuidString,
                    "legacy-video",
                    1.0,
                    24.0,
                    "[{\"legacy\":true}]",
                    Date().timeIntervalSince1970,
                    Date().timeIntervalSince1970,
                ]
            )
        }

        var v21Migrator = DatabaseMigrator()
        v21Migrator.registerMigration(V21_AddAnnotationText.migrationIdentifier) { db in
            try V21_AddAnnotationText.migrate(db)
        }
        try v21Migrator.migrate(pool)

        let legacyAnnotation = try pool.read { db in
            try AnnotationRecord.fetchOne(db, sql: "SELECT * FROM video_annotations WHERE video_file_id = ?", arguments: ["legacy-video"])
        }
        XCTAssertNotNil(legacyAnnotation)
        XCTAssertNil(legacyAnnotation?.text)
        XCTAssertEqual(legacyAnnotation?.strokesJSON, "[{\"legacy\":true}]")
    }

    func testLookupHelpersThrowOnDatabaseErrors() throws {
        // No migrations: the tables are missing, so every read fails.
        // A failure must surface as an error, never as "not found".
        let queue = try DatabaseQueue()
        try queue.read { db in
            XCTAssertThrowsError(try AnnotationRecord.findById(UUID(), in: db))
            XCTAssertThrowsError(try AnnotationRecord.findByVideoFileId("v", in: db))
            XCTAssertThrowsError(try AnnotationRecord.findByVideoFileIdAndFrameTime("v", frameTime: 1, in: db))
            XCTAssertThrowsError(try AnnotationRecord.listFrameTimes(forVideoFileId: "v", in: db))
            XCTAssertThrowsError(try FrameCaptureRecord.findById("c", in: db))
            XCTAssertThrowsError(try FrameCaptureRecord.findByFileId("v", in: db))
        }
    }
}

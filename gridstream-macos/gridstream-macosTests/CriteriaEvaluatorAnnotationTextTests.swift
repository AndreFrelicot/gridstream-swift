import GridStreamAPI
import XCTest
import GRDB
@testable import gridstream_macos

final class CriteriaEvaluatorAnnotationTextTests: XCTestCase {
    var testDatabaseURL: URL!
    var databaseManager: DatabaseManager!

    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GridStreamCriteriaEvaluatorTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        testDatabaseURL = testDir.appendingPathComponent("test_gridstream.sqlite")
        databaseManager = DatabaseManager(databasePath: testDatabaseURL)
        try await databaseManager.initialize()
    }

    override func tearDown() async throws {
        try await databaseManager.close()
        let testDir = testDatabaseURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: testDir)
        databaseManager = nil
        testDatabaseURL = nil
    }

    private func createVideo(fileId: String, rating: Int = 0) async throws {
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
            lastModified: Date().timeIntervalSince1970,
            rating: rating
        )

        try await databaseManager.write { db in
            try video.insert(db)
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

    func testHasTextAnnotationsTrueAndFalse() async throws {
        try await createVideo(fileId: "text-video")
        try await createVideo(fileId: "pencil-only-video")
        try await createVideo(fileId: "whitespace-text-video")
        try await createVideo(fileId: "plain-video")
        try await createAnnotation(fileId: "text-video", frameTime: 1, text: "corner note")
        try await createAnnotation(fileId: "pencil-only-video", frameTime: 1, text: nil)
        try await createAnnotation(fileId: "whitespace-text-video", frameTime: 1, text: "   ")

        let evaluator = CriteriaEvaluator()
        let withText = try await evaluator.evaluateCondition(.hasTextAnnotations(value: true), db: databaseManager)
        let withoutText = try await evaluator.evaluateCondition(.hasTextAnnotations(value: false), db: databaseManager)

        XCTAssertEqual(withText, ["text-video"])
        XCTAssertEqual(withoutText, ["pencil-only-video", "whitespace-text-video", "plain-video"])
    }

    func testHasTimeRangesTrueAndFalseOnlyIncludesPlayableSegments() async throws {
        try await createVideo(fileId: "segment-video")
        try await createVideo(fileId: "plain-video")
        try await createVideo(fileId: "invalid-segment-video")
        try await createTimeRange(fileId: "segment-video", startTime: 10, endTime: 20)
        try await createTimeRange(fileId: "invalid-segment-video", startTime: 90, endTime: 80)

        let evaluator = CriteriaEvaluator()
        let withSegments = try await evaluator.evaluateCondition(.hasTimeRanges(value: true), db: databaseManager)
        let withoutSegments = try await evaluator.evaluateCondition(.hasTimeRanges(value: false), db: databaseManager)

        XCTAssertEqual(withSegments, ["segment-video"])
        XCTAssertEqual(withoutSegments, ["invalid-segment-video", "plain-video"])
    }

    func testAnnotationTextSearchMatchesFTSContent() async throws {
        try await createVideo(fileId: "match-video")
        try await createVideo(fileId: "miss-video")
        try await createAnnotation(fileId: "match-video", frameTime: 1, text: "blue marker at the corner")
        try await createAnnotation(fileId: "miss-video", frameTime: 1, text: "red pencil stroke")

        let result = try await CriteriaEvaluator().evaluateCondition(
            .annotationTextSearch(text: "marker"),
            db: databaseManager
        )

        XCTAssertEqual(result, ["match-video"])
    }

    func testAnnotationTextSearchTreatsSpecialCharactersAsLiteralText() async throws {
        try await createVideo(fileId: "special-video")
        try await createVideo(fileId: "plain-video")
        try await createAnnotation(fileId: "special-video", frameTime: 1, text: #"tag:"blue"? marker"#)
        try await createAnnotation(fileId: "plain-video", frameTime: 1, text: "blue marker")

        let quotedResult = try await CriteriaEvaluator().evaluateCondition(
            .annotationTextSearch(text: #"tag:"blue"?"#),
            db: databaseManager
        )
        XCTAssertEqual(quotedResult, ["special-video"])

        let punctuationResult = try await CriteriaEvaluator().evaluateCondition(
            .annotationTextSearch(text: "??"),
            db: databaseManager
        )
        XCTAssertTrue(punctuationResult.isEmpty)
    }

    func testAnnotationCriteriaCombineWithAndOr() async throws {
        try await createVideo(fileId: "rated-text-video", rating: 8)
        try await createVideo(fileId: "low-text-video", rating: 2)
        try await createVideo(fileId: "unrated-plain-video", rating: 0)
        try await createAnnotation(fileId: "rated-text-video", frameTime: 1, text: "blue corner")
        try await createAnnotation(fileId: "low-text-video", frameTime: 1, text: "blue edge")

        let andCriteria = SmartListCriteria(conditions: [
            FilterCondition(id: UUID(), criteriaType: .annotationTextSearch(text: "blue"), logicOperator: .and),
            FilterCondition(id: UUID(), criteriaType: .ratingMin(value: 5), logicOperator: .and),
        ])
        let andResult = try await CriteriaEvaluator().evaluateCriteria(andCriteria, db: databaseManager)
        XCTAssertEqual(andResult, ["rated-text-video"])

        let orCriteria = SmartListCriteria(conditions: [
            FilterCondition(id: UUID(), criteriaType: .annotationTextSearch(text: "edge"), logicOperator: .and),
            FilterCondition(id: UUID(), criteriaType: .unrated, logicOperator: .or),
        ])
        let orResult = try await CriteriaEvaluator().evaluateCriteria(orCriteria, db: databaseManager)
        XCTAssertEqual(orResult, ["low-text-video", "unrated-plain-video"])
    }
}

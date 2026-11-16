import XCTest
import GRDB
@testable import gridstream_macos

final class VideoFileScrubTrackingTests: XCTestCase {

    var testDatabaseURL: URL!
    var databaseManager: DatabaseManager!

    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GridStreamTests_\(UUID().uuidString)")
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

    @discardableResult
    private func insertVideo(fileId: String, duration: Double = 100) async throws -> VideoFileRecord {
        let record = VideoFileRecord(
            fileId: fileId,
            path: "/tmp/\(fileId).mp4",
            sourceDirectoryId: UUID(),
            filename: "\(fileId).mp4",
            fileSize: 1000,
            duration: duration,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: 0
        )
        try await databaseManager.write { db in
            try record.insert(db)
        }
        return record
    }

    private func fetch(_ fileId: String) async throws -> VideoFileRecord? {
        try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(fileId, in: db)
        }
    }

    private func makeFrames(count: Int, payload: UInt8) -> [(time: Double, data: Data)] {
        (0..<count).map { index in
            (time: Double(index) * ScrubFrameGenerator.frameInterval,
             data: Data([payload, UInt8(index & 0xFF)]))
        }
    }

    // MARK: - C2: denormalized scrub_frame_count

    func testStoreFramesMaintainsScrubFrameCount() async throws {
        let fileId = "count-file-1"
        try await insertVideo(fileId: fileId)

        try await ScrubFrameCache.shared.storeFrames(
            videoId: fileId, frames: makeFrames(count: 25, payload: 0xAA), using: databaseManager)

        let record = try await fetch(fileId)
        XCTAssertEqual(record?.scrubFrameCount, 25)
    }

    func testScrubFrameCountIsIdempotentOnReStore() async throws {
        let fileId = "count-file-2"
        try await insertVideo(fileId: fileId)

        try await ScrubFrameCache.shared.storeFrames(
            videoId: fileId, frames: makeFrames(count: 25, payload: 0x01), using: databaseManager)
        // Same timestamps → upsert, no new rows.
        try await ScrubFrameCache.shared.storeFrames(
            videoId: fileId, frames: makeFrames(count: 25, payload: 0x02), using: databaseManager)

        let record = try await fetch(fileId)
        XCTAssertEqual(record?.scrubFrameCount, 25, "Re-storing identical timestamps must not inflate the count")
    }

    // MARK: - C4: failure tracking helpers

    func testRecordScrubFailureFlagsAfterMaxAttempts() async throws {
        let fileId = "fail-file-1"
        try await insertVideo(fileId: fileId)

        for attempt in 1...3 {
            try await databaseManager.write { db in
                try VideoFileRecord.recordScrubFailure(
                    fileId: fileId, error: "boom", now: 123, maxAttempts: 4, in: db)
            }
            let record = try await fetch(fileId)
            XCTAssertEqual(record?.scrubAttemptCount, attempt)
            XCTAssertEqual(record?.scrubFailed, false, "Should not be flagged before the 4th attempt")
        }

        try await databaseManager.write { db in
            try VideoFileRecord.recordScrubFailure(
                fileId: fileId, error: "boom", now: 123, maxAttempts: 4, in: db)
        }
        let record = try await fetch(fileId)
        XCTAssertEqual(record?.scrubAttemptCount, 4)
        XCTAssertEqual(record?.scrubFailed, true)
        XCTAssertEqual(record?.scrubLastError, "boom")
    }

    func testRecordScrubSuccessClearsFailureState() async throws {
        let fileId = "fail-file-2"
        try await insertVideo(fileId: fileId)

        for _ in 1...4 {
            try await databaseManager.write { db in
                try VideoFileRecord.recordScrubFailure(
                    fileId: fileId, error: "boom", now: 1, maxAttempts: 4, in: db)
            }
        }
        let flaggedBeforeSuccess = try await fetch(fileId)?.scrubFailed
        XCTAssertEqual(flaggedBeforeSuccess, true)

        try await databaseManager.write { db in
            try VideoFileRecord.recordScrubSuccess(fileId: fileId, in: db)
        }
        let record = try await fetch(fileId)
        XCTAssertEqual(record?.scrubFailed, false)
        XCTAssertEqual(record?.scrubAttemptCount, 0)
        XCTAssertNil(record?.scrubLastError)
    }

    func testResetScrubFailureClearsFlag() async throws {
        let fileId = "fail-file-3"
        try await insertVideo(fileId: fileId)

        for _ in 1...4 {
            try await databaseManager.write { db in
                try VideoFileRecord.recordScrubFailure(
                    fileId: fileId, error: "boom", now: 1, maxAttempts: 4, in: db)
            }
        }
        let flaggedBeforeReset = try await fetch(fileId)?.scrubFailed
        XCTAssertEqual(flaggedBeforeReset, true)

        try await databaseManager.write { db in
            try VideoFileRecord.resetScrubFailure(fileId: fileId, in: db)
        }
        let record = try await fetch(fileId)
        XCTAssertEqual(record?.scrubFailed, false)
        XCTAssertEqual(record?.scrubAttemptCount, 0)
        XCTAssertNil(record?.scrubLastError)
    }

    func testFetchScrubCandidatesAndBlockedPartition() async throws {
        try await insertVideo(fileId: "healthy-1")
        try await insertVideo(fileId: "blocked-1")

        for _ in 1...4 {
            try await databaseManager.write { db in
                try VideoFileRecord.recordScrubFailure(
                    fileId: "blocked-1", error: "boom", now: 1, maxAttempts: 4, in: db)
            }
        }

        let candidates = try await databaseManager.read { db in
            try VideoFileRecord.fetchScrubCandidates(in: db)
        }
        let blocked = try await databaseManager.read { db in
            try VideoFileRecord.fetchScrubBlocked(in: db)
        }

        XCTAssertEqual(candidates.map(\.fileId), ["healthy-1"])
        XCTAssertEqual(blocked.map(\.fileId), ["blocked-1"])
    }
}

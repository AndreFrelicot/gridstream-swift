import XCTest
import GRDB
@testable import gridstream_macos

final class ScrubFrameCacheTests: XCTestCase {

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

    /// Distinct grid-aligned timestamps with a recognizable payload per index.
    private func makeFrames(count: Int, payload: UInt8) -> [(time: Double, data: Data)] {
        (0..<count).map { index in
            (time: Double(index) * ScrubFrameGenerator.frameInterval,
             data: Data([payload, UInt8(index & 0xFF)]))
        }
    }

    func testStoreFramesInsertsAllRows() async throws {
        let fileId = "batch-file-1"
        let frames = makeFrames(count: 100, payload: 0xAA)

        try await ScrubFrameCache.shared.storeFrames(videoId: fileId, frames: frames, using: databaseManager)

        let count = try await databaseManager.read { db in
            try ScrubFrameRecord.count(forFileId: fileId, in: db)
        }
        XCTAssertEqual(count, 100)
    }

    func testStoreFramesRoundTripsData() async throws {
        let fileId = "batch-file-2"
        let frames = makeFrames(count: 10, payload: 0x42)

        try await ScrubFrameCache.shared.storeFrames(videoId: fileId, frames: frames, using: databaseManager)

        // index 3 → timestamp 6.0, payload [0x42, 0x03]
        let sampleTime = 3.0 * ScrubFrameGenerator.frameInterval
        let stored = try await databaseManager.read { db in
            try ScrubFrameRecord.find(fileId: fileId, timestamp: sampleTime, in: db)?.frameData
        }
        XCTAssertEqual(stored, Data([0x42, 0x03]))
    }

    func testStoreFramesIsIdempotentOnUpsert() async throws {
        let fileId = "batch-file-3"
        let first = makeFrames(count: 100, payload: 0x01)
        let second = makeFrames(count: 100, payload: 0x02) // same timestamps, fresh payloads

        try await ScrubFrameCache.shared.storeFrames(videoId: fileId, frames: first, using: databaseManager)
        try await ScrubFrameCache.shared.storeFrames(videoId: fileId, frames: second, using: databaseManager)

        let count = try await databaseManager.read { db in
            try ScrubFrameRecord.count(forFileId: fileId, in: db)
        }
        XCTAssertEqual(count, 100, "Upsert on unique (file_id, timestamp) must not duplicate rows")

        let latest = try await databaseManager.read { db in
            try ScrubFrameRecord.find(fileId: fileId, timestamp: 0.0, in: db)?.frameData
        }
        XCTAssertEqual(latest, Data([0x02, 0x00]), "Latest write should win on conflict")
    }

    func testStoreFramesEmptyIsNoOp() async throws {
        let fileId = "batch-file-4"

        try await ScrubFrameCache.shared.storeFrames(videoId: fileId, frames: [], using: databaseManager)

        let count = try await databaseManager.read { db in
            try ScrubFrameRecord.count(forFileId: fileId, in: db)
        }
        XCTAssertEqual(count, 0)
    }
}

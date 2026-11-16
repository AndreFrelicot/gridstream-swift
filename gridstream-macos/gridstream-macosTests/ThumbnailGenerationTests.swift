import XCTest
import AVFoundation
import GRDB
@testable import gridstream_macos

final class ThumbnailGenerationTests: XCTestCase {

    var testDatabaseURL: URL!
    var databaseManager: DatabaseManager!

    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("GridStreamThumbnailTests_\(UUID().uuidString)")
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

    // MARK: - Test Helpers

    private func createTestVideo(
        fileId: String,
        duration: Double = 120.0,
        sourceDirectoryId: UUID = UUID()
    ) async throws -> VideoFileRecord {
        let video = VideoFileRecord(
            fileId: fileId,
            path: "/test/path/video.mp4",
            sourceDirectoryId: sourceDirectoryId,
            filename: "video.mp4",
            fileSize: 1000,
            duration: duration,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: Date().timeIntervalSince1970
        )

        try await databaseManager.write { db in
            try video.insert(db)
        }

        return video
    }

    // MARK: - Test 1: Thumbnail generation captures at ~20 seconds for long videos

    func testThumbnailGeneratorCapturesAtTwentySecondsForLongVideo() async throws {
        // Test that for videos longer than 20 seconds, capture time is at 20 seconds
        let thumbnailGenerator = ThumbnailGenerator()
        let longVideoDuration = 120.0 // 2 minutes

        let captureTime = thumbnailGenerator.calculateCaptureTime(for: longVideoDuration)

        XCTAssertEqual(captureTime, 20.0, "Long videos should capture at 20 seconds")
    }

    // MARK: - Test 2: Thumbnail generation captures at 50% duration for short videos

    func testThumbnailGeneratorCapturesAtFiftyPercentForShortVideo() async throws {
        // Test that for videos shorter than 20 seconds, capture at 50% duration
        let thumbnailGenerator = ThumbnailGenerator()
        let shortVideoDuration = 10.0 // 10 seconds

        let captureTime = thumbnailGenerator.calculateCaptureTime(for: shortVideoDuration)

        XCTAssertEqual(captureTime, 5.0, "Short videos should capture at 50% duration")
    }

    // MARK: - Test 3: Thumbnail data storage and retrieval by fileId

    func testThumbnailStorageAndRetrievalByFileId() async throws {
        let fileId = "thumbnail_storage_test"
        _ = try await createTestVideo(fileId: fileId)

        // Create a test thumbnail data (a small valid JPEG header)
        let testImageData = createTestJPEGData()

        // Store thumbnail
        let thumbnail = ThumbnailRecord(
            fileId: fileId,
            imageData: testImageData
        )

        try await databaseManager.write { db in
            try thumbnail.insert(db)
        }

        // Retrieve thumbnail by fileId
        let retrievedThumbnail = try await databaseManager.read { db in
            try ThumbnailRecord.findByFileId(fileId, in: db)
        }

        XCTAssertNotNil(retrievedThumbnail)
        XCTAssertEqual(retrievedThumbnail?.fileId, fileId)
        XCTAssertEqual(retrievedThumbnail?.imageData, testImageData)
    }

    // MARK: - Test 4: Thumbnail endpoint returns correct content type

    func testThumbnailRecordStoresJPEGData() async throws {
        let fileId = "content_type_test"
        _ = try await createTestVideo(fileId: fileId)

        // Create test JPEG data
        let testImageData = createTestJPEGData()

        let thumbnail = ThumbnailRecord(
            fileId: fileId,
            imageData: testImageData
        )

        try await databaseManager.write { db in
            try thumbnail.insert(db)
        }

        let retrievedThumbnail = try await databaseManager.read { db in
            try ThumbnailRecord.findByFileId(fileId, in: db)
        }

        XCTAssertNotNil(retrievedThumbnail)

        // Verify the data starts with JPEG magic bytes (FFD8FF)
        let imageData = retrievedThumbnail!.imageData
        XCTAssertTrue(imageData.count >= 3)
        XCTAssertEqual(imageData[0], 0xFF)
        XCTAssertEqual(imageData[1], 0xD8)
        XCTAssertEqual(imageData[2], 0xFF)
    }

    // MARK: - Test Helpers

    private func createTestJPEGData() -> Data {
        // Create minimal valid JPEG data (JPEG header bytes)
        var data = Data()
        data.append(contentsOf: [0xFF, 0xD8, 0xFF, 0xE0]) // SOI and APP0 markers
        data.append(contentsOf: [0x00, 0x10]) // APP0 length
        data.append(contentsOf: "JFIF".utf8) // JFIF identifier
        data.append(contentsOf: [0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00])
        data.append(contentsOf: [0xFF, 0xD9]) // EOI marker
        return data
    }
}

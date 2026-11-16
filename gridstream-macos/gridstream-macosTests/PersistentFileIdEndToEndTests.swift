//
//  PersistentFileIdEndToEndTests.swift
//  gridstream-macosTests
//
//  End-to-end tests for the Persistent File ID System feature.
//  These tests verify critical integration workflows.
//

import GridStreamAPI
import XCTest
import GRDB
@testable import gridstream_macos

final class PersistentFileIdEndToEndTests: XCTestCase {

    var testDatabaseURL: URL!
    var databaseManager: DatabaseManager!
    var testDirectory: URL!
    var sampleVideoURL: URL?

    override func setUp() async throws {
        // Set up test database
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("PersistentFileIdE2ETests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        testDatabaseURL = testDir.appendingPathComponent("test_gridstream.sqlite")
        databaseManager = DatabaseManager(databasePath: testDatabaseURL)
        try await databaseManager.initialize()

        // Set up test video directory
        testDirectory = testDir.appendingPathComponent("videos")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)

        // Find a sample video file from the system
        sampleVideoURL = findSystemSampleVideo()
    }

    override func tearDown() async throws {
        try await databaseManager.close()
        let testDir = testDatabaseURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: testDir)
        databaseManager = nil
        testDatabaseURL = nil
        testDirectory = nil
        sampleVideoURL = nil
    }

    // MARK: - Test Helpers

    private func findSystemSampleVideo() -> URL? {
        let possiblePaths = [
            "/System/Library/Desktop Pictures/.wallpapers",
            "/System/Library/CoreServices",
            "/Library/Desktop Pictures"
        ]

        for basePath in possiblePaths {
            let baseURL = URL(fileURLWithPath: basePath)
            if let enumerator = FileManager.default.enumerator(
                at: baseURL,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) {
                for case let fileURL as URL in enumerator {
                    let ext = fileURL.pathExtension.lowercased()
                    if ["mp4", "m4v", "mov"].contains(ext) {
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                           let size = attrs[.size] as? Int64,
                           size >= FileHasher.minimumFileSize {
                            return fileURL
                        }
                    }
                }
            }
        }

        return nil
    }

    private func createTestVideoFile(name: String) throws -> URL {
        guard let sampleURL = sampleVideoURL else {
            throw XCTSkip("No sample video available on this system")
        }

        let destinationURL = testDirectory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: sampleURL, to: destinationURL)
        return destinationURL
    }

    private func createSourceDirectory(path: String) -> SourceDirectory {
        SourceDirectory(
            id: UUID(),
            path: path,
            isEnabled: true,
            lastScanned: nil,
            bookmarkData: nil
        )
    }

    // MARK: - End-to-End Test: Copied file produces same hash

    /// Tests the core value proposition: copying a file to a new location
    /// produces the same fileId, enabling metadata preservation.
    func testCopiedFileProducesSameFileId() async throws {
        // Create original file
        let originalFile = try createTestVideoFile(name: "original.mov")

        // Copy to new location (simulating user organizing their library)
        let copiedFile = testDirectory.appendingPathComponent("copied.mov")
        try FileManager.default.copyItem(at: originalFile, to: copiedFile)

        let hasher = FileHasher()

        let originalHash = try await hasher.computeFileId(for: originalFile)
        let copiedHash = try await hasher.computeFileId(for: copiedFile)

        // Core value proposition: same content = same fileId
        XCTAssertEqual(
            originalHash,
            copiedHash,
            "Copied file should have the same fileId as the original"
        )
    }

    // MARK: - End-to-End Test: Full scan and database lookup workflow

    /// Tests the complete workflow: scan populates database, and records
    /// can be retrieved by fileId, enabling the API lookup functionality.
    func testFullScanPopulatesDatabaseAndSupportsLookup() async throws {
        // Create test video
        _ = try createTestVideoFile(name: "test_video.mov")

        let sourceDirectory = createSourceDirectory(path: testDirectory.path)
        let scanner = VideoScanner(databaseManager: databaseManager)

        // Scan to populate database
        let videos = try await scanner.scan(directories: [sourceDirectory])

        XCTAssertEqual(videos.count, 1, "Should find one video")

        let scannedVideo = videos[0]
        let fileId = scannedVideo.fileId

        // Verify we can look up the record by fileId (simulating API lookup)
        let record = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(fileId, in: db)
        }

        XCTAssertNotNil(record, "Should find record in database by fileId")
        XCTAssertEqual(record?.filename, "test_video.mov")
        XCTAssertEqual(record?.fileId, fileId)

        // Verify all fields are populated (mapping is complete)
        XCTAssertFalse(record?.path.isEmpty ?? true, "Path should be populated")
        XCTAssertGreaterThan(record?.fileSize ?? 0, 0, "File size should be populated")
        XCTAssertGreaterThan(record?.duration ?? 0, 0, "Duration should be populated")
        XCTAssertGreaterThan(record?.width ?? 0, 0, "Width should be populated")
        XCTAssertGreaterThan(record?.height ?? 0, 0, "Height should be populated")
    }
}

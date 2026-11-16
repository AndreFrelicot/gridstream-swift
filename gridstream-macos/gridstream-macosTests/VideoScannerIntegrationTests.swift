//
//  VideoScannerIntegrationTests.swift
//  gridstream-macosTests
//
//  Integration tests for VideoScanner database functionality.
//

import GridStreamAPI
import XCTest
import GRDB
@testable import gridstream_macos

final class VideoScannerIntegrationTests: XCTestCase {

    var testDatabaseURL: URL!
    var databaseManager: DatabaseManager!
    var testDirectory: URL!
    var sampleVideoURL: URL?

    override func setUp() async throws {
        // Set up test database
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("VideoScannerTests_\(UUID().uuidString)")
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

    /// Finds a sample video file from the system for testing
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
                        // Check if file is large enough for hashing
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                           let size = attrs[.size] as? Int64,
                           size >= FileHasher.minimumFileSize {
                            return fileURL
                        }
                    }
                }
            }
        }

        // Try specific known video paths
        let knownPaths = [
            "/System/Library/Desktop Pictures/.wallpapers/Sonoma/Sonoma Graphic Light Portrait.mov"
        ]

        for path in knownPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path),
               let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64,
               size >= FileHasher.minimumFileSize {
                return url
            }
        }

        return nil
    }

    /// Creates a test video file by copying a system sample video
    private func createTestVideoFile(name: String) throws -> URL {
        guard let sampleURL = sampleVideoURL else {
            throw XCTSkip("No sample video available on this system")
        }

        let destinationURL = testDirectory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: sampleURL, to: destinationURL)
        return destinationURL
    }

    /// Creates a small (under 192KB) test file
    private func createSmallTestFile(name: String, sizeInBytes: Int) throws -> URL {
        let fileURL = testDirectory.appendingPathComponent(name)
        var data = Data(count: sizeInBytes)
        for i in 0..<sizeInBytes {
            data[i] = UInt8(i % 256)
        }
        try data.write(to: fileURL)
        return fileURL
    }

    /// Creates a source directory for testing
    private func createSourceDirectory(path: String) -> SourceDirectory {
        SourceDirectory(
            id: UUID(),
            path: path,
            isEnabled: true,
            lastScanned: nil,
            bookmarkData: nil
        )
    }

    // MARK: - Test 1: Small files (< 192KB) are skipped during scan

    func testSmallFilesAreSkippedDuringScan() async throws {
        // Create a small file (under 192KB threshold)
        _ = try createSmallTestFile(name: "small_video.mp4", sizeInBytes: 100_000)

        // Create a large enough file (real video)
        _ = try createTestVideoFile(name: "large_video.mov")

        let sourceDirectory = createSourceDirectory(path: testDirectory.path)
        let scanner = VideoScanner(databaseManager: databaseManager)

        let videos = try await scanner.scan(directories: [sourceDirectory])

        // Only the large file should be included (small file excluded by size check)
        XCTAssertEqual(videos.count, 1, "Only files >= 192KB should be scanned")
        XCTAssertTrue(videos[0].filename.contains("large_video"), "The large video should be in results")
    }

    // MARK: - Test 2: New files are inserted into database with fileId

    func testNewFilesAreInsertedIntoDatabaseWithFileId() async throws {
        // Create a test video file
        _ = try createTestVideoFile(name: "new_video.mov")

        let sourceDirectory = createSourceDirectory(path: testDirectory.path)
        let scanner = VideoScanner(databaseManager: databaseManager)

        let videos = try await scanner.scan(directories: [sourceDirectory])

        XCTAssertEqual(videos.count, 1)
        XCTAssertFalse(videos[0].fileId.isEmpty, "Video should have a fileId")

        // Verify the record exists in database
        let recordCount = try await databaseManager.read { db in
            try VideoFileRecord.fetchCount(db)
        }
        XCTAssertEqual(recordCount, 1, "One record should be in the database")

        let record = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(videos[0].fileId, in: db)
        }
        XCTAssertNotNil(record, "Record should exist in database with matching fileId")
        XCTAssertEqual(record?.filename, "new_video.mov")
    }

    // MARK: - Test 3: Rescan identifies moved file by fileId and updates path

    func testRescanIdentifiesMovedFileByFileIdAndUpdatesPath() async throws {
        // Create initial test video file
        let originalFile = try createTestVideoFile(name: "video.mov")

        let sourceDirectory = createSourceDirectory(path: testDirectory.path)
        let scanner = VideoScanner(databaseManager: databaseManager)

        // First scan
        let firstScanVideos = try await scanner.scan(directories: [sourceDirectory])
        XCTAssertEqual(firstScanVideos.count, 1)
        let originalFileId = firstScanVideos[0].fileId

        // Get original database record
        let originalRecord = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(originalFileId, in: db)
        }
        let originalDatabaseId = originalRecord?.id
        let originalPath = originalRecord?.path

        // Create a subdirectory and move the file
        let subDir = testDirectory.appendingPathComponent("subfolder")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let newLocation = subDir.appendingPathComponent("video.mov")
        try FileManager.default.moveItem(at: originalFile, to: newLocation)

        // Second scan after move
        let secondScanVideos = try await scanner.scan(directories: [sourceDirectory])

        XCTAssertEqual(secondScanVideos.count, 1)
        XCTAssertEqual(secondScanVideos[0].fileId, originalFileId, "FileId should be the same after move")

        // Verify database was updated with new path
        let updatedRecord = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(originalFileId, in: db)
        }
        XCTAssertNotNil(updatedRecord)
        XCTAssertNotEqual(updatedRecord?.path, originalPath, "Path should be updated")
        XCTAssertTrue(updatedRecord?.path.contains("subfolder") ?? false, "New path should contain subfolder")
        XCTAssertEqual(updatedRecord?.id, originalDatabaseId, "Database ID should be preserved")
    }

    // MARK: - Test 4: Records of deleted files are soft-deleted after scan

    func testOrphanedRecordsAreSoftDeletedAfterScan() async throws {
        // Create test video file
        let videoFile = try createTestVideoFile(name: "video.mov")
        // Keep the folder non-empty so the scan treats it as available
        _ = try createSmallTestFile(name: "anchor.mp4", sizeInBytes: 300_000)

        let sourceDirectory = createSourceDirectory(path: testDirectory.path)
        let scanner = VideoScanner(databaseManager: databaseManager)

        // First scan to populate database
        _ = try await scanner.scan(directories: [sourceDirectory])

        // Verify record exists
        let initialCount = try await databaseManager.read { db in
            try VideoFileRecord.fetchCount(db)
        }
        XCTAssertEqual(initialCount, 1)

        // Delete the file
        try FileManager.default.removeItem(at: videoFile)

        // Rescan
        let secondScanVideos = try await scanner.scan(directories: [sourceDirectory])

        XCTAssertEqual(secondScanVideos.count, 0, "No videos should be found after file deletion")

        // Verify the record was soft-deleted, not purged
        let records = try await databaseManager.read { db in
            try VideoFileRecord.fetchAll(db)
        }
        XCTAssertEqual(records.count, 1, "Missing record is kept")
        XCTAssertNotNil(records.first?.missingSince, "Missing record is soft-deleted")
    }

    // MARK: - Test 5: Scan returns VideoItems with fileId populated

    func testScanReturnsVideoItemsWithFileIdPopulated() async throws {
        // Create a test video file
        _ = try createTestVideoFile(name: "video.mov")

        let sourceDirectory = createSourceDirectory(path: testDirectory.path)
        let scanner = VideoScanner(databaseManager: databaseManager)

        let videos = try await scanner.scan(directories: [sourceDirectory])

        XCTAssertEqual(videos.count, 1)

        let video = videos[0]
        XCTAssertFalse(video.fileId.isEmpty, "Video should have a fileId")
        XCTAssertEqual(video.fileId.count, 16, "FileId should be 16 characters (hex-encoded xxHash64)")

        // Verify fileId contains only hex characters
        let hexCharacterSet = CharacterSet(charactersIn: "0123456789abcdef")
        let fileIdCharacters = CharacterSet(charactersIn: video.fileId.lowercased())
        XCTAssertTrue(fileIdCharacters.isSubset(of: hexCharacterSet), "FileId should only contain hex characters")
    }

    // MARK: - Test 6: Database record preserves id when file is moved

    func testDatabaseRecordPreservesIdWhenFileIsMoved() async throws {
        // Create initial test video file
        let originalFile = try createTestVideoFile(name: "persistent_video.mov")

        let sourceDirectory = createSourceDirectory(path: testDirectory.path)
        let scanner = VideoScanner(databaseManager: databaseManager)

        // First scan
        _ = try await scanner.scan(directories: [sourceDirectory])

        // Get original database record
        let originalRecord = try await databaseManager.read { db in
            try VideoFileRecord.fetchAll(db).first
        }
        let originalId = originalRecord?.id
        let originalCreatedAt = originalRecord?.createdAt

        XCTAssertNotNil(originalId)
        XCTAssertNotNil(originalCreatedAt)

        // Move the file to a different location
        let newDirectory = testDirectory.appendingPathComponent("newlocation")
        try FileManager.default.createDirectory(at: newDirectory, withIntermediateDirectories: true)
        let newLocation = newDirectory.appendingPathComponent("persistent_video.mov")
        try FileManager.default.moveItem(at: originalFile, to: newLocation)

        // Second scan after move
        _ = try await scanner.scan(directories: [sourceDirectory])

        // Verify the database record ID and created_at were preserved
        let updatedRecord = try await databaseManager.read { db in
            try VideoFileRecord.fetchAll(db).first
        }

        XCTAssertEqual(updatedRecord?.id, originalId, "Database ID should be preserved after file move")
        XCTAssertEqual(updatedRecord?.createdAt, originalCreatedAt, "created_at should be preserved after file move")
        XCTAssertNotEqual(updatedRecord?.path, originalRecord?.path, "Path should be updated")
    }
}

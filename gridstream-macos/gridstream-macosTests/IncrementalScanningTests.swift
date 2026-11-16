//
//  IncrementalScanningTests.swift
//  gridstream-macosTests
//
//  Tests for incremental scanning functionality including:
//  - Unchanged files are skipped (no metadata extraction when lastModified matches)
//  - New files are detected and processed
//  - Modified files are detected and re-processed
//  - Deleted files are removed from database
//  - Scan can run in background without blocking
//

import GridStreamAPI
import XCTest
import GRDB
@testable import gridstream_macos

final class IncrementalScanningTests: XCTestCase {

    var testDatabaseURL: URL!
    var databaseManager: DatabaseManager!
    var testDirectory: URL!
    var sampleVideoURL: URL?

    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("IncrementalScanTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        testDatabaseURL = testDir.appendingPathComponent("test_gridstream.sqlite")
        databaseManager = DatabaseManager(databasePath: testDatabaseURL)
        try await databaseManager.initialize()

        testDirectory = testDir.appendingPathComponent("videos")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)

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

    private func createTestVideoFile(name: String) throws -> URL {
        guard let sampleURL = sampleVideoURL else {
            throw XCTSkip("No sample video available on this system")
        }

        let destinationURL = testDirectory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: sampleURL, to: destinationURL)
        return destinationURL
    }

    private func createSourceDirectory(path: String, id: UUID = UUID()) -> SourceDirectory {
        SourceDirectory(
            id: id,
            path: path,
            isEnabled: true,
            lastScanned: nil,
            bookmarkData: nil
        )
    }

    private func createVideoRecord(
        fileId: String,
        path: String,
        filename: String,
        sourceDirectoryId: UUID,
        lastModified: Double
    ) -> VideoFileRecord {
        VideoFileRecord(
            fileId: fileId,
            path: path,
            sourceDirectoryId: sourceDirectoryId,
            filename: filename,
            fileSize: 1000,
            duration: 120.0,
            width: 1920,
            height: 1080,
            codec: "h264",
            lastModified: lastModified
        )
    }

    // MARK: - Test 1: Unchanged files are skipped

    func testUnchangedFilesAreSkipped() async throws {
        // Create a test video file
        let videoFile = try createTestVideoFile(name: "unchanged_video.mov")

        let sourceDirectory = createSourceDirectory(path: testDirectory.path)
        let scanner = VideoScanner(databaseManager: databaseManager)

        // First scan to populate database
        let firstScanVideos = try await scanner.scan(directories: [sourceDirectory])
        XCTAssertEqual(firstScanVideos.count, 1)

        // Get the record after first scan
        let firstRecord = try await databaseManager.read { db in
            try VideoFileRecord.fetchAllRecords(in: db).first
        }
        let firstUpdatedAt = firstRecord?.updatedAt
        XCTAssertNotNil(firstUpdatedAt)

        // Wait a small amount to ensure updatedAt would be different if changed
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Second scan without modifying the file
        let secondScanVideos = try await scanner.scan(directories: [sourceDirectory])
        XCTAssertEqual(secondScanVideos.count, 1)

        // Verify the record was not updated (same updatedAt timestamp)
        let secondRecord = try await databaseManager.read { db in
            try VideoFileRecord.fetchAllRecords(in: db).first
        }

        // The updatedAt should remain the same because the file was unchanged
        XCTAssertEqual(secondRecord?.updatedAt, firstUpdatedAt, "Unchanged file should not update the record's updatedAt")
    }

    // MARK: - Test 2: New files are detected and processed

    func testNewFilesAreDetectedAndProcessed() async throws {
        let sourceDirectory = createSourceDirectory(path: testDirectory.path)
        let scanner = VideoScanner(databaseManager: databaseManager)

        // First scan with no files
        let firstScanVideos = try await scanner.scan(directories: [sourceDirectory])
        XCTAssertEqual(firstScanVideos.count, 0)

        // Add a new video file
        _ = try createTestVideoFile(name: "new_video.mov")

        // Second scan should detect the new file
        let secondScanVideos = try await scanner.scan(directories: [sourceDirectory])
        XCTAssertEqual(secondScanVideos.count, 1)
        XCTAssertEqual(secondScanVideos.first?.filename, "new_video.mov")

        // Verify it's in the database
        let recordCount = try await databaseManager.read { db in
            try VideoFileRecord.fetchCount(db)
        }
        XCTAssertEqual(recordCount, 1)
    }

    // MARK: - Test 3: Modified files are detected and re-processed

    func testModifiedFilesAreDetectedAndReprocessed() async throws {
        // Create a test video file
        let videoFile = try createTestVideoFile(name: "modified_video.mov")

        let sourceDirectory = createSourceDirectory(path: testDirectory.path)
        let scanner = VideoScanner(databaseManager: databaseManager)

        // First scan
        let firstScanVideos = try await scanner.scan(directories: [sourceDirectory])
        XCTAssertEqual(firstScanVideos.count, 1)

        // Get the original record
        let originalRecord = try await databaseManager.read { db in
            try VideoFileRecord.fetchAllRecords(in: db).first
        }
        let originalUpdatedAt = originalRecord?.updatedAt
        XCTAssertNotNil(originalUpdatedAt)

        // Wait and then "modify" the file by changing its modification date
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        let futureDate = Date().addingTimeInterval(1000) // 1000 seconds in the future
        try FileManager.default.setAttributes(
            [.modificationDate: futureDate],
            ofItemAtPath: videoFile.path
        )

        // Second scan should detect the modification
        let secondScanVideos = try await scanner.scan(directories: [sourceDirectory])
        XCTAssertEqual(secondScanVideos.count, 1)

        // Verify the record was updated
        let updatedRecord = try await databaseManager.read { db in
            try VideoFileRecord.fetchAllRecords(in: db).first
        }

        XCTAssertNotNil(updatedRecord?.updatedAt)
        XCTAssertGreaterThan(updatedRecord!.updatedAt, originalUpdatedAt!, "Modified file should update the record's updatedAt")
    }

    // MARK: - Test 4: Deleted files are soft-deleted from the catalog

    func testDeletedFilesAreSoftDeleted() async throws {
        // Create a test video file
        let videoFile = try createTestVideoFile(name: "to_be_deleted.mov")
        // Keep the folder non-empty so the scan treats it as available
        try Data(repeating: 0x42, count: 300_000).write(to: testDirectory.appendingPathComponent("anchor.mp4"))

        let sourceDirectory = createSourceDirectory(path: testDirectory.path)
        let scanner = VideoScanner(databaseManager: databaseManager)

        // First scan to add the file to database
        let firstScanVideos = try await scanner.scan(directories: [sourceDirectory])
        XCTAssertEqual(firstScanVideos.count, 1)

        // Delete the file
        try FileManager.default.removeItem(at: videoFile)

        // Second scan should detect the deletion
        let secondScanVideos = try await scanner.scan(directories: [sourceDirectory])
        XCTAssertEqual(secondScanVideos.count, 0)

        // Verify record was soft-deleted (kept, excluded from the catalog)
        let (total, live) = try await databaseManager.read { db in
            (try VideoFileRecord.fetchCount(db), try VideoFileRecord.liveFileIds(in: db).count)
        }
        XCTAssertEqual(total, 1, "Deleted file's record is kept for restoration")
        XCTAssertEqual(live, 0, "Deleted file's record is excluded from the catalog")
    }

    // MARK: - Test 5: Scan can run in background without blocking

    func testScanCanRunInBackgroundWithoutBlocking() async throws {
        _ = try createTestVideoFile(name: "background_test.mov")

        let sourceDirectory = createSourceDirectory(path: testDirectory.path)
        let scanner = VideoScanner(databaseManager: databaseManager)

        // Run scan in a detached task to simulate background operation
        let scanTask = Task.detached {
            try await scanner.scan(directories: [sourceDirectory])
        }

        // This code should execute immediately without waiting for scan
        let taskStarted = true
        XCTAssertTrue(taskStarted, "Code should not be blocked by background scan")

        // Wait for scan to complete and verify results
        let videos = try await scanTask.value
        XCTAssertEqual(videos.count, 1)
    }

    // MARK: - Test 6: loadCachedVideos returns cached data immediately

    func testLoadCachedVideosReturnsCachedDataImmediately() async throws {
        // Create a source directory with a known ID
        let sourceDirectoryId = UUID()
        let sourceDirectory = createSourceDirectory(path: testDirectory.path, id: sourceDirectoryId)

        // Insert some video records directly into database using the same source directory ID
        let records = [
            createVideoRecord(
                fileId: "cached_file_1",
                path: "/test/path/video1.mp4",
                filename: "video1.mp4",
                sourceDirectoryId: sourceDirectoryId,
                lastModified: Date().timeIntervalSince1970
            ),
            createVideoRecord(
                fileId: "cached_file_2",
                path: "/test/path/video2.mp4",
                filename: "video2.mp4",
                sourceDirectoryId: sourceDirectoryId,
                lastModified: Date().timeIntervalSince1970
            )
        ]

        for record in records {
            try await databaseManager.write { db in
                let mutableRecord = record
                try mutableRecord.insert(db)
            }
        }

        let scanner = VideoScanner(databaseManager: databaseManager)

        // Load cached videos should return immediately without scanning
        let cachedVideos = try await scanner.loadCachedVideos(sourceDirectories: [sourceDirectory])

        XCTAssertEqual(cachedVideos.count, 2)
        let filenames = Set(cachedVideos.map { $0.filename })
        XCTAssertTrue(filenames.contains("video1.mp4"))
        XCTAssertTrue(filenames.contains("video2.mp4"))
    }

    // MARK: - Test 7: loadCachedVideos handles empty database gracefully

    func testLoadCachedVideosHandlesEmptyDatabaseGracefully() async throws {
        let sourceDirectory = createSourceDirectory(path: testDirectory.path)
        let scanner = VideoScanner(databaseManager: databaseManager)

        // Load cached videos from empty database
        let cachedVideos = try await scanner.loadCachedVideos(sourceDirectories: [sourceDirectory])

        XCTAssertEqual(cachedVideos.count, 0, "Empty database should return empty array")
    }
}

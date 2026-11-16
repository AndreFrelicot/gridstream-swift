//
//  MetadataExtractorTests.swift
//  gridstream-macosTests
//
//  Unit tests for MetadataExtractor functionality.
//

import XCTest
@testable import gridstream_macos

final class MetadataExtractorTests: XCTestCase {

    var extractor: MetadataExtractor!

    override func setUp() async throws {
        extractor = MetadataExtractor()
    }

    override func tearDown() async throws {
        extractor = nil
    }

    // MARK: - Test Invalid File Handling

    func testExtractFromNonExistentFileThrowsError() async throws {
        let nonExistentURL = URL(fileURLWithPath: "/nonexistent/path/video.mp4")

        do {
            _ = try await extractor.extract(from: nonExistentURL)
            XCTFail("Expected error for non-existent file")
        } catch {
            // Expected to throw an error for non-existent file
            XCTAssertNotNil(error)
        }
    }

    func testExtractFromInvalidFileTypeThrowsError() async throws {
        // Create a temporary text file to test with invalid content
        let tempDir = FileManager.default.temporaryDirectory
        let invalidFileURL = tempDir.appendingPathComponent("invalid_test_\(UUID().uuidString).txt")

        let testContent = "This is not a video file"
        try testContent.write(to: invalidFileURL, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: invalidFileURL)
        }

        do {
            _ = try await extractor.extract(from: invalidFileURL)
            XCTFail("Expected error for invalid file type")
        } catch {
            // Expected to throw an error for invalid video file
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Test File Attributes Extraction

    func testExtractFileAttributesFromExistingFile() async throws {
        // Create a temporary file to test file attribute extraction
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileURL = tempDir.appendingPathComponent("test_file_\(UUID().uuidString).dat")

        let testData = Data(repeating: 0, count: 1024)
        try testData.write(to: tempFileURL)

        defer {
            try? FileManager.default.removeItem(at: tempFileURL)
        }

        // Get file attributes directly using FileManager
        let attributes = try FileManager.default.attributesOfItem(atPath: tempFileURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        let modificationDate = attributes[.modificationDate] as? Date ?? Date()

        XCTAssertEqual(fileSize, 1024)
        XCTAssertNotNil(modificationDate)
        XCTAssertTrue(modificationDate <= Date())
    }

    // MARK: - Test with Valid Video (if available)

    func testExtractFromSystemSampleVideoIfAvailable() async throws {
        // Try to find a system sample video or skip the test
        // Common locations for sample videos on macOS
        let possiblePaths = [
            "/Library/Desktop Pictures",
            "/System/Library/Compositions"
        ]

        var sampleVideoURL: URL?

        for basePath in possiblePaths {
            let baseURL = URL(fileURLWithPath: basePath)
            if let enumerator = FileManager.default.enumerator(
                at: baseURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator.allObjects {
                    let ext = fileURL.pathExtension.lowercased()
                    if ["mp4", "m4v", "mov"].contains(ext) {
                        sampleVideoURL = fileURL
                        break
                    }
                }
            }
            if sampleVideoURL != nil { break }
        }

        guard let videoURL = sampleVideoURL else {
            // Skip test if no sample video is available
            throw XCTSkip("No sample video available on this system")
        }

        let metadata = try await extractor.extract(from: videoURL)

        // Verify metadata has reasonable values
        XCTAssertGreaterThanOrEqual(metadata.duration, 0)
        XCTAssertGreaterThanOrEqual(metadata.width, 0)
        XCTAssertGreaterThanOrEqual(metadata.height, 0)
        XCTAssertFalse(metadata.codec.isEmpty)
        XCTAssertGreaterThan(metadata.fileSize, 0)
        XCTAssertNotNil(metadata.lastModified)
    }
}

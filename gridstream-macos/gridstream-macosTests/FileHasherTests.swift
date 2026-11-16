//
//  FileHasherTests.swift
//  gridstream-macosTests
//
//  Unit tests for FileHasher functionality.
//

import XCTest
@testable import gridstream_macos

final class FileHasherTests: XCTestCase {

    var hasher: FileHasher!

    override func setUp() async throws {
        hasher = FileHasher()
    }

    override func tearDown() async throws {
        hasher = nil
    }

    // MARK: - Test Helpers

    /// Creates a temporary file with specified size filled with pattern data
    private func createTemporaryFile(sizeInBytes: Int, pattern: UInt8 = 0xAB) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileURL = tempDir.appendingPathComponent("test_file_\(UUID().uuidString).dat")

        var data = Data(count: sizeInBytes)
        for i in 0..<sizeInBytes {
            data[i] = UInt8((Int(pattern) + i) % 256)
        }
        try data.write(to: tempFileURL)

        return tempFileURL
    }

    // MARK: - Test Consistent Hash Output

    func testConsistentHashOutputForSameFileContent() async throws {
        // Create a file large enough to be hashed (>= 192KB)
        let fileURL = try createTemporaryFile(sizeInBytes: 200_000, pattern: 0xAB)

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        // Compute hash twice for the same file
        let hash1 = try await hasher.computeFileId(for: fileURL)
        let hash2 = try await hasher.computeFileId(for: fileURL)

        // Both hashes should be identical
        XCTAssertEqual(hash1, hash2, "Hash should be consistent for the same file content")
    }

    // MARK: - Test Different Hash Output for Different Content

    func testDifferentHashOutputForDifferentContent() async throws {
        // Create two files with different content
        let fileURL1 = try createTemporaryFile(sizeInBytes: 200_000, pattern: 0xAB)
        let fileURL2 = try createTemporaryFile(sizeInBytes: 200_000, pattern: 0xCD)

        defer {
            try? FileManager.default.removeItem(at: fileURL1)
            try? FileManager.default.removeItem(at: fileURL2)
        }

        let hash1 = try await hasher.computeFileId(for: fileURL1)
        let hash2 = try await hasher.computeFileId(for: fileURL2)

        // Hashes should be different for different content
        XCTAssertNotEqual(hash1, hash2, "Hash should be different for different file content")
    }

    // MARK: - Test File Size Threshold Rejection

    func testFileSizeThresholdRejection() async throws {
        // Create a file smaller than 192KB (threshold is 196608 bytes = 192KB)
        let smallFileURL = try createTemporaryFile(sizeInBytes: 100_000, pattern: 0xAB)

        defer {
            try? FileManager.default.removeItem(at: smallFileURL)
        }

        do {
            _ = try await hasher.computeFileId(for: smallFileURL)
            XCTFail("Expected error for file smaller than 192KB")
        } catch let error as FileHasherError {
            // Verify the error is specifically about file size
            if case .fileTooSmall(let size, let minimum) = error {
                XCTAssertEqual(size, 100_000)
                XCTAssertEqual(minimum, 196_608)
            } else {
                XCTFail("Expected fileTooSmall error")
            }
        } catch {
            XCTFail("Expected FileHasherError, got: \(error)")
        }
    }

    // MARK: - Test Hex-Encoded Output Format

    func testHexEncodedOutputIs16Characters() async throws {
        let fileURL = try createTemporaryFile(sizeInBytes: 200_000, pattern: 0xAB)

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let hash = try await hasher.computeFileId(for: fileURL)

        // xxHash64 produces 64-bit hash = 8 bytes = 16 hex characters
        XCTAssertEqual(hash.count, 16, "Hash should be exactly 16 hexadecimal characters")

        // Verify all characters are valid hex digits
        let hexCharacterSet = CharacterSet(charactersIn: "0123456789abcdef")
        let hashCharacters = CharacterSet(charactersIn: hash.lowercased())
        XCTAssertTrue(hashCharacters.isSubset(of: hexCharacterSet), "Hash should only contain hex characters")
    }

    // MARK: - Test Middle Chunk Calculation

    func testMiddleChunkCalculationIsCorrect() async throws {
        // Create a file where we can verify the middle chunk position
        // File size: 300KB = 307200 bytes
        // Middle position should be: (307200 / 2) - 32768 = 153600 - 32768 = 120832
        let fileSize = 307_200
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_middle_chunk_\(UUID().uuidString).dat")

        // Create file with distinct patterns in each chunk region
        var data = Data(count: fileSize)

        // First 64KB: pattern 0x11
        for i in 0..<65_536 {
            data[i] = 0x11
        }

        // Middle 64KB (starting at position 120832): pattern 0x22
        let middleStart = (fileSize / 2) - 32_768
        for i in middleStart..<(middleStart + 65_536) {
            data[i] = 0x22
        }

        // Last 64KB: pattern 0x33
        let lastStart = fileSize - 65_536
        for i in lastStart..<fileSize {
            data[i] = 0x33
        }

        // Fill remaining bytes with 0x00
        try data.write(to: fileURL)

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        // Create another file with same first and last chunks but different middle
        let fileURL2 = tempDir.appendingPathComponent("test_middle_chunk2_\(UUID().uuidString).dat")
        var data2 = data // Copy the first file's data
        // Change middle chunk pattern to 0x44
        for i in middleStart..<(middleStart + 65_536) {
            data2[i] = 0x44
        }
        try data2.write(to: fileURL2)

        defer {
            try? FileManager.default.removeItem(at: fileURL2)
        }

        let hash1 = try await hasher.computeFileId(for: fileURL)
        let hash2 = try await hasher.computeFileId(for: fileURL2)

        // Hashes should be different because middle chunks differ
        XCTAssertNotEqual(hash1, hash2, "Hash should differ when middle chunk content differs")
    }
}

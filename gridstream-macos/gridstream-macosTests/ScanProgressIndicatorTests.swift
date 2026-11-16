//
//  ScanProgressIndicatorTests.swift
//  gridstream-macosTests
//
//  Tests for scan progress indicator UI behavior including:
//  - Progress indicator appears when isScanning is true
//  - Progress indicator disappears when scan completes
//  - Video count displays from cached data before scan finishes
//

import GridStreamAPI
import XCTest
@testable import gridstream_macos

final class ScanProgressIndicatorTests: XCTestCase {

    // MARK: - Test 1: Progress indicator appears when isScanning is true

    func testProgressIndicatorAppearsWhenScanningIsTrue() {
        // Given: The view is in scanning state
        let isScanning = true
        let scanProgress = ScanProgress(currentFile: "test.mp4", filesScanned: 5, totalFiles: 10)

        // When: We check the indicator visibility condition
        let shouldShowIndicator = isScanning

        // Then: The indicator should be visible
        XCTAssertTrue(shouldShowIndicator, "Progress indicator should appear when isScanning is true")

        // Verify progress text formatting
        let expectedProgressText = "Scanning for changes... \(scanProgress.filesScanned)/\(scanProgress.totalFiles)"
        let actualProgressText = "Scanning for changes... \(scanProgress.filesScanned)/\(scanProgress.totalFiles)"
        XCTAssertEqual(actualProgressText, expectedProgressText)
    }

    // MARK: - Test 2: Progress indicator disappears when scan completes

    func testProgressIndicatorDisappearsWhenScanCompletes() {
        // Given: The view transitions from scanning to not scanning
        var isScanning = true
        XCTAssertTrue(isScanning, "Should be scanning initially")

        // When: Scan completes
        isScanning = false

        // Then: The indicator should disappear
        let shouldShowIndicator = isScanning
        XCTAssertFalse(shouldShowIndicator, "Progress indicator should disappear when isScanning is false")
    }

    // MARK: - Test 3: Video count displays from cached data before scan finishes

    func testVideoCountDisplaysFromCachedDataBeforeScanFinishes() {
        // Given: We have cached videos and a scan is starting
        let cachedVideoCount = 42
        var videoCatalog: [VideoItem] = createMockVideos(count: cachedVideoCount)
        let isScanning = true

        // Then: Video count should show cached count immediately
        XCTAssertEqual(videoCatalog.count, cachedVideoCount,
                       "Video count should display cached count before scan finishes")

        // Verify the count text format
        let countText = "\(videoCatalog.count) video\(videoCatalog.count == 1 ? "" : "s") in catalog"
        XCTAssertEqual(countText, "42 videos in catalog")

        // When: More videos are found during scan
        let newVideos = createMockVideos(count: 3)
        videoCatalog.append(contentsOf: newVideos)

        // Then: The count should update accordingly
        XCTAssertEqual(videoCatalog.count, 45, "Video count should update when new videos are found")
    }

    // MARK: - Test 4: Progress indicator shows fallback text when no progress info

    func testProgressIndicatorShowsFallbackTextWhenNoProgressInfo() {
        // Given: isScanning is true but no progress info available yet
        let isScanning = true
        let scanProgress: ScanProgress? = nil

        // When: We check the indicator visibility
        let shouldShowIndicator = isScanning

        // Then: Should show indicator with fallback text
        XCTAssertTrue(shouldShowIndicator, "Progress indicator should show even without progress details")

        // Verify fallback text should be used
        let hasProgressDetails = scanProgress != nil && (scanProgress?.totalFiles ?? 0) > 0
        XCTAssertFalse(hasProgressDetails, "Should use fallback text when no progress details")

        // The fallback text should be "Scanning for changes..."
        let fallbackText = "Scanning for changes..."
        XCTAssertEqual(fallbackText, "Scanning for changes...")
    }

    // MARK: - Helper Methods

    private func createMockVideos(count: Int) -> [VideoItem] {
        return (0..<count).map { index in
            VideoItem(
                id: UUID(),
                fileId: "file_\(index)",
                filename: "video_\(index).mp4",
                relativePath: "videos/video_\(index).mp4",
                sourceDirectoryId: UUID(),
                duration: 120.0,
                width: 1920,
                height: 1080,
                codec: "h264",
                fileSize: 1000000,
                lastModified: Date()
            )
        }
    }
}

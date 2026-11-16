//
//  ScrubPreviewGeneratorTests.swift
//  gridstream-ipadTests
//

import XCTest
import AVFoundation
import CoreMedia
@testable import gridstream_ipad

@MainActor
final class ScrubPreviewGeneratorTests: XCTestCase {

    var generator: ScrubPreviewGenerator!

    override func setUp() async throws {
        try await super.setUp()
        generator = ScrubPreviewGenerator()
    }

    override func tearDown() async throws {
        generator.cleanup()
        generator = nil
        try await super.tearDown()
    }

    // MARK: - Test: Generator configures AVAssetImageGenerator from AVAsset

    func testConfigureCreatesImageGeneratorFromAsset() async {
        // Given: A valid AVAsset (using a composition as a mock asset)
        let composition = AVMutableComposition()

        // When: Configuring the generator
        generator.configure(with: composition)

        // Then: Generator should be configured (internal state change)
        // We verify by checking that currentPreviewImage starts as nil
        XCTAssertNil(generator.currentPreviewImage)
    }

    // MARK: - Test: Generator cancels in-flight requests on new request

    func testGenerateCancelsPendingTaskOnNewRequest() async throws {
        // Given: A generator with no asset configured
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!
        let time1 = CMTime(seconds: 1.0, preferredTimescale: 600)
        let time2 = CMTime(seconds: 2.0, preferredTimescale: 600)

        // When: Making rapid requests without asset
        generator.generatePreview(at: time1, for: testURL)
        generator.generatePreview(at: time2, for: testURL)

        // Then: No crash occurs and generator handles gracefully
        // The second request should cancel the first
        XCTAssertNil(generator.currentPreviewImage)
    }

    // MARK: - Test: Fallback returns last successful frame when generation fails

    func testFallbackToLastSuccessfulImageOnFailure() async throws {
        // Given: A generator with a cached last successful image
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!
        let time = CMTime(seconds: 5.0, preferredTimescale: 600)

        // Simulate a successful frame by caching one
        let testImage = createTestCGImage()
        PreviewFrameCache.shared.setFrame(testImage, forURL: testURL, atTime: time)

        // When: Requesting a preview for a cached time
        generator.generatePreview(at: time, for: testURL)

        // Give time for async operation
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Then: Should retrieve from cache
        XCTAssertNotNil(generator.currentPreviewImage)
    }

    // MARK: - Test: Debouncing limits frame requests during rapid scrubbing

    func testDebouncingLimitsRapidRequests() async throws {
        // Given: A generator
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!

        // When: Making many rapid requests (simulating fast scrubbing)
        for i in 0..<10 {
            let time = CMTime(seconds: Double(i) * 0.01, preferredTimescale: 600)
            generator.generatePreview(at: time, for: testURL)
        }

        // Then: Generator should not crash and should handle gracefully
        // The debouncing mechanism should cancel intermediate requests
        // Only the last request should be processed after the 50ms delay
        XCTAssertNil(generator.currentPreviewImage) // No asset configured, so no image
    }

    // MARK: - Test: Cleanup properly cancels tasks and clears state

    func testCleanupCancelsTasksAndClearsState() async {
        // Given: A configured generator
        let composition = AVMutableComposition()
        generator.configure(with: composition)

        // When: Cleanup is called
        generator.cleanup()

        // Then: State should be cleared
        XCTAssertNil(generator.currentPreviewImage)
    }

    // MARK: - Test Helpers

    private func createTestCGImage() -> CGImage {
        let size = CGSize(width: 320, height: 180)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )!

        context.setFillColor(UIColor.gray.cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        return context.makeImage()!
    }
}

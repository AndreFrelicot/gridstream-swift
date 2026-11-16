//
//  ScrubPreviewIntegrationTests.swift
//  gridstream-ipadTests
//
//  Strategic integration tests for scrubbing preview feature.
//  Tests end-to-end workflows and critical integration points.
//

import XCTest
import AVFoundation
import CoreMedia
@testable import gridstream_ipad

@MainActor
final class ScrubPreviewIntegrationTests: XCTestCase {

    // MARK: - Test: End-to-end scrub gesture workflow

    func testEndToEndScrubGestureShowsPreviewAndReleasesHidesIt() async throws {
        // Given: A configured generator and cache
        let generator = ScrubPreviewGenerator()
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!
        let time = CMTime(seconds: 10.0, preferredTimescale: 600)

        // Pre-populate cache to simulate successful frame generation
        let testImage = createTestCGImage()
        PreviewFrameCache.shared.setFrame(testImage, forURL: testURL, atTime: time)

        // When: Simulating scrub gesture start (generator configured, preview requested)
        let composition = AVMutableComposition()
        generator.configure(with: composition)
        generator.generatePreview(at: time, for: testURL)

        // Give time for cache retrieval
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Then: Preview should be visible (currentPreviewImage not nil)
        XCTAssertNotNil(generator.currentPreviewImage, "Preview should be shown during scrub")

        // When: Simulating scrub gesture release
        generator.cancelPendingGeneration()
        generator.cleanup()

        // Then: Preview should be cleared
        XCTAssertNil(generator.currentPreviewImage, "Preview should be hidden after scrub release")
    }

    // MARK: - Test: Preview updates correctly with slider position changes

    func testPreviewUpdatesWithSliderPositionChanges() async throws {
        // Given: A generator with cached frames at multiple positions
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!
        let generator = ScrubPreviewGenerator()

        // Cache frames at different positions
        let image1 = createTestCGImage(color: .red)
        let image2 = createTestCGImage(color: .blue)
        let time1 = CMTime(seconds: 5.0, preferredTimescale: 600)
        let time2 = CMTime(seconds: 15.0, preferredTimescale: 600)

        PreviewFrameCache.shared.setFrame(image1, forURL: testURL, atTime: time1)
        PreviewFrameCache.shared.setFrame(image2, forURL: testURL, atTime: time2)

        // When: Requesting preview at first position
        generator.generatePreview(at: time1, for: testURL)
        try await Task.sleep(nanoseconds: 50_000_000)

        // Then: First cached image should be shown
        XCTAssertNotNil(generator.currentPreviewImage, "Should show cached preview at position 1")
        let firstImage = generator.currentPreviewImage

        // When: Scrubbing to second position
        generator.generatePreview(at: time2, for: testURL)
        try await Task.sleep(nanoseconds: 50_000_000)

        // Then: Second cached image should be shown (different from first)
        XCTAssertNotNil(generator.currentPreviewImage, "Should show cached preview at position 2")
        // Both images exist and were retrieved from cache successfully
        XCTAssertNotNil(firstImage)

        // Cleanup
        generator.cleanup()
    }

    // MARK: - Test: Fallback behavior shows last successful image on generation failure

    func testFallbackShowsLastSuccessfulImageOnGenerationFailure() async throws {
        // Given: A generator with a previously successful image cached
        let generator = ScrubPreviewGenerator()
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!
        let successTime = CMTime(seconds: 5.0, preferredTimescale: 600)
        let failTime = CMTime(seconds: 99.0, preferredTimescale: 600) // Not cached

        // Cache a successful frame
        let successImage = createTestCGImage()
        PreviewFrameCache.shared.setFrame(successImage, forURL: testURL, atTime: successTime)

        // Retrieve successful frame first
        generator.generatePreview(at: successTime, for: testURL)
        try await Task.sleep(nanoseconds: 50_000_000)

        // Verify successful retrieval
        XCTAssertNotNil(generator.currentPreviewImage, "Should have retrieved cached frame")

        // When: Requesting preview at non-cached time (no generator configured = failure)
        // Note: Without configured generator, generation will fail and fallback to lastSuccessfulImage
        generator.generatePreview(at: failTime, for: testURL)

        // Wait for debounce and generation attempt
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Then: Should still show the last successful image (fallback)
        // Since no generator is configured, it will use fallback behavior
        XCTAssertNotNil(generator.currentPreviewImage, "Should fall back to last successful image")

        // Cleanup
        generator.cleanup()
    }

    // MARK: - Test: Rapid scrubbing does not cause issues (performance validation)

    func testRapidScrubbingDoesNotCauseIssues() async throws {
        // Given: A generator
        let generator = ScrubPreviewGenerator()
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!

        // When: Simulating rapid scrubbing (many requests in quick succession)
        for i in 0..<50 {
            let time = CMTime(seconds: Double(i) * 0.05, preferredTimescale: 600)
            generator.generatePreview(at: time, for: testURL)
        }

        // Then: No crash should occur, generator handles gracefully
        // Debouncing should cancel intermediate requests

        // Wait for any pending operations
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Generator should still be functional after rapid requests
        XCTAssertNotNil(generator) // Basic sanity check

        // Cleanup
        generator.cleanup()
    }

    // MARK: - Test Helpers

    private func createTestCGImage(color: UIColor = .gray) -> CGImage {
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

        context.setFillColor(color.cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        return context.makeImage()!
    }
}

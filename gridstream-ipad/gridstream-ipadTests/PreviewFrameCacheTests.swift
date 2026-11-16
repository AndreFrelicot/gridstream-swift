//
//  PreviewFrameCacheTests.swift
//  gridstream-ipadTests
//

import XCTest
import CoreMedia
@testable import gridstream_ipad

@MainActor
final class PreviewFrameCacheTests: XCTestCase {

    func testCacheStoresAndRetrievesCGImageByCompositeKey() async {
        let cache = PreviewFrameCache.shared
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!
        let testTime = CMTime(seconds: 5.0, preferredTimescale: 600)
        let testImage = createTestCGImage()

        cache.setFrame(testImage, forURL: testURL, atTime: testTime)
        let retrievedImage = cache.frame(forURL: testURL, atTime: testTime)

        XCTAssertNotNil(retrievedImage)
    }

    func testCacheReturnsNilForNonExistentKeys() async {
        let cache = PreviewFrameCache.shared
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/nonexistent/stream")!
        let testTime = CMTime(seconds: 99.0, preferredTimescale: 600)

        let retrievedImage = cache.frame(forURL: testURL, atTime: testTime)

        XCTAssertNil(retrievedImage)
    }

    func testCompositeKeyGenerationFromURLAndCMTime() async {
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!
        let testTime = CMTime(seconds: 5.03, preferredTimescale: 600)

        let key = PreviewFrameCache.cacheKey(forURL: testURL, atTime: testTime)

        // Should round to nearest 0.1 seconds (5.0); 5.05 is a tie that rounds up
        XCTAssertTrue(key.contains("5.0"))
        XCTAssertTrue(key.contains(testURL.absoluteString))
    }

    func testCompositeKeyRoundsTimeToNearestTenthSecond() async {
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!

        let time1 = CMTime(seconds: 5.04, preferredTimescale: 600)
        let time2 = CMTime(seconds: 5.06, preferredTimescale: 600)

        let key1 = PreviewFrameCache.cacheKey(forURL: testURL, atTime: time1)
        let key2 = PreviewFrameCache.cacheKey(forURL: testURL, atTime: time2)

        // 5.04 rounds to 5.0, 5.06 rounds to 5.1
        XCTAssertTrue(key1.contains("5.0"))
        XCTAssertTrue(key2.contains("5.1"))
    }

    // MARK: - Test Helpers

    func testFramesAreRecordedUnderTheVideoOfTheirURL() async {
        let cache = PreviewFrameCache()
        let urlA = URL(string: "http://localhost:8080/api/v1/videos/a/stream")!
        let urlB = URL(string: "http://localhost:8080/api/v1/videos/b/stream")!
        cache.registerVideo(id: "a", url: urlA)
        cache.registerVideo(id: "b", url: urlB)
        let image = createTestCGImage()

        // Two tiles scrubbing at once: frames of B must not land under A
        cache.setFrame(image, forURL: urlA, atTime: CMTime(seconds: 4, preferredTimescale: 600))
        cache.setFrame(image, forURL: urlB, atTime: CMTime(seconds: 40, preferredTimescale: 600))
        cache.setFrame(image, forURL: urlA, atTime: CMTime(seconds: 6, preferredTimescale: 600))

        XCTAssertEqual(cache.cachedRanges(forVideoId: "a"), [4...8])
        XCTAssertEqual(cache.cachedRanges(forVideoId: "b"), [40...42])
    }

    func testRangesFollowNewFramesAndServerTimes() async {
        let cache = PreviewFrameCache()
        let url = URL(string: "http://localhost:8080/api/v1/videos/a/stream")!
        cache.registerVideo(id: "a", url: url)
        XCTAssertEqual(cache.cachedRanges(forVideoId: "a"), [])

        cache.setFrame(createTestCGImage(), forURL: url, atTime: CMTime(seconds: 20, preferredTimescale: 600))
        XCTAssertEqual(cache.cachedRanges(forVideoId: "a"), [20...22])

        cache.updateFromServerTimes(videoId: "a", times: [0, 2, 4])
        XCTAssertEqual(cache.cachedRanges(forVideoId: "a"), [0...6])

        cache.clearCachedTimes(for: "a")
        XCTAssertEqual(cache.cachedRanges(forVideoId: "a"), [])
    }

    func testFramesOfAnUnregisteredURLAreNotTracked() async {
        let cache = PreviewFrameCache()
        let url = URL(string: "http://localhost:8080/api/v1/videos/x/stream")!

        cache.setFrame(createTestCGImage(), forURL: url, atTime: CMTime(seconds: 10, preferredTimescale: 600))

        XCTAssertNotNil(cache.frame(forURL: url, atTime: CMTime(seconds: 10, preferredTimescale: 600)))
        XCTAssertEqual(cache.cachedRanges(forVideoId: "x"), [])
    }

    func testSessionTokenDoesNotSplitTheCache() async {
        let cache = PreviewFrameCache()
        let oldTokenURL = URL(string: "http://localhost:8080/api/v1/videos/v/stream?token=old")!
        let newTokenURL = URL(string: "http://localhost:8080/api/v1/videos/v/stream?token=new")!
        let time = CMTime(seconds: 4, preferredTimescale: 600)

        cache.registerVideo(id: "v", url: oldTokenURL)
        cache.setFrame(createTestCGImage(), forURL: newTokenURL, atTime: time)

        XCTAssertNotNil(cache.frame(forURL: oldTokenURL, atTime: time))
        XCTAssertEqual(cache.cachedRanges(forVideoId: "v"), [4...6])
        XCTAssertFalse(PreviewFrameCache.cacheKey(forURL: newTokenURL, atTime: time).contains("token"))
    }

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

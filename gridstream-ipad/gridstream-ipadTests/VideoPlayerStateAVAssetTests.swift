//
//  VideoPlayerStateAVAssetTests.swift
//  gridstream-ipadTests
//

import XCTest
import AVFoundation
@testable import gridstream_ipad

@MainActor
final class VideoPlayerStateAVAssetTests: XCTestCase {

    func testCurrentAssetReturnsAVAssetWhenPlayerItemIsConfigured() async {
        let state = VideoPlayerState()
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!

        state.setupPlayer(url: testURL)

        XCTAssertNotNil(state.currentAsset)
    }

    func testCurrentAssetReturnsNilWhenPlayerNotReady() async {
        let state = VideoPlayerState()

        XCTAssertNil(state.currentAsset)
    }

    func testVideoURLReturnsCurrentURLWhenConfigured() async {
        let state = VideoPlayerState()
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!

        state.setupPlayer(url: testURL)

        XCTAssertEqual(state.videoURL, testURL)
    }

    func testVideoURLReturnsNilWhenNotConfigured() async {
        let state = VideoPlayerState()

        XCTAssertNil(state.videoURL)
    }
}

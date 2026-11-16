//
//  VideoURLBuilderTests.swift
//  gridstream-ipadTests
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class VideoURLBuilderTests: XCTestCase {

    func testBuildStreamURLFromValidServer() async {
        let server = DiscoveredServer(name: "Test Server", hostname: "localhost", port: 8080)
        let builder = VideoURLBuilder(server: server)

        let url = builder.buildStreamURL(for: "video-123")

        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, "http://localhost:8080/api/v1/videos/video-123/stream?stats=client")
    }

    func testStaticBuildStreamURLFromServerURL() async {
        let serverURL = URL(string: "http://192.168.1.100:8080")!

        let url = VideoURLBuilder.buildStreamURL(from: serverURL, videoId: "test-video")

        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, "http://192.168.1.100:8080/api/v1/videos/test-video/stream?stats=client")
    }

    func testBuildStreamURLWithSpecialCharactersInVideoId() async {
        let serverURL = URL(string: "http://localhost:8080")!

        let url = VideoURLBuilder.buildStreamURL(from: serverURL, videoId: "video_with-dash")

        XCTAssertNotNil(url)
        XCTAssertTrue(url?.absoluteString.contains("video_with-dash") ?? false)
    }
}

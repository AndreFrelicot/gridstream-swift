//
//  GlobalPlaybackControlsTests.swift
//  gridstream-ipadTests
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class GlobalPlaybackControlsTests: XCTestCase {

    func testHasActivePlayersReturnsTrueWhenPlayersRegistered() async {
        let manager = GlobalPlaybackManager()
        let playerState = VideoPlayerState()

        XCTAssertFalse(manager.hasActivePlayers)

        manager.register(playerState)

        XCTAssertTrue(manager.hasActivePlayers)
    }

    func testHasActivePlayersReturnsFalseWhenNoPlayers() async {
        let manager = GlobalPlaybackManager()

        XCTAssertFalse(manager.hasActivePlayers)
    }

    func testPauseAllCallsPauseOnAllRegisteredPlayers() async {
        let manager = GlobalPlaybackManager()
        let playerState1 = VideoPlayerState()
        let playerState2 = VideoPlayerState()
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!

        playerState1.setupPlayer(url: testURL)
        playerState2.setupPlayer(url: testURL)
        playerState1.play()
        playerState2.play()

        manager.register(playerState1)
        manager.register(playerState2)

        XCTAssertTrue(playerState1.isPlaying)
        XCTAssertTrue(playerState2.isPlaying)

        manager.pauseAll()

        XCTAssertFalse(playerState1.isPlaying)
        XCTAssertFalse(playerState2.isPlaying)
    }

    func testPlayAllCallsPlayOnAllRegisteredPlayers() async {
        let manager = GlobalPlaybackManager()
        let playerState1 = VideoPlayerState()
        let playerState2 = VideoPlayerState()
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!

        playerState1.setupPlayer(url: testURL)
        playerState2.setupPlayer(url: testURL)

        manager.register(playerState1)
        manager.register(playerState2)

        XCTAssertFalse(playerState1.isPlaying)
        XCTAssertFalse(playerState2.isPlaying)

        manager.playAll()

        XCTAssertTrue(playerState1.isPlaying)
        XCTAssertTrue(playerState2.isPlaying)
    }
}

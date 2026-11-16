//
//  PlayerRegistrationTests.swift
//  gridstream-ipadTests
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class PlayerRegistrationTests: XCTestCase {

    func testVideoTileViewRegistersPlayerOnAppear() async {
        // Given a GlobalPlaybackManager and VideoPlayerState
        let manager = GlobalPlaybackManager()
        let playerState = VideoPlayerState()

        // When player is registered (simulating onAppear)
        manager.register(playerState)

        // Then manager should have the player in registry
        XCTAssertTrue(manager.hasActivePlayers)
        XCTAssertNotNil(manager.activePlayers[playerState.id])
    }

    func testVideoTileViewUnregistersPlayerOnDisappear() async {
        // Given a registered player
        let manager = GlobalPlaybackManager()
        let playerState = VideoPlayerState()
        manager.register(playerState)

        // When player is unregistered (simulating onDisappear)
        manager.unregister(playerState)

        // Then manager should not have the player in registry
        XCTAssertFalse(manager.hasActivePlayers)
        XCTAssertNil(manager.activePlayers[playerState.id])
    }

    func testRegistrationPersistsAcrossTileChanges() async {
        // Given a manager with multiple registered players
        let manager = GlobalPlaybackManager()
        let playerState1 = VideoPlayerState()
        let playerState2 = VideoPlayerState()

        manager.register(playerState1)
        manager.register(playerState2)

        // When one player is unregistered (tile removed/changed)
        manager.unregister(playerState1)

        // Then the other player should still be registered
        XCTAssertTrue(manager.hasActivePlayers)
        XCTAssertEqual(manager.activePlayers.count, 1)
        XCTAssertNotNil(manager.activePlayers[playerState2.id])
        XCTAssertNil(manager.activePlayers[playerState1.id])
    }

    func testSharedPlayerPoolReleasesRemovedTilePlayers() async {
        let pool = SharedPlayerPool()
        let player = pool.currentPlayer(forTile: 0)
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!

        player.setupPlayer(url: testURL, fileId: "test-file", autoplay: false)
        XCTAssertNotNil(player.player)

        pool.removePlayers(forTile: 0)

        XCTAssertNil(player.player)
        XCTAssertTrue(pool.activeTileIndices.isEmpty)
    }

    func testSharedPlayerPoolCleansDroppedPlayersWhenReindexing() async {
        let pool = SharedPlayerPool()
        let droppedPlayer = pool.currentPlayer(forTile: 0)
        let retainedPlayer = pool.currentPlayer(forTile: 1)
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!

        droppedPlayer.setupPlayer(url: testURL, fileId: "dropped", autoplay: false)
        retainedPlayer.setupPlayer(url: testURL, fileId: "retained", autoplay: false)

        pool.reindexPlayers(newIndices: [1: 0])

        XCTAssertNil(droppedPlayer.player)
        XCTAssertNotNil(retainedPlayer.player)
        XCTAssertEqual(retainedPlayer.tileIndex, 0)
        XCTAssertEqual(pool.activeTileIndices, [0])
    }
}

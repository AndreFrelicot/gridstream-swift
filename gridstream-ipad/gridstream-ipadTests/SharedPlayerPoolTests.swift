//
//  SharedPlayerPoolTests.swift
//  gridstream-ipadTests
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class SharedPlayerPoolTests: XCTestCase {

    private func makePool() -> (SharedPlayerPool, GlobalPlaybackManager, TileAudioStateManager) {
        let audio = TileAudioStateManager()
        let manager = GlobalPlaybackManager(audioStates: audio)
        return (SharedPlayerPool(playbackManager: manager), manager, audio)
    }

    func testRemovePlayersUnregistersThem() async {
        let (pool, manager, _) = makePool()
        let current = pool.currentPlayer(forTile: 0)
        let kept = pool.currentPlayer(forTile: 1)
        manager.register(current)
        manager.register(kept)

        pool.removePlayers(forTile: 0)

        XCTAssertNil(manager.activePlayers[current.id], "Play All must not reach a removed tile")
        XCTAssertNotNil(manager.activePlayers[kept.id])
    }

    func testRemoveAllPlayersUnregistersEveryone() async {
        let (pool, manager, _) = makePool()
        for index in 0..<3 {
            manager.register(pool.currentPlayer(forTile: index))
        }

        pool.removeAllPlayers()

        XCTAssertFalse(manager.hasActivePlayers)
    }

    func testReindexUnregistersDroppedPlayersAndRetargetsKeptOnes() async {
        let (pool, manager, _) = makePool()
        let dropped = pool.currentPlayer(forTile: 0)
        let kept = pool.currentPlayer(forTile: 1)
        let keptNext = pool.nextPlayer(forTile: 1)
        manager.register(dropped)
        manager.register(kept)

        pool.reindexPlayers(newIndices: [1: 0])

        XCTAssertNil(manager.activePlayers[dropped.id])
        XCTAssertNotNil(manager.activePlayers[kept.id])
        XCTAssertEqual(kept.tileIndex, 0)
        XCTAssertEqual(keptNext.tileIndex, 0, "Adjacent players follow their tile")
        XCTAssertTrue(pool.currentPlayer(forTile: 0) === kept)
    }

    func testSoloOnARemovedTileDoesNotSilenceTheOthers() async {
        let (pool, manager, _) = makePool()
        let soloed = pool.currentPlayer(forTile: 0)
        let other = pool.currentPlayer(forTile: 1)
        manager.register(soloed)
        manager.register(other)
        manager.setSolo(true, for: soloed)
        XCTAssertTrue(other.isAudioSuppressed)

        pool.removePlayers(forTile: 0)

        XCTAssertFalse(other.isAudioSuppressed)
    }

    func testAdjacentPlayersCarryTheTileIndexFromCreation() async {
        let (pool, _, _) = makePool()

        XCTAssertEqual(pool.previousPlayer(forTile: 3).tileIndex, 3)
        XCTAssertEqual(pool.nextPlayer(forTile: 3).tileIndex, 3)
    }
}

//
//  GlobalPlaybackManagerTests.swift
//  gridstream-ipadTests
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class GlobalPlaybackManagerTests: XCTestCase {

    func testRegisterAddsPlayerToRegistry() async {
        let manager = GlobalPlaybackManager()
        let playerState = VideoPlayerState()

        manager.register(playerState)

        XCTAssertTrue(manager.hasActivePlayers)
        XCTAssertEqual(manager.activePlayers.count, 1)
        XCTAssertNotNil(manager.activePlayers[playerState.id])
    }

    func testUnregisterRemovesPlayerFromRegistry() async {
        let manager = GlobalPlaybackManager()
        let playerState = VideoPlayerState()

        manager.register(playerState)
        manager.unregister(playerState)

        XCTAssertFalse(manager.hasActivePlayers)
        XCTAssertEqual(manager.activePlayers.count, 0)
        XCTAssertNil(manager.activePlayers[playerState.id])
    }

    func testPauseAllPausesAllRegisteredPlayers() async {
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

        manager.pauseAll()

        XCTAssertFalse(playerState1.isPlaying)
        XCTAssertFalse(playerState2.isPlaying)
    }

    func testPlayAllResumesAllRegisteredPlayers() async {
        let manager = GlobalPlaybackManager()
        let playerState1 = VideoPlayerState()
        let playerState2 = VideoPlayerState()
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!

        playerState1.setupPlayer(url: testURL)
        playerState2.setupPlayer(url: testURL)

        manager.register(playerState1)
        manager.register(playerState2)

        manager.playAll()

        XCTAssertTrue(playerState1.isPlaying)
        XCTAssertTrue(playerState2.isPlaying)
    }

    func testSuperSoloRestoresPreviousSoloPlayer() async {
        let manager = GlobalPlaybackManager()
        let soloPlayer = VideoPlayerState()
        let fullscreenPlayer = VideoPlayerState()
        let otherPlayer = VideoPlayerState()

        manager.register(soloPlayer)
        manager.register(fullscreenPlayer)
        manager.register(otherPlayer)

        manager.activateSolo(for: soloPlayer)
        XCTAssertTrue(manager.isSolo(soloPlayer.id))

        manager.activateSuperSolo(for: fullscreenPlayer)
        XCTAssertTrue(manager.isSuperSolo(fullscreenPlayer.id))

        manager.deactivateSuperSolo()

        XCTAssertTrue(manager.isSolo(soloPlayer.id))
        XCTAssertFalse(manager.isSuperSolo(fullscreenPlayer.id))
    }

    // MARK: - Tile-owned solo and mute

    private func makePlayer(tile: Int) -> VideoPlayerState {
        let player = VideoPlayerState()
        player.tileIndex = tile
        return player
    }

    func testSoloSurvivesSwapToANewPlayerOnTheSameTile() async {
        let audio = TileAudioStateManager()
        let manager = GlobalPlaybackManager(audioStates: audio)
        let soloed = makePlayer(tile: 0)
        let other = makePlayer(tile: 1)
        manager.register(soloed)
        manager.register(other)

        manager.setSolo(true, for: soloed)
        XCTAssertTrue(other.isAudioSuppressed)

        // Swipe / video change: the tile gets a different player object
        let replacement = makePlayer(tile: 0)
        manager.unregister(soloed)
        manager.register(replacement)

        XCTAssertTrue(audio.isSolo(for: 0), "The tile keeps its solo")
        XCTAssertTrue(manager.isSolo(replacement.id), "The incoming player takes the solo back")
        XCTAssertTrue(other.isAudioSuppressed, "Other tiles stay silenced")
        XCTAssertFalse(replacement.isAudioSuppressed)
    }

    func testSoloIsExclusiveAcrossTiles() async {
        let audio = TileAudioStateManager()
        let manager = GlobalPlaybackManager(audioStates: audio)
        let first = makePlayer(tile: 0)
        let second = makePlayer(tile: 1)
        manager.register(first)
        manager.register(second)

        manager.setSolo(true, for: first)
        manager.setSolo(true, for: second)

        XCTAssertFalse(audio.isSolo(for: 0), "Soloing another tile clears this tile's solo")
        XCTAssertTrue(audio.isSolo(for: 1))
        XCTAssertTrue(manager.isSolo(second.id))
        XCTAssertTrue(first.isAudioSuppressed)
    }

    func testTurningOffASoloThatWasReplacedKeepsTheNewSolo() async {
        let audio = TileAudioStateManager()
        let manager = GlobalPlaybackManager(audioStates: audio)
        let first = makePlayer(tile: 0)
        let second = makePlayer(tile: 1)
        manager.register(first)
        manager.register(second)

        manager.setSolo(true, for: first)
        manager.setSolo(true, for: second)
        manager.deactivateSolo(for: first)

        XCTAssertTrue(manager.isSolo(second.id), "deactivateSolo(for:) only clears its own solo")
        XCTAssertTrue(first.isAudioSuppressed)
    }

    func testExclusiveSoloMutesOtherTilesThroughTheirAudioState() async {
        let audio = TileAudioStateManager()
        let manager = GlobalPlaybackManager(audioStates: audio)
        let soloed = makePlayer(tile: 0)
        let other = makePlayer(tile: 1)
        manager.register(soloed)
        manager.register(other)

        manager.exclusiveSolo(for: soloed)

        XCTAssertTrue(audio.isMuted(for: 1), "The muted tile's button and persistence see the mute")
        XCTAssertTrue(other.isMuted)
        XCTAssertFalse(audio.isMuted(for: 0))
        XCTAssertTrue(audio.isSolo(for: 0))

        // Leaving solo does not give the muted tile its sound back
        manager.setSolo(false, for: soloed)
        XCTAssertTrue(other.isSilenced)
        XCTAssertFalse(soloed.isSilenced)
    }

    func testUnregisteringTheSoloPlayerReleasesTheOthers() async {
        let audio = TileAudioStateManager()
        let manager = GlobalPlaybackManager(audioStates: audio)
        let soloed = makePlayer(tile: 0)
        let other = makePlayer(tile: 1)
        manager.register(soloed)
        manager.register(other)
        manager.setSolo(true, for: soloed)

        manager.unregister(soloed)

        XCTAssertNil(manager.soloPlayerID)
        XCTAssertFalse(other.isAudioSuppressed, "A player that left must not keep the rest silent")
        XCTAssertFalse(soloed.isAudioSuppressed)
    }

    func testMuteIsNotClearedBySolo() async {
        let audio = TileAudioStateManager()
        let manager = GlobalPlaybackManager(audioStates: audio)
        let muted = makePlayer(tile: 0)
        manager.register(muted)
        muted.setMuted(true)

        manager.setSolo(true, for: muted)
        manager.setSolo(false, for: muted)

        XCTAssertTrue(muted.isMuted)
        XCTAssertTrue(muted.isSilenced)
    }
}

//
//  TileEndActionTests.swift
//  gridstream-ipadTests
//

import XCTest
import SwiftData
@testable import gridstream_ipad

@MainActor
final class TileEndActionTests: XCTestCase {

    private var savedEndActions: Any?
    private var savedEndActionsVersion: Any?

    override func setUp() async throws {
        savedEndActions = UserDefaults.standard.object(forKey: GridState.endActionsDefaultsKey)
        savedEndActionsVersion = UserDefaults.standard.object(forKey: GridState.endActionsDefaultsVersionKey)
        UserDefaults.standard.removeObject(forKey: GridState.endActionsDefaultsKey)
        UserDefaults.standard.removeObject(forKey: GridState.endActionsDefaultsVersionKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedEndActions, forKey: GridState.endActionsDefaultsKey)
        UserDefaults.standard.set(savedEndActionsVersion, forKey: GridState.endActionsDefaultsVersionKey)
    }

    // MARK: - Next video in a list

    func testNextVideoFollowsListOrder() async {
        XCTAssertEqual(TileEndAction.nextVideoId(after: "b", in: ["a", "b", "c"]), "c")
    }

    func testNextVideoWrapsAroundAtTheEnd() async {
        XCTAssertEqual(TileEndAction.nextVideoId(after: "c", in: ["a", "b", "c"]), "a")
    }

    func testNextVideoStartsTheListWhenCurrentIsNotInIt() async {
        XCTAssertEqual(TileEndAction.nextVideoId(after: "z", in: ["a", "b"]), "a")
        XCTAssertEqual(TileEndAction.nextVideoId(after: nil, in: ["a", "b"]), "a")
    }

    func testNoNextVideoWhenNothingElseToPlay() async {
        XCTAssertNil(TileEndAction.nextVideoId(after: "a", in: []))
        XCTAssertNil(TileEndAction.nextVideoId(after: "a", in: ["a"]))
    }

    // MARK: - Per-tile setting

    func testTilesStopByDefault() async {
        let state = GridState()
        state.setTileCount(2)

        XCTAssertEqual(state.endAction(at: 0), .stop)
        XCTAssertEqual(state.endAction(at: 1), .stop)
        XCTAssertEqual(state.endAction(at: 5), .stop, "An invalid index stops")
    }

    func testDemoClipsLoopByDefaultAndServerClipsStop() async {
        let state = GridState()
        state.setTileCount(2)
        state.setVideoURL(DemoMode.serverURL.appendingPathComponent("api/v1/videos/a/stream"), videoId: "a", at: 0)
        state.setVideoURL(URL(string: "http://studio.local:8080/api/v1/videos/b/stream")!, videoId: "b", at: 1)

        XCTAssertEqual(state.endAction(at: 0), .loop)
        XCTAssertEqual(state.endAction(at: 1), .stop)
        state.addTile()
        state.setVideoURL(DemoMode.serverURL.appendingPathComponent("api/v1/videos/c/stream"), videoId: "c", at: 2)
        XCTAssertEqual(state.endAction(at: 2), .loop)
    }

    func testChangingDemoClipsPreservesExplicitEndAction() async {
        let state = GridState()
        state.setVideoURL(DemoMode.serverURL.appendingPathComponent("api/v1/videos/a/stream"), videoId: "a", at: 0)
        state.setEndAction(.stop, at: 0)
        state.setVideoURL(DemoMode.serverURL.appendingPathComponent("api/v1/videos/b/stream"), videoId: "b", at: 0)
        XCTAssertEqual(state.endAction(at: 0), .stop)
    }

    func testDemoDefaultsAndExplicitChoicesSurviveRestoration() async throws {
        let schema = Schema([LayoutState.self, TileLayout.self, PiPPositionState.self, PiPLayoutEntry.self, SourcePreset.self, TileAudioPersistedState.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let service = LayoutPersistenceService(modelContext: container.mainContext)
        let state = GridState()
        state.connectPersistence(service)
        state.setTileCount(3)
        state.setEndAction(.stop, at: 0)
        state.setEndAction(.shuffle, at: 1)
        state.flushPendingSave()

        let restored = GridState()
        restored.connectPersistence(service)
        for index in restored.tiles.indices {
            restored.setVideoURL(DemoMode.serverURL.appendingPathComponent("api/v1/videos/clip-\(index)/stream"), videoId: "clip-\(index)", at: index)
        }
        XCTAssertEqual(restored.endAction(at: 0), .stop)
        XCTAssertEqual(restored.endAction(at: 1), .shuffle)
        XCTAssertEqual(restored.endAction(at: 2), .loop)
    }

    func testLegacyStopDefaultsUseDemoLoopWhileExplicitShuffleIsKept() async throws {
        let schema = Schema([LayoutState.self, TileLayout.self, PiPPositionState.self, PiPLayoutEntry.self, SourcePreset.self, TileAudioPersistedState.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let service = LayoutPersistenceService(modelContext: container.mainContext)
        service.currentLayout.tileLayouts.append(TileLayout(index: 1))
        UserDefaults.standard.set(["stop", "shuffle"], forKey: GridState.endActionsDefaultsKey)

        let state = GridState()
        state.connectPersistence(service)
        for index in state.tiles.indices {
            state.setVideoURL(DemoMode.serverURL.appendingPathComponent("api/v1/videos/clip-\(index)/stream"), videoId: "clip-\(index)", at: index)
        }
        XCTAssertEqual(state.endAction(at: 0), .loop)
        XCTAssertEqual(state.endAction(at: 1), .shuffle)
    }

    func testEndActionIsPerTile() async {
        let state = GridState()
        state.setTileCount(3)

        state.setEndAction(.shuffle, at: 1)

        XCTAssertEqual(state.endAction(at: 0), .stop)
        XCTAssertEqual(state.endAction(at: 1), .shuffle)
        XCTAssertEqual(state.endAction(at: 2), .stop)
    }

    func testEndActionFollowsTheTileWhenTilesAreReindexed() async {
        let state = GridState()
        state.setTileCount(3)
        state.setEndAction(.loop, at: 2)

        state.removeTile(at: 0)

        XCTAssertEqual(state.endAction(at: 1), .loop)
        XCTAssertEqual(state.endAction(at: 0), .stop)
    }

    // MARK: - End of playback routing

    private func makePool() -> SharedPlayerPool {
        let audio = TileAudioStateManager()
        return SharedPlayerPool(playbackManager: GlobalPlaybackManager(audioStates: audio))
    }

    func testCurrentPlayerEndIsReportedForItsTile() async {
        let pool = makePool()
        var endedTiles: [Int] = []
        pool.onTilePlaybackEnded = { endedTiles.append($0) }

        pool.currentPlayer(forTile: 2).onPlaybackEnded?()

        XCTAssertEqual(endedTiles, [2])
    }

    func testAdjacentPlayerEndIsIgnored() async {
        let pool = makePool()
        var endedTiles: [Int] = []
        pool.onTilePlaybackEnded = { endedTiles.append($0) }
        _ = pool.currentPlayer(forTile: 0)

        pool.nextPlayer(forTile: 0).onPlaybackEnded?()

        XCTAssertEqual(endedTiles, [], "A preloaded swipe player is not the tile's video")
    }

    func testPromotedPlayerReportsItsNewRole() async {
        let pool = makePool()
        var endedTiles: [Int] = []
        pool.onTilePlaybackEnded = { endedTiles.append($0) }
        let oldCurrent = pool.currentPlayer(forTile: 1)
        let next = pool.nextPlayer(forTile: 1)

        pool.swapForForwardNavigation(tileIndex: 1)
        oldCurrent.onPlaybackEnded?()
        next.onPlaybackEnded?()

        XCTAssertEqual(endedTiles, [1], "Only the player now current on tile 1 counts")
    }

    func testReindexedPlayerReportsItsNewTile() async {
        let pool = makePool()
        var endedTiles: [Int] = []
        pool.onTilePlaybackEnded = { endedTiles.append($0) }
        let player = pool.currentPlayer(forTile: 2)

        pool.reindexPlayers(newIndices: [2: 1])
        player.onPlaybackEnded?()

        XCTAssertEqual(endedTiles, [1])
    }
}

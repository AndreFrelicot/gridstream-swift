//
//  LayoutPersistenceTests.swift
//  gridstream-ipadTests
//

import XCTest
import SwiftData
@testable import gridstream_ipad

@MainActor
final class LayoutPersistenceTests: XCTestCase {

    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([LayoutState.self, TileLayout.self, PiPPositionState.self, PiPLayoutEntry.self, SourcePreset.self, TileAudioPersistedState.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try! ModelContainer(for: schema, configurations: [configuration])
        modelContext = ModelContext(modelContainer)
    }

    override func tearDown() async throws {
        modelContainer = nil
        modelContext = nil
        try await super.tearDown()
    }

    // MARK: - LayoutState Initialization Tests

    func testLayoutStateInitializationWithDefaults() async {
        let layoutState = LayoutState()

        XCTAssertNotNil(layoutState.id)
        XCTAssertEqual(layoutState.orientation, .horizontal)
        XCTAssertNil(layoutState.presetIdentifier)
        XCTAssertTrue(layoutState.tileLayouts.isEmpty)
    }

    // MARK: - TileLayout Size Ratio Tests

    func testTileLayoutStoresSizeRatios() async {
        let tileLayout = TileLayout(index: 0, widthRatio: 0.6, heightRatio: 0.4)

        XCTAssertEqual(tileLayout.index, 0)
        XCTAssertEqual(tileLayout.widthRatio, 0.6, accuracy: 0.001)
        XCTAssertEqual(tileLayout.heightRatio, 0.4, accuracy: 0.001)
    }

    func testTileLayoutDefaultsToEqualSizing() async {
        let tileLayout = TileLayout(index: 0)

        XCTAssertEqual(tileLayout.widthRatio, 0.5, accuracy: 0.001)
        XCTAssertEqual(tileLayout.heightRatio, 0.5, accuracy: 0.001)
    }

    // MARK: - Orientation Mode Tests

    func testLayoutOrientationEncodingDecoding() async {
        let horizontalOrientation = LayoutOrientation.horizontal
        let verticalOrientation = LayoutOrientation.vertical

        XCTAssertEqual(horizontalOrientation.rawValue, "horizontal")
        XCTAssertEqual(verticalOrientation.rawValue, "vertical")

        XCTAssertEqual(LayoutOrientation(rawValue: "horizontal"), .horizontal)
        XCTAssertEqual(LayoutOrientation(rawValue: "vertical"), .vertical)
    }

    // MARK: - Preset Identifier Tests

    func testLayoutStateStoresPresetIdentifier() async {
        let layoutState = LayoutState()
        layoutState.presetIdentifier = "onePlusTwo"

        XCTAssertEqual(layoutState.presetIdentifier, "onePlusTwo")
    }

    // MARK: - Relationship Tests

    func testLayoutStateAndTileLayoutRelationship() async {
        let layoutState = LayoutState()
        let tileLayout1 = TileLayout(index: 0, widthRatio: 0.5, heightRatio: 1.0)
        let tileLayout2 = TileLayout(index: 1, widthRatio: 0.5, heightRatio: 1.0)

        layoutState.tileLayouts = [tileLayout1, tileLayout2]

        XCTAssertEqual(layoutState.tileLayouts.count, 2)
        XCTAssertEqual(layoutState.tileLayouts[0].widthRatio, 0.5, accuracy: 0.001)
        XCTAssertEqual(layoutState.tileLayouts[1].index, 1)
    }

    // MARK: - Persistence Service Tests

    func testLayoutPersistenceServiceSaveAndLoad() async {
        let service = LayoutPersistenceService(modelContext: modelContext)

        service.currentLayout.orientation = .vertical
        service.currentLayout.presetIdentifier = "twoPlusOne"
        service.currentLayout.tileLayouts = [
            TileLayout(index: 0, widthRatio: 0.7, heightRatio: 1.0),
            TileLayout(index: 1, widthRatio: 0.3, heightRatio: 0.5),
            TileLayout(index: 2, widthRatio: 0.3, heightRatio: 0.5)
        ]

        service.save()

        let newService = LayoutPersistenceService(modelContext: modelContext)
        newService.load()

        XCTAssertEqual(newService.currentLayout.orientation, .vertical)
        XCTAssertEqual(newService.currentLayout.presetIdentifier, "twoPlusOne")
        XCTAssertEqual(newService.currentLayout.tileLayouts.count, 3)
    }

    func testGridStateFlushPendingSavePersistsImmediately() async {
        let service = LayoutPersistenceService(modelContext: modelContext)
        let state = GridState()
        state.connectPersistence(service)

        state.setTileCount(4)
        state.flushPendingSave()

        let newService = LayoutPersistenceService(modelContext: modelContext)
        newService.load()

        XCTAssertEqual(newService.currentLayout.tileLayouts.count, 4)
    }

    func testPipLayoutLookupIgnoresInvalidIndicesAndKeepsFirstDuplicate() async {
        let layoutState = LayoutState()
        let first = PiPLayoutEntry(pipTileIndex: 1, fullscreenTileIndex: 0, positionX: 10, positionY: 10)
        let duplicate = PiPLayoutEntry(pipTileIndex: 1, fullscreenTileIndex: 0, positionX: 20, positionY: 20)
        let invalid = PiPLayoutEntry(pipTileIndex: -1, fullscreenTileIndex: 0, positionX: 30, positionY: 30)

        layoutState.pipLayouts = [first, duplicate, invalid]

        let layouts = layoutState.pipLayouts(forFullscreen: 0)

        XCTAssertEqual(layouts.count, 1)
        XCTAssertTrue(layouts[1] === first)
    }

    func testPipLayoutReindexDropsInvalidEntries() async {
        let layoutState = LayoutState()
        layoutState.pipLayouts = [
            PiPLayoutEntry(pipTileIndex: 0, fullscreenTileIndex: 1, positionX: 0, positionY: 0),
            PiPLayoutEntry(pipTileIndex: 2, fullscreenTileIndex: 0, positionX: 0, positionY: 0),
            PiPLayoutEntry(pipTileIndex: 3, fullscreenTileIndex: 1, positionX: 0, positionY: 0)
        ]

        layoutState.reindexPipLayouts(fromIndex: 1)

        XCTAssertFalse(layoutState.pipLayouts.contains { $0.pipTileIndex < 0 || $0.fullscreenTileIndex < 0 })
        XCTAssertFalse(layoutState.pipLayouts.contains { $0.pipTileIndex == $0.fullscreenTileIndex })
    }

    // MARK: - Content Restoration Tests

    @MainActor
    func testTileLayoutPersistsContentFields() async throws {
        let service = LayoutPersistenceService(modelContext: modelContext)
        let state = GridState()
        state.connectPersistence(service)
        state.setTileCount(2)

        let fakeURL = URL(string: "http://example.local:8080/api/v1/videos/abc/stream")!
        let smartId = UUID()
        state.setVideoURL(fakeURL, videoId: "file-abc", at: 0)
        state.setSmartList(smartId, at: 1)
        state.flushPendingSave()

        // Read back via a fresh service against the same context.
        let fresh = LayoutPersistenceService(modelContext: modelContext)
        let layouts = fresh.currentLayout.tileLayouts.sorted { $0.index < $1.index }
        XCTAssertEqual(layouts.count, 2)
        XCTAssertEqual(layouts[0].videoFileId, "file-abc")
        XCTAssertEqual(layouts[1].smartListId, smartId)
        XCTAssertNil(layouts[0].smartListId)
        XCTAssertNil(layouts[1].videoFileId)
    }

    @MainActor
    func testTileAudioPersistedStateRoundTrip() async throws {
        let layout = TileLayout(index: 3)
        layout.audioState = TileAudioPersistedState(
            tileIndex: 3,
            isMuted: true,
            isSolo: false,
            isVolumeOverrideActive: true,
            overrideVolume: 0.42
        )
        let layoutState = LayoutState()
        layoutState.tileLayouts = [layout]
        modelContext.insert(layoutState)
        try modelContext.save()

        let fetched = try modelContext.fetch(FetchDescriptor<LayoutState>())
        XCTAssertEqual(fetched.count, 1)
        let audio = fetched[0].tileLayouts.first?.audioState
        XCTAssertNotNil(audio)
        XCTAssertEqual(audio?.tileIndex, 3)
        XCTAssertEqual(audio?.isMuted, true)
        XCTAssertEqual(audio?.isSolo, false)
        XCTAssertEqual(audio?.isVolumeOverrideActive, true)
        XCTAssertEqual(audio?.overrideVolume ?? 0, 0.42, accuracy: 0.001)
    }

    @MainActor
    func testConnectPersistenceHydratesContentFromLayoutState() async throws {
        // Seed the store with a layout that has content saved.
        let layout = TileLayout(index: 0)
        layout.videoFileId = "persisted-file-id"
        layout.playbackTime = 12.5
        layout.smartListId = UUID()
        layout.audioState = TileAudioPersistedState(
            tileIndex: 0,
            isMuted: true,
            isSolo: false,
            isVolumeOverrideActive: false,
            overrideVolume: 1.0
        )
        let layoutState = LayoutState()
        layoutState.tileLayouts = [layout]
        modelContext.insert(layoutState)
        try modelContext.save()

        let service = LayoutPersistenceService(modelContext: modelContext)
        let state = GridState()
        state.connectPersistence(service)

        XCTAssertEqual(state.tiles[0].videoId, "persisted-file-id")
        XCTAssertEqual(state.tiles[0].smartListId, layout.smartListId)
        XCTAssertNil(state.tiles[0].videoURL, "URL must remain nil until phase 2 restore rebuilds it")
        XCTAssertTrue(state.hasPendingRestores)
        XCTAssertEqual(state.tilesPendingRestore, [0])
        XCTAssertTrue(TileAudioStateManager.shared.isMuted(for: 0))

        // The pending flag is consumed exactly once.
        XCTAssertTrue(state.consumePendingRestoreFlag(at: 0))
        XCTAssertFalse(state.consumePendingRestoreFlag(at: 0))
    }

    @MainActor
    func testRestoreSkipsTilesWithoutFileId() async throws {
        let layoutWithFile = TileLayout(index: 0)
        layoutWithFile.videoFileId = "real-file"
        let layoutEmpty = TileLayout(index: 1)
        let layoutState = LayoutState()
        layoutState.tileLayouts = [layoutWithFile, layoutEmpty]
        modelContext.insert(layoutState)
        try modelContext.save()

        let service = LayoutPersistenceService(modelContext: modelContext)
        let state = GridState()
        state.connectPersistence(service)

        XCTAssertEqual(state.tilesPendingRestore, [0])
        XCTAssertNil(state.persistedRestoreInfo(forTile: 1))
        let info = state.persistedRestoreInfo(forTile: 0)
        XCTAssertEqual(info?.fileId, "real-file")
    }

    @MainActor
    private func connectStateWithPendingRestores(fileIds: [String]) throws -> GridState {
        let layoutState = LayoutState()
        layoutState.tileLayouts = fileIds.enumerated().map { index, fileId in
            let layout = TileLayout(index: index)
            layout.videoFileId = fileId
            return layout
        }
        modelContext.insert(layoutState)
        try modelContext.save()

        let state = GridState()
        state.connectPersistence(LayoutPersistenceService(modelContext: modelContext))
        return state
    }

    @MainActor
    func testRemovingATileShiftsPendingRestoresWithTheirTiles() async throws {
        let state = try connectStateWithPendingRestores(fileIds: ["file-0", "file-1", "file-2"])
        XCTAssertEqual(state.tilesPendingRestore, [0, 1, 2])

        state.removeTile(at: 1)

        XCTAssertEqual(state.tilesPendingRestore, [0, 1])
        XCTAssertEqual(state.tiles[1].videoId, "file-2")
        XCTAssertTrue(state.consumePendingRestoreFlag(at: 1), "The deferred autoplay follows file-2 to its new index")
    }

    @MainActor
    func testShrinkingTheGridDropsPendingRestoresOfRemovedTiles() async throws {
        let state = try connectStateWithPendingRestores(fileIds: ["file-0", "file-1", "file-2"])

        state.setTileCount(1)

        XCTAssertEqual(state.tilesPendingRestore, [0])
    }

    @MainActor
    func testCaptureContentSnapshotPersistsAudioAndContent() async throws {
        let service = LayoutPersistenceService(modelContext: modelContext)
        let state = GridState()
        state.connectPersistence(service)
        state.setTileCount(2)

        let url = URL(string: "http://example.local:8080/api/v1/videos/x/stream")!
        state.setVideoURL(url, videoId: "fileX", at: 0)
        TileAudioStateManager.shared.setMuted(true, for: 0)
        TileAudioStateManager.shared.setVolumeOverride(active: true, level: 0.7, for: 0)

        let pool = SharedPlayerPool()
        // Note: we don't drive an AVPlayer here; the playerPool branch is exercised
        // via hasCurrentPlayer/currentPlayer in the snapshot routine but the test
        // is mainly about persisting content + audio fields.
        GridSidecarStateCoordinator.captureContentState(gridState: state, playerPool: pool)
        state.flushPendingSave()

        let fresh = LayoutPersistenceService(modelContext: modelContext)
        let layouts = fresh.currentLayout.tileLayouts.sorted { $0.index < $1.index }
        XCTAssertEqual(layouts[0].videoFileId, "fileX")
        XCTAssertEqual(layouts[0].audioState?.isMuted, true)
        XCTAssertEqual(layouts[0].audioState?.isVolumeOverrideActive, true)
        XCTAssertEqual(layouts[0].audioState?.overrideVolume ?? 0, 0.7, accuracy: 0.001)
    }

    @MainActor
    func testClearMissingVideoBindingDropsFileIdButPreservesLists() async throws {
        let smartId = UUID()
        let layout = TileLayout(index: 0)
        layout.videoFileId = "ghost-file"
        layout.smartListId = smartId
        layout.playbackTime = 99
        let layoutState = LayoutState()
        layoutState.tileLayouts = [layout]
        modelContext.insert(layoutState)
        try modelContext.save()

        let service = LayoutPersistenceService(modelContext: modelContext)
        let state = GridState()
        state.connectPersistence(service)

        state.clearMissingVideoBinding(at: 0)

        XCTAssertNil(layout.videoFileId)
        XCTAssertEqual(layout.smartListId, smartId, "Smart list assignment survives a missing video")
        XCTAssertEqual(layout.playbackTime, 0)
        XCTAssertNil(state.tiles[0].videoId)
        XCTAssertEqual(state.tiles[0].smartListId, smartId)
    }
}

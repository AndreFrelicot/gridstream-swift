//
//  GridState.swift
//  gridstream-ipad
//

import Foundation
import CoreGraphics
import OSLog

@Observable
final class GridState {
    private(set) var tiles: [Tile]
    var selectedTileIndex: Int?

    /// End-of-video behavior per tile, keyed by `Tile.id` so it follows a
    /// tile when tiles are reindexed. Unset demo tiles loop; other tiles stop.
    private var endActions: [UUID: TileEndAction] = [:]

    /// UserDefaults key of the end actions, stored in tile order.
    static let endActionsDefaultsKey = "tileEndActions"
    static let endActionsDefaultsVersionKey = "tileEndActionsVersion"

    // MARK: - Layout State Properties

    private(set) var layoutState: LayoutState

    var orientation: LayoutOrientation {
        layoutState.orientation
    }

    var activePreset: LayoutPreset? {
        guard let identifier = layoutState.presetIdentifier else { return nil }
        return LayoutPreset(rawValue: identifier)
    }

    var tileRatios: [TileLayout] {
        layoutState.tileLayouts.sorted { $0.index < $1.index }
    }

    // MARK: - Fullscreen State Properties

    private(set) var fullscreenTileIndex: Int?

    var isFullscreenMode: Bool {
        fullscreenTileIndex != nil
    }

    var isPiPLayoutMemoryEnabled: Bool {
        !UserDefaults.standard.bool(forKey: "pipLayoutMemoryDisabled")
    }

    // MARK: - Computed Properties for PiP Layout Memory

    private var effectiveFullscreenIndex: Int {
        isPiPLayoutMemoryEnabled ? (fullscreenTileIndex ?? 0) : 0
    }

    // MARK: - Persistence

    private var persistenceService: LayoutPersistenceService?
    private var saveWorkItem: DispatchWorkItem?
    private let saveDebounceInterval: TimeInterval = 0.5

    var shouldBootstrapDefaultTileLayout: Bool {
        persistenceService?.createdDefaultLayout == true &&
        tiles.count == 1 &&
        layoutState.tileLayouts.count == 1 &&
        tiles.allSatisfy { tile in
            tile.videoURL == nil &&
            tile.videoId == nil &&
            tile.smartListId == nil &&
            tile.simpleListId == nil
        }
    }

    // MARK: - Computed Properties

    var currentConfiguration: GridConfiguration {
        GridConfiguration.configuration(forTileCount: tiles.count)
    }

    var tileCount: Int {
        tiles.count
    }

    var canAddTile: Bool {
        tiles.count < 12
    }

    var canRemoveTile: Bool {
        tiles.count > 1 && selectedTileIndex != nil
    }

    // MARK: - Initialization

    init() {
        self.tiles = [Tile(index: 0)]
        self.selectedTileIndex = nil
        self.layoutState = LayoutState.createDefault()
        self.fullscreenTileIndex = nil
    }

    // MARK: - Fullscreen Mode Methods

    /// Enters fullscreen mode with the specified tile
    /// - Parameter tileIndex: The index of the tile to display fullscreen
    func enterFullscreen(tileIndex: Int) {
        guard tileIndex >= 0, tileIndex < tiles.count else {
            AppLogger.grid.warning("Cannot enter fullscreen: invalid tile index \(tileIndex)")
            return
        }

        fullscreenTileIndex = tileIndex
        AppLogger.grid.info("Entered fullscreen mode with tile \(tileIndex)")
    }

    /// Exits fullscreen mode and returns to grid layout
    func exitFullscreen() {
        fullscreenTileIndex = nil
        AppLogger.grid.info("Exited fullscreen mode")
    }

    /// Swaps the fullscreen tile with a PiP tile
    /// - Parameter toPipIndex: The index of the PiP tile to swap to fullscreen
    func swapFullscreen(toPipIndex: Int) {
        guard isFullscreenMode else {
            AppLogger.grid.warning("Cannot swap fullscreen: not in fullscreen mode")
            return
        }

        guard toPipIndex >= 0, toPipIndex < tiles.count else {
            AppLogger.grid.warning("Cannot swap fullscreen: invalid PiP index \(toPipIndex)")
            return
        }

        guard toPipIndex != fullscreenTileIndex else {
            AppLogger.grid.warning("Cannot swap fullscreen: PiP index matches fullscreen index")
            return
        }

        let previousFullscreen = fullscreenTileIndex
        fullscreenTileIndex = toPipIndex
        AppLogger.grid.info("Swapped fullscreen from tile \(previousFullscreen ?? -1) to tile \(toPipIndex)")
    }

    /// Swaps fullscreen with a PiP tile and exchanges persisted PiP transforms.
    /// This keeps each tile's saved PiP slot distinct across app restarts.
    /// - Parameters:
    ///   - toPipIndex: The tapped PiP tile index that becomes fullscreen
    ///   - tappedPiPTransform: The current transform of the tapped PiP tile
    func swapFullscreen(toPipIndex: Int, tappedPiPTransform: PiPTransform) {
        guard let oldFullscreenIndex = fullscreenTileIndex else {
            AppLogger.grid.warning("Cannot swap fullscreen with transform: not in fullscreen mode")
            return
        }

        guard toPipIndex >= 0, toPipIndex < tiles.count else {
            AppLogger.grid.warning("Cannot swap fullscreen with transform: invalid PiP index \(toPipIndex)")
            return
        }

        guard toPipIndex != oldFullscreenIndex else {
            AppLogger.grid.warning("Cannot swap fullscreen with transform: PiP index matches fullscreen index")
            return
        }

        if isPiPLayoutMemoryEnabled {
            // Save tapped PiP's current transform under current fullscreen context
            layoutState.setPipLayout(
                forPiP: toPipIndex,
                whenFullscreen: oldFullscreenIndex,
                position: tappedPiPTransform.position,
                scale: Double(tappedPiPTransform.scale),
                rotation: Double(tappedPiPTransform.rotation)
            )
        } else {
            // Old behavior: exchange transforms
            let oldFullscreenTransform = currentPiPTransform(for: oldFullscreenIndex)
            applyPiPTransform(tappedPiPTransform, to: oldFullscreenIndex)
            applyPiPTransform(oldFullscreenTransform, to: toPipIndex)
        }

        fullscreenTileIndex = toPipIndex
        AppLogger.grid.info("Swapped fullscreen from tile \(oldFullscreenIndex) to tile \(toPipIndex) with PiP transform exchange")
        scheduleSave()
    }

    // MARK: - Tile Management

    func addTile() {
        guard canAddTile else { return }
        let newIndex = tiles.count
        tiles.append(Tile(index: newIndex))

        // Add corresponding tile layout
        layoutState.tileLayouts.append(TileLayout(index: newIndex))

        // Check preset compatibility
        checkAndConvertPresetForTileCount()

        AppLogger.grid.info("Added tile at index \(newIndex). Total tiles: \(self.tiles.count)")
        scheduleSave()
    }

    func removeTile(at index: Int) {
        guard tiles.count > 1, index >= 0, index < tiles.count else { return }

        tiles.remove(at: index)

        // Remove corresponding tile layout and reindex
        if index < layoutState.tileLayouts.count {
            let sortedLayouts = layoutState.tileLayouts.sorted { $0.index < $1.index }
            if index < sortedLayouts.count {
                let layoutToRemove = sortedLayouts[index]
                if let layoutIndex = layoutState.tileLayouts.firstIndex(where: { $0.id == layoutToRemove.id }) {
                    layoutState.tileLayouts.remove(at: layoutIndex)
                }
            }
        }

        // Remove and reindex PiP layouts
        layoutState.removePipLayouts(forPiP: index)
        layoutState.reindexPipLayouts(fromIndex: index)

        // Reindex tiles while preserving all source assignments.
        for i in 0..<tiles.count {
            tiles[i] = Tile(
                index: i,
                id: tiles[i].id,
                videoURL: tiles[i].videoURL,
                videoId: tiles[i].videoId,
                playCount: tiles[i].playCount,
                totalViewTime: tiles[i].totalViewTime,
                smartListId: tiles[i].smartListId,
                simpleListId: tiles[i].simpleListId
            )
        }

        // Reindex tile layouts
        let sortedLayouts = layoutState.tileLayouts.sorted { $0.index < $1.index }
        for (newIndex, layout) in sortedLayouts.enumerated() {
            layout.index = newIndex
        }

        if selectedTileIndex == index {
            selectedTileIndex = nil
        } else if let selected = selectedTileIndex, selected > index {
            selectedTileIndex = selected - 1
        }

        // Tiles still waiting for restore move down with their tile; the
        // removed tile's own pending restore goes away with it.
        pendingRestoreTileIndices = Set(pendingRestoreTileIndices.compactMap { pending in
            pending == index ? nil : (pending > index ? pending - 1 : pending)
        })

        // Re-mirror content fields onto the reindexed layouts so the
        // post-remove tile assignments are persisted under the new indices.
        for i in tiles.indices {
            persistTileContent(at: i)
        }

        // Check preset compatibility after removal
        checkAndConvertPresetForTileCount()

        AppLogger.grid.info("Removed tile at index \(index). Total tiles: \(self.tiles.count)")
        scheduleSave()
    }

    func removeSelectedTile() {
        guard let selected = selectedTileIndex else { return }
        removeTile(at: selected)
    }

    func selectTile(at index: Int) {
        guard index >= 0, index < tiles.count else { return }
        selectedTileIndex = index
        AppLogger.grid.debug("Selected tile at index \(index)")
    }

    func setTileCount(_ count: Int) {
        guard count >= 1, count <= 12 else { return }

        if count > tiles.count {
            while tiles.count < count {
                let newIndex = tiles.count
                tiles.append(Tile(index: newIndex))
                layoutState.tileLayouts.append(TileLayout(index: newIndex))
            }
        } else if count < tiles.count {
            tiles = Array(tiles.prefix(count))
            // Remove excess tile layouts
            let sortedLayouts = layoutState.tileLayouts.sorted { $0.index < $1.index }
            let layoutsToKeep = Array(sortedLayouts.prefix(count))
            layoutState.tileLayouts = layoutsToKeep
            if let selected = selectedTileIndex, selected >= count {
                selectedTileIndex = nil
            }
            // Dropped tiles have nothing left to restore
            pendingRestoreTileIndices = pendingRestoreTileIndices.filter { $0 < count }
        }

        // Check preset compatibility
        checkAndConvertPresetForTileCount()

        AppLogger.grid.info("Set tile count to \(count)")
        scheduleSave()
    }

    func setVideoURL(_ url: URL?, videoId: String?, playCount: Int = 0, totalViewTime: Int = 0, at index: Int) {
        guard index >= 0, index < tiles.count else {
            AppLogger.grid.warning("Cannot set video URL at invalid index \(index)")
            return
        }

        tiles[index] = Tile(
            index: tiles[index].index,
            id: tiles[index].id,
            videoURL: url,
            videoId: videoId,
            playCount: playCount,
            totalViewTime: totalViewTime,
            smartListId: tiles[index].smartListId,
            simpleListId: tiles[index].simpleListId
        )

        if let url = url {
            AppLogger.grid.info("Set video URL for tile \(index): \(VideoURLBuilder.removingToken(from: url).absoluteString) [Stats: count=\(playCount), time=\(totalViewTime)]")
        } else {
            AppLogger.grid.info("Cleared video URL for tile \(index)")
        }

        persistTileContent(at: index)
        scheduleSave()
    }

    /// Rebuilds the stream URL of every tile playing from `serverURL`, so the
    /// URLs carry the current session token. Tiles whose URL is already
    /// current are left alone; the tiles reload the others in place.
    func refreshStreamURLs(serverURL: URL) {
        let serverKey = ServerSessionManager.serverKey(for: serverURL)
        for index in tiles.indices {
            let tile = tiles[index]
            guard let videoId = tile.videoId,
                  let currentURL = tile.videoURL,
                  ServerSessionManager.serverKey(for: currentURL) == serverKey,
                  let freshURL = VideoURLBuilder.buildStreamURL(from: serverURL, videoId: videoId),
                  freshURL != currentURL else { continue }
            setVideoURL(freshURL, videoId: videoId, playCount: tile.playCount, totalViewTime: tile.totalViewTime, at: index)
        }
    }

    // MARK: - Smart List Management

    /// Sets the Smart List for a tile.
    /// - Parameters:
    ///   - smartListId: The UUID of the Smart List to attach, or nil to clear
    ///   - index: The index of the tile to modify
    func setSmartList(_ smartListId: UUID?, at index: Int) {
        guard index >= 0, index < tiles.count else {
            AppLogger.grid.warning("Cannot set Smart List at invalid index \(index)")
            return
        }

        tiles[index] = Tile(
            index: tiles[index].index,
            id: tiles[index].id,
            videoURL: tiles[index].videoURL,
            videoId: tiles[index].videoId,
            playCount: tiles[index].playCount,
            totalViewTime: tiles[index].totalViewTime,
            smartListId: smartListId,
            simpleListId: nil
        )

        if let smartListId = smartListId {
            AppLogger.grid.info("Set Smart List \(smartListId.uuidString) for tile \(index)")
        } else {
            AppLogger.grid.info("Cleared Smart List for tile \(index)")
        }
        persistTileContent(at: index)
        scheduleSave()
    }

    /// Sets the Simple List for a tile.
    /// - Parameters:
    ///   - simpleListId: The UUID of the Simple List to attach, or nil to clear
    ///   - index: The index of the tile to modify
    func setSimpleList(_ simpleListId: UUID?, at index: Int) {
        guard index >= 0, index < tiles.count else {
            AppLogger.grid.warning("Cannot set Simple List at invalid index \(index)")
            return
        }

        tiles[index] = Tile(
            index: tiles[index].index,
            id: tiles[index].id,
            videoURL: tiles[index].videoURL,
            videoId: tiles[index].videoId,
            playCount: tiles[index].playCount,
            totalViewTime: tiles[index].totalViewTime,
            smartListId: nil,
            simpleListId: simpleListId
        )

        if let simpleListId = simpleListId {
            AppLogger.grid.info("Set Simple List \(simpleListId.uuidString) for tile \(index)")
        } else {
            AppLogger.grid.info("Cleared Simple List for tile \(index)")
        }
        persistTileContent(at: index)
        scheduleSave()
    }

    // MARK: - End Action

    func endAction(at index: Int) -> TileEndAction {
        guard index >= 0, index < tiles.count else { return .stop }
        return endActions[tiles[index].id] ?? (DemoMode.isDemo(tiles[index].videoURL) ? .loop : .stop)
    }

    func setEndAction(_ action: TileEndAction, at index: Int) {
        guard index >= 0, index < tiles.count else { return }
        endActions[tiles[index].id] = action
        persistEndActions()
        AppLogger.grid.info("Set end action \(action.rawValue) for tile \(index)")
    }

    /// End actions live in UserDefaults rather than on `TileLayout`: adding a
    /// field there needs a new SwiftData schema version.
    private func persistEndActions() {
        UserDefaults.standard.set(
            tiles.map { endActions[$0.id]?.rawValue ?? "" },
            forKey: Self.endActionsDefaultsKey
        )
        UserDefaults.standard.set(1, forKey: Self.endActionsDefaultsVersionKey)
    }

    // MARK: - Source Preset Support

    /// Exports the current tile configurations for saving as a preset
    func exportTileConfigs() -> [TileSourceConfig] {
        return tiles.map { TileSourceConfig.from(tile: $0) }
    }

    /// Clears all source assignments from all tiles
    func clearAllSources() {
        for i in 0..<tiles.count {
            tiles[i] = Tile(
                index: tiles[i].index,
                id: tiles[i].id,
                videoURL: nil,
                videoId: nil,
                playCount: 0,
                totalViewTime: 0,
                smartListId: nil,
                simpleListId: nil
            )
        }
        for layout in layoutState.tileLayouts {
            layout.videoFileId = nil
            layout.smartListId = nil
            layout.simpleListId = nil
            layout.playbackTime = 0
        }
        AppLogger.grid.info("Cleared all sources from \(self.tiles.count) tiles")
        scheduleSave()
    }

    // MARK: - Layout Mutation Methods

    func setOrientation(_ orientation: LayoutOrientation) {
        layoutState.orientation = orientation
        AppLogger.grid.info("Set layout orientation to \(orientation.rawValue)")
        scheduleSave()
    }

    func setPreset(_ preset: LayoutPreset) {
        let previousPreset = activePreset
        layoutState.presetIdentifier = preset.rawValue

        // Reset tile ratios to defaults when changing presets
        resetTileRatiosToDefault()

        if let previous = previousPreset {
            AppLogger.grid.info("Changed preset from \(previous.rawValue) to \(preset.rawValue)")
        } else {
            AppLogger.grid.info("Set preset to \(preset.rawValue)")
        }
        scheduleSave()
    }

    func setPiPLayoutMemoryEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(!enabled, forKey: "pipLayoutMemoryDisabled")
        AppLogger.grid.info("PiP layout memory \(enabled ? "enabled" : "disabled")")
    }

    /// Puts the floating windows back in their default place, size and
    /// rotation for the video at `fullscreenIndex`: its remembered layout, or
    /// the shared one when layout memory is off.
    func resetPiPLayout(forFullscreen fullscreenIndex: Int) {
        if isPiPLayoutMemoryEnabled {
            layoutState.removePipLayouts(whenFullscreen: fullscreenIndex)
        } else {
            clearSharedPiPLayout()
        }
        AppLogger.grid.info("Reset PiP layout for fullscreen tile \(fullscreenIndex)")
        scheduleSave()
    }

    /// Forgets every remembered floating-window layout, for every video, and
    /// the shared one.
    func resetAllPiPLayouts() {
        layoutState.pipLayouts.removeAll()
        clearSharedPiPLayout()
        AppLogger.grid.info("Reset all PiP layouts")
        scheduleSave()
    }

    private func clearSharedPiPLayout() {
        for layout in layoutState.tileLayouts {
            layout.pipPosition = nil
        }
    }

    func updateTileRatio(at index: Int, widthRatio: Double?, heightRatio: Double?) {
        guard index >= 0, index < layoutState.tileLayouts.count else {
            AppLogger.grid.warning("Cannot update tile ratio at invalid index \(index)")
            return
        }

        let sortedLayouts = layoutState.tileLayouts.sorted { $0.index < $1.index }
        guard index < sortedLayouts.count else { return }

        let layout = sortedLayouts[index]

        if let width = widthRatio {
            layout.updateWidthRatio(width)
        }
        if let height = heightRatio {
            layout.updateHeightRatio(height)
        }

        AppLogger.grid.debug("Updated tile ratio at index \(index): width=\(layout.widthRatio), height=\(layout.heightRatio)")
        scheduleSave()
    }

    /// Updates the PiP position for a tile and persists the change
    func updatePiPPosition(at index: Int, position: CGPoint) {
        if isPiPLayoutMemoryEnabled {
            layoutState.setPipLayout(
                forPiP: index,
                whenFullscreen: self.effectiveFullscreenIndex,
                position: position,
                scale: Double(currentPiPTransform(for: index).scale),
                rotation: Double(currentPiPTransform(for: index).rotation)
            )
            AppLogger.grid.debug("Updated PiP position for tile \(index) (fullscreen: \(self.effectiveFullscreenIndex)): (\(position.x), \(position.y))")
        } else {
            let sortedLayouts = layoutState.tileLayouts.sorted { $0.index < $1.index }
            guard let layout = sortedLayouts.first(where: { $0.index == index }) else {
                AppLogger.grid.warning("Cannot update PiP position: no layout found for tile index \(index)")
                return
            }
            layout.updatePiPPosition(position)
            AppLogger.grid.debug("Updated PiP position for tile \(index): (\(position.x), \(position.y))")
        }
        scheduleSave()
    }

    /// Updates the PiP scale for a tile and persists the change
    func updatePiPScale(at index: Int, scale: CGFloat) {
        if isPiPLayoutMemoryEnabled {
            layoutState.setPipLayout(
                forPiP: index,
                whenFullscreen: self.effectiveFullscreenIndex,
                position: currentPiPTransform(for: index).position,
                scale: Double(scale),
                rotation: Double(currentPiPTransform(for: index).rotation)
            )
            AppLogger.grid.debug("Updated PiP scale for tile \(index) (fullscreen: \(self.effectiveFullscreenIndex)): \(scale)")
        } else {
            let sortedLayouts = layoutState.tileLayouts.sorted { $0.index < $1.index }
            guard let layout = sortedLayouts.first(where: { $0.index == index }) else {
                AppLogger.grid.warning("Cannot update PiP scale: no layout found for tile index \(index)")
                return
            }
            layout.updatePiPScale(scale)
            AppLogger.grid.debug("Updated PiP scale for tile \(index): \(scale)")
        }
        scheduleSave()
    }

    /// Updates the PiP rotation for a tile and persists the change
    func updatePiPRotation(at index: Int, rotation: CGFloat) {
        if isPiPLayoutMemoryEnabled {
            layoutState.setPipLayout(
                forPiP: index,
                whenFullscreen: self.effectiveFullscreenIndex,
                position: currentPiPTransform(for: index).position,
                scale: Double(currentPiPTransform(for: index).scale),
                rotation: Double(rotation)
            )
            AppLogger.grid.debug("Updated PiP rotation for tile \(index) (fullscreen: \(self.effectiveFullscreenIndex)): \(rotation) radians")
        } else {
            let sortedLayouts = layoutState.tileLayouts.sorted { $0.index < $1.index }
            guard let layout = sortedLayouts.first(where: { $0.index == index }) else {
                AppLogger.grid.warning("Cannot update PiP rotation: no layout found for tile index \(index)")
                return
            }
            layout.updatePiPRotation(rotation)
            AppLogger.grid.debug("Updated PiP rotation for tile \(index): \(rotation) radians")
        }
        scheduleSave()
    }

    // MARK: - Persistence Connection

    func connectPersistence(_ service: LayoutPersistenceService) {
        self.persistenceService = service

        // Load saved layout state
        layoutState = service.currentLayout

        // Sync tile count with layout state
        let layoutTileCount = layoutState.tileLayouts.count
        if layoutTileCount > 0 && layoutTileCount != tiles.count {
            syncTilesWithLayoutState()
        }

        // Phase 1 restore: hydrate tile content from persistence without
        // touching the server. URL is left nil; phase 2 fills it in once a
        // verified server is discovered.
        hydrateTilesFromLayoutState()

        // Migrate legacy PiP positions if needed
        if migrateLegacyPiPPositions() {
            AppLogger.grid.info("Migrated legacy PiP positions to per-fullscreen layout memory")
            scheduleSave()
        }

        AppLogger.grid.info("Connected to persistence service")
    }

    /// Indices that still need URL hydration from a verified server.
    /// Drained either by the phase-2 coordinator (after running
    /// HEAD-checks and calling `setVideoURL`) or by the consume call below
    /// when the view applies the restored URL. The same set acts as the
    /// "autoplay deferred" flag: a tile present here at the moment its
    /// `videoURL` changes is being restored, not freshly assigned, so the
    /// view should pass `autoplay: false`.
    private(set) var pendingRestoreTileIndices: Set<Int> = []

    /// Tiles waiting for a verified server to rebuild their URL.
    var tilesPendingRestore: [Int] {
        pendingRestoreTileIndices.sorted()
    }

    var hasPendingRestores: Bool {
        !pendingRestoreTileIndices.isEmpty
    }

    /// Returns the persisted file ID + playback time for a tile, if any.
    func persistedRestoreInfo(forTile index: Int) -> (fileId: String, playbackTime: Double)? {
        guard let layout = layoutState.tileLayouts.first(where: { $0.index == index }),
              let fileId = layout.videoFileId,
              !fileId.isEmpty else { return nil }
        return (fileId, layout.playbackTime)
    }

    /// One-shot read of the autoplay-deferred flag. Returns true and clears
    /// the flag if the tile was pending restore; otherwise returns false.
    /// View calls this from its `videoURL` onChange to pick autoplay vs. pause.
    func consumePendingRestoreFlag(at index: Int) -> Bool {
        pendingRestoreTileIndices.remove(index) != nil
    }

    /// Clears the persisted file ID for a tile that the server no longer
    /// recognizes (HEAD 404). Smart/Simple list assignments survive so the
    /// list engine can pick a replacement video.
    func clearMissingVideoBinding(at index: Int) {
        guard index >= 0, index < tiles.count else { return }
        guard let layout = layoutState.tileLayouts.first(where: { $0.index == index }) else { return }
        layout.videoFileId = nil
        layout.playbackTime = 0

        let tile = tiles[index]
        tiles[index] = Tile(
            index: tile.index,
            id: tile.id,
            videoURL: nil,
            videoId: nil,
            playCount: 0,
            totalViewTime: 0,
            smartListId: tile.smartListId,
            simpleListId: tile.simpleListId
        )
        pendingRestoreTileIndices.remove(index)
        AppLogger.grid.warning("Cleared missing video binding for tile \(index): server no longer recognizes the persisted fileId")
        scheduleSave()
    }

    private func hydrateTilesFromLayoutState() {
        pendingRestoreTileIndices.removeAll()

        let savedEndActions = UserDefaults.standard.stringArray(forKey: Self.endActionsDefaultsKey) ?? []
        // Legacy arrays used "stop" for both implicit defaults and explicit choices.
        let hasExplicitDefaults = UserDefaults.standard.integer(forKey: Self.endActionsDefaultsVersionKey) >= 1
        endActions = [:]
        for (index, rawValue) in savedEndActions.enumerated() where index < tiles.count {
            if let action = TileEndAction(rawValue: rawValue), hasExplicitDefaults || action != .stop {
                endActions[tiles[index].id] = action
            }
        }

        for index in tiles.indices {
            guard let layout = layoutState.tileLayouts.first(where: { $0.index == index }) else { continue }

            // Restore content fields onto the in-memory Tile.
            let tile = tiles[index]
            tiles[index] = Tile(
                index: tile.index,
                id: tile.id,
                videoURL: nil,
                videoId: layout.videoFileId,
                playCount: 0,
                totalViewTime: 0,
                smartListId: layout.smartListId,
                simpleListId: layout.simpleListId
            )

            // Hydrate audio state from sidecar (no server needed for audio).
            if let audio = layout.audioState {
                TileAudioStateManager.shared.hydrateState(
                    TileAudioState(
                        isMuted: audio.isMuted,
                        isSolo: audio.isSolo,
                        isVolumeOverrideActive: audio.isVolumeOverrideActive,
                        overrideVolume: audio.overrideVolume
                    ),
                    for: index
                )
            }

            if let fileId = layout.videoFileId, !fileId.isEmpty {
                pendingRestoreTileIndices.insert(index)
            }
        }

        if !pendingRestoreTileIndices.isEmpty {
            AppLogger.grid.info("Phase 1 restore: \(self.pendingRestoreTileIndices.count) tiles pending URL rebuild after server discovery")
        }
    }

    func flushPendingSave() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        persistenceService?.save()
    }

    // MARK: - Content Persistence

    /// Mirrors the tile's content fields (videoFileId / smartListId / simpleListId)
    /// onto the matching TileLayout so SwiftData persists them. Called from every
    /// content mutation in addition to the save scheduling. Does not write the
    /// playbackTime — that's stamped only during the .background snapshot via
    /// `captureContentSnapshot(playerPool:)`.
    func persistTileContent(at index: Int) {
        guard index >= 0, index < tiles.count else { return }
        guard let layout = layoutState.tileLayouts.first(where: { $0.index == index }) else { return }
        let tile = tiles[index]
        layout.videoFileId = tile.videoId
        layout.smartListId = tile.smartListId
        layout.simpleListId = tile.simpleListId
        persistEndActions()
    }

    /// Snapshots every tile's content state to SwiftData, including current
    /// playback time read from the SharedPlayerPool. Called from the App's
    /// `.background` handler before `flushPendingSave()`.
    func captureContentSnapshot(playerPool: SharedPlayerPool) {
        for index in tiles.indices {
            persistTileContent(at: index)
            guard let layout = layoutState.tileLayouts.first(where: { $0.index == index }) else { continue }

            let audio = TileAudioStateManager.shared.state(for: index)
            if layout.audioState == nil {
                layout.audioState = TileAudioPersistedState(tileIndex: index)
            }
            layout.audioState?.isMuted = audio.isMuted
            layout.audioState?.isSolo = audio.isSolo
            layout.audioState?.isVolumeOverrideActive = audio.isVolumeOverrideActive
            layout.audioState?.overrideVolume = audio.overrideVolume

            if playerPool.hasCurrentPlayer(forTile: index) {
                let time = playerPool.currentPlayer(forTile: index).currentTime
                if time.isFinite, time >= 0 {
                    layout.playbackTime = time
                }
            }
        }
        AppLogger.grid.debug("Captured content snapshot for \(self.tiles.count) tiles")
    }

    /// Persist the given audio state (already updated in the shared manager)
    /// into the matching TileLayout's sidecar. Invoked via the
    /// `TileAudioStateManager.shared.persistenceBridge` set during app boot.
    func persistTileAudioState(at index: Int, state: TileAudioState) {
        guard let layout = layoutState.tileLayouts.first(where: { $0.index == index }) else { return }
        if layout.audioState == nil {
            layout.audioState = TileAudioPersistedState(tileIndex: index)
        }
        layout.audioState?.isMuted = state.isMuted
        layout.audioState?.isSolo = state.isSolo
        layout.audioState?.isVolumeOverrideActive = state.isVolumeOverrideActive
        layout.audioState?.overrideVolume = state.overrideVolume
        scheduleSave()
    }

    // MARK: - Private Helpers

    private func checkAndConvertPresetForTileCount() {
        guard let currentPreset = activePreset, currentPreset != .symmetric else { return }

        let compatiblePresets = LayoutPreset.compatiblePresets(forTileCount: tiles.count)

        if !compatiblePresets.contains(currentPreset) {
            let previousPreset = currentPreset
            layoutState.presetIdentifier = LayoutPreset.symmetric.rawValue
            AppLogger.grid.info("Converted preset from \(previousPreset.rawValue) to symmetric due to tile count change (\(self.tiles.count) tiles)")
        }
    }

    private func resetTileRatiosToDefault() {
        for layout in layoutState.tileLayouts {
            // Use 0.5 (50%) as default for equal distribution
            // The calculator will use these as relative weights
            layout.widthRatio = 0.5
            layout.heightRatio = 0.5
        }
    }

    private func syncTilesWithLayoutState() {
        let layoutTileCount = layoutState.tileLayouts.count

        if layoutTileCount > tiles.count {
            // Add tiles to match layout
            while tiles.count < layoutTileCount {
                tiles.append(Tile(index: tiles.count))
            }
        } else if layoutTileCount < tiles.count {
            // Reduce tiles to match layout
            tiles = Array(tiles.prefix(layoutTileCount))
            if let selected = selectedTileIndex, selected >= layoutTileCount {
                selectedTileIndex = nil
            }
        }
    }

    private func currentPiPTransform(for tileIndex: Int) -> PiPTransform {
        if isPiPLayoutMemoryEnabled {
            if let pipLayout = layoutState.pipLayout(forPiP: tileIndex, whenFullscreen: effectiveFullscreenIndex) {
                return PiPTransform(
                    position: CGPoint(x: pipLayout.positionX, y: pipLayout.positionY),
                    scale: CGFloat(pipLayout.scale),
                    rotation: CGFloat(pipLayout.rotation)
                )
            }
        } else {
            guard let layout = layoutState.tileLayouts.first(where: { $0.index == tileIndex }) else {
                return PiPTransform(
                    position: .zero,
                    scale: CGFloat(PiPPositionState.defaultScale),
                    rotation: CGFloat(PiPPositionState.defaultRotation)
                )
            }
            return PiPTransform(
                position: layout.currentPiPPosition,
                scale: layout.currentPiPScale,
                rotation: layout.currentPiPRotation
            )
        }

        return PiPTransform(
            position: .zero,
            scale: CGFloat(PiPPositionState.defaultScale),
            rotation: CGFloat(PiPPositionState.defaultRotation)
        )
    }

    private func applyPiPTransform(_ transform: PiPTransform, to tileIndex: Int) {
        if isPiPLayoutMemoryEnabled {
            layoutState.setPipLayout(
                forPiP: tileIndex,
                whenFullscreen: effectiveFullscreenIndex,
                position: transform.position,
                scale: Double(transform.scale),
                rotation: Double(transform.rotation)
            )
        } else {
            guard let layout = layoutState.tileLayouts.first(where: { $0.index == tileIndex }) else {
                AppLogger.grid.warning("Cannot apply PiP transform: no layout found for tile index \(tileIndex)")
                return
            }

            layout.updatePiPPosition(transform.position)
            layout.updatePiPScale(transform.scale)
            layout.updatePiPRotation(transform.rotation)
        }
    }

    private func migrateLegacyPiPPositions() -> Bool {
        // Migrate old per-tile PiPPositionState to new per-context PiPLayoutEntry system
        var migrated = false

        for layout in layoutState.tileLayouts.sorted(by: { $0.index < $1.index }) {
            guard let pipState = layout.pipPosition else { continue }

            // Skip default/zero positions
            if pipState.position == .zero {
                continue
            }

            // Create new PiPLayoutEntry for each old position under context 0 (default fullscreen)
            let entry = PiPLayoutEntry(
                pipTileIndex: layout.index,
                fullscreenTileIndex: 0,
                positionX: pipState.positionX,
                positionY: pipState.positionY,
                scale: pipState.scale,
                rotation: pipState.rotation
            )

            // Only add if this entry doesn't already exist
            if layoutState.pipLayout(forPiP: layout.index, whenFullscreen: 0) == nil {
                layoutState.pipLayouts.append(entry)
                migrated = true
                AppLogger.grid.info("Migrated PiP position for tile \(layout.index) to per-fullscreen system")
            }
        }

        return migrated
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.persistenceService?.save()
        }

        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDebounceInterval, execute: workItem)
    }
}

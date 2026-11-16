//
//  GridSidecarStateCoordinator.swift
//  gridstream-ipad
//

import Foundation
import OSLog

@MainActor
enum GridSidecarStateCoordinator {
    /// Snapshots every tile's content (video/list/playback time/audio) to
    /// SwiftData. Called on `.background` so a subsequent cold start can
    /// rebuild the grid before the server is reachable.
    static func captureContentState(
        gridState: GridState,
        playerPool: SharedPlayerPool
    ) {
        gridState.captureContentSnapshot(playerPool: playerPool)
    }

    /// Phase-2 restore: now that a verified server is available, rebuild
    /// stream URLs and rehydrate playback for tiles that finished phase 1
    /// with a persisted videoFileId. Runs at most once per cold start;
    /// re-emissions of the verified servers stream become no-ops because
    /// the pending set is drained as we go.
    ///
    /// HEAD-probes each fileId in parallel before applying the URL; a 404
    /// drops the binding via `clearMissingVideoBinding(at:)` so the
    /// SmartList/SimpleList engine can pick a replacement.
    static func restoreContentAfterDiscovery(
        serverURL: URL,
        gridState: GridState,
        historyManager: VideoHistoryManager,
        apiService: VideoAPIService? = nil
    ) async {
        guard gridState.hasPendingRestores else { return }

        let api = apiService ?? VideoAPIService()
        let pendingIndices = gridState.tilesPendingRestore
        AppLogger.grid.info("Phase 2 restore: hydrating \(pendingIndices.count) tiles from \(serverURL.absoluteString)")

        let probes: [(Int, String, Double, Bool)] = await withTaskGroup(
            of: (Int, String, Double, Bool).self
        ) { group in
            for index in pendingIndices {
                guard let info = gridState.persistedRestoreInfo(forTile: index) else { continue }
                group.addTask {
                    let exists = await api.checkVideoExists(fileId: info.fileId, serverURL: serverURL)
                    return (index, info.fileId, info.playbackTime, exists)
                }
            }
            var results: [(Int, String, Double, Bool)] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }
        }

        for (index, fileId, playbackTime, exists) in probes {
            guard exists else {
                gridState.clearMissingVideoBinding(at: index)
                continue
            }

            guard let streamURL = VideoURLBuilder.buildStreamURL(from: serverURL, videoId: fileId) else {
                AppLogger.video.warning("Phase 2: failed to build stream URL for fileId \(fileId), tile \(index)")
                _ = gridState.consumePendingRestoreFlag(at: index)
                continue
            }

            // Seed the per-tile history so the view sees a current entry
            // (otherwise navigation/seek lookups would return nil), then stamp
            // the persisted playbackTime so the view picks it up as seekTime.
            let history = historyManager.history(forTile: index)
            history.push(videoId: fileId, videoURL: streamURL)
            if playbackTime > 0 {
                history.updateCurrentPlaybackTime(playbackTime)
            }

            // setVideoURL fires the View's onChange(of: videoURL), which
            // consumes the pendingRestoreTileIndices flag to set autoplay:false.
            gridState.setVideoURL(streamURL, videoId: fileId, at: index)
        }
    }

    static func setTileCount(
        _ count: Int,
        gridState: GridState,
        playerPool: SharedPlayerPool,
        historyManager: VideoHistoryManager
    ) {
        let oldCount = gridState.tileCount
        gridState.setTileCount(count)
        let newCount = gridState.tileCount

        guard newCount < oldCount else { return }

        for index in newCount..<oldCount {
            playerPool.removePlayers(forTile: index)
            historyManager.clearHistory(forTile: index)
            TileAudioStateManager.shared.clearState(for: index)
            StereoPanState.shared.clearPan(for: index)
        }
    }

    static func removeSelectedTile(
        gridState: GridState,
        playerPool: SharedPlayerPool,
        historyManager: VideoHistoryManager
    ) {
        guard let selected = gridState.selectedTileIndex else { return }
        let oldCount = gridState.tileCount
        gridState.removeSelectedTile()
        guard gridState.tileCount == oldCount - 1 else { return }

        var newIndices: [Int: Int] = [:]
        for oldIndex in 0..<oldCount where oldIndex != selected {
            newIndices[oldIndex] = oldIndex > selected ? oldIndex - 1 : oldIndex
        }

        playerPool.removePlayers(forTile: selected)
        playerPool.reindexPlayers(newIndices: newIndices)
        historyManager.reindexHistories(newIndices: newIndices)
        TileAudioStateManager.shared.reindexStates(newIndices: newIndices)
        StereoPanState.shared.reindexPanValues(newIndices: newIndices)
    }

    static func clearAllSources(
        gridState: GridState,
        playerPool: SharedPlayerPool,
        historyManager: VideoHistoryManager,
        resetSidecarState: Bool
    ) {
        gridState.clearAllSources()

        guard resetSidecarState else { return }

        playerPool.removeAllPlayers()
        historyManager.clearAllHistories()
        TileAudioStateManager.shared.clearAllStates()
        StereoPanState.shared.clearAllPanValues()
    }
}

//
//  SourcePresetApplicator.swift
//  gridstream-ipad
//

import Foundation
import GridStreamAPI
import OSLog

/// Result of applying a preset to the grid state
struct PresetApplicationResult {
    let appliedCount: Int
    let warnings: [String]
    var success: Bool { warnings.isEmpty }
}

/// Applies source presets to GridState with validation
struct SourcePresetApplicator {

    /// Applies a preset to the grid state, validating that referenced lists still exist
    /// - Parameters:
    ///   - preset: The preset to apply
    ///   - gridState: The grid state to modify
    ///   - smartLists: Available smart lists for validation
    ///   - simpleLists: Available simple lists for validation
    /// - Returns: Result indicating success and any warnings
    static func apply(
        _ preset: SourcePreset,
        to gridState: GridState,
        playerPool: SharedPlayerPool,
        historyManager: VideoHistoryManager,
        smartLists: [SmartListInfo],
        simpleLists: [SimpleListDTO]
    ) -> PresetApplicationResult {
        var warnings: [String] = []
        var appliedCount = 0

        // 1. Set tile count
        GridSidecarStateCoordinator.setTileCount(
            preset.tileCount,
            gridState: gridState,
            playerPool: playerPool,
            historyManager: historyManager
        )

        // 2. Clear all existing sources first
        GridSidecarStateCoordinator.clearAllSources(
            gridState: gridState,
            playerPool: playerPool,
            historyManager: historyManager,
            resetSidecarState: false
        )

        // 3. Apply each tile config
        for config in preset.tileConfigs {
            guard config.tileIndex < preset.tileCount else { continue }

            switch config.sourceType {
            case .smartList:
                if let smartListId = config.smartListId {
                    if smartLists.contains(where: { $0.id == smartListId }) {
                        gridState.setSmartList(smartListId, at: config.tileIndex)
                        appliedCount += 1
                    } else {
                        warnings.append(String(localized: "Tile \(config.tileIndex + 1): Smart List no longer exists"))
                    }
                }

            case .simpleList:
                if let simpleListId = config.simpleListId {
                    if simpleLists.contains(where: { $0.id == simpleListId }) {
                        gridState.setSimpleList(simpleListId, at: config.tileIndex)
                        appliedCount += 1
                    } else {
                        warnings.append(String(localized: "Tile \(config.tileIndex + 1): Simple List no longer exists"))
                    }
                }

            case .directVideo:
                if config.videoId != nil {
                    warnings.append(String(localized: "Tile \(config.tileIndex + 1): Direct videos cannot be restored from presets yet"))
                }

            case .none:
                // Already cleared, nothing to do
                appliedCount += 1
            }
        }

        AppLogger.grid.info("Applied preset '\(preset.name)': \(appliedCount) tiles configured, \(warnings.count) warnings")

        return PresetApplicationResult(appliedCount: appliedCount, warnings: warnings)
    }
}

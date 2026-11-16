//
//  SourcePresetService.swift
//  gridstream-ipad
//

import Foundation
import SwiftData
import OSLog

enum SourcePresetError: Error, LocalizedError {
    case duplicateName(String)

    var errorDescription: String? {
        switch self {
        case .duplicateName(let name):
            return String(localized: "A preset named '\(name)' already exists")
        }
    }
}

@Observable
final class SourcePresetService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Fetch Methods

    func fetchAllPresets() -> [SourcePreset] {
        let descriptor = FetchDescriptor<SourcePreset>(
            sortBy: [SortDescriptor(\.name)]
        )

        do {
            let presets = try modelContext.fetch(descriptor)
            AppLogger.grid.info("Fetched \(presets.count) source presets")
            return presets
        } catch {
            AppLogger.grid.error("Failed to fetch source presets: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetches all presets sorted with last-used first, then by name.
    func fetchPresetsForRecall() -> [SourcePreset] {
        let descriptor = FetchDescriptor<SourcePreset>(
            sortBy: [SortDescriptor(\.name)]
        )

        do {
            let presets = try modelContext.fetch(descriptor)
            // Sort: last-used first (most recent), then unused presets by name
            return presets.sorted { a, b in
                switch (a.lastUsedAt, b.lastUsedAt) {
                case let (aDate?, bDate?):
                    return aDate > bDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return a.name < b.name
                }
            }
        } catch {
            AppLogger.grid.error("Failed to fetch source presets for recall: \(error.localizedDescription)")
            return []
        }
    }

    /// Marks a preset as used and persists the change.
    func markPresetAsUsed(_ preset: SourcePreset) {
        preset.markAsUsed()
        save()
    }

    func fetchPreset(id: UUID) -> SourcePreset? {
        let descriptor = FetchDescriptor<SourcePreset>(
            predicate: #Predicate { $0.id == id }
        )

        do {
            let presets = try modelContext.fetch(descriptor)
            return presets.first
        } catch {
            AppLogger.grid.error("Failed to fetch source preset by ID: \(error.localizedDescription)")
            return nil
        }
    }

    func fetchPreset(named name: String) -> SourcePreset? {
        let descriptor = FetchDescriptor<SourcePreset>(
            predicate: #Predicate { $0.name == name }
        )

        do {
            let presets = try modelContext.fetch(descriptor)
            return presets.first
        } catch {
            AppLogger.grid.error("Failed to fetch source preset by name: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Create Methods

    func createPreset(name: String, tileCount: Int, configs: [TileSourceConfig]) throws -> SourcePreset {
        // Check for duplicate name
        if fetchPreset(named: name) != nil {
            throw SourcePresetError.duplicateName(name)
        }

        let preset = SourcePreset(name: name, tileCount: tileCount, tileConfigs: configs)
        modelContext.insert(preset)
        save()
        AppLogger.grid.info("Created source preset: \(name)")
        return preset
    }

    // MARK: - Update Methods

    // MARK: - Delete Methods

    func deletePreset(_ preset: SourcePreset) {
        let name = preset.name
        modelContext.delete(preset)
        save()
        AppLogger.grid.info("Deleted source preset: \(name)")
    }

    // MARK: - Private Methods

    private func save() {
        do {
            if modelContext.hasChanges {
                try modelContext.save()
            }
        } catch {
            AppLogger.grid.error("Failed to save source preset changes: \(error.localizedDescription)")
        }
    }
}

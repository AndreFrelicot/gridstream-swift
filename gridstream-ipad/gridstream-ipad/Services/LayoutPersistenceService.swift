//
//  LayoutPersistenceService.swift
//  gridstream-ipad
//

import Foundation
import SwiftData
import OSLog

@Observable
final class LayoutPersistenceService {
    private let modelContext: ModelContext
    private(set) var currentLayout: LayoutState
    private(set) var createdDefaultLayout = false

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.currentLayout = LayoutState.createDefault()
        load()
    }

    func save() {
        do {
            if modelContext.hasChanges {
                try modelContext.save()
                AppLogger.grid.info("Layout state saved successfully")
            }
        } catch {
            AppLogger.grid.error("Failed to save layout state: \(error.localizedDescription)")
        }
    }

    func load() {
        let descriptor = FetchDescriptor<LayoutState>(
            sortBy: [SortDescriptor(\.id)]
        )

        do {
            let existingLayouts = try modelContext.fetch(descriptor)
            if let savedLayout = existingLayouts.first {
                currentLayout = savedLayout
                createdDefaultLayout = false
                if existingLayouts.count > 1 {
                    for duplicateLayout in existingLayouts.dropFirst() {
                        modelContext.delete(duplicateLayout)
                    }
                    try modelContext.save()
                    AppLogger.grid.info("Removed duplicate layout state records")
                }
                AppLogger.grid.info("Loaded existing layout state")
            } else {
                let newLayout = LayoutState.createDefault()
                modelContext.insert(newLayout)
                currentLayout = newLayout
                createdDefaultLayout = true
                try modelContext.save()
                AppLogger.grid.info("Created new default layout state")
            }
        } catch {
            AppLogger.grid.error("Failed to load layout state: \(error.localizedDescription)")
            let newLayout = LayoutState.createDefault()
            modelContext.insert(newLayout)
            currentLayout = newLayout
            createdDefaultLayout = true
            do {
                try modelContext.save()
                AppLogger.grid.info("Created fallback default layout state")
            } catch {
                modelContext.rollback()
                currentLayout = LayoutState.createDefault()
                AppLogger.grid.error("Failed to save fallback layout state: \(error.localizedDescription)")
            }
        }
    }
}

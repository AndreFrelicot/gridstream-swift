//
//  GridStreamSchema.swift
//  gridstream-ipad
//
//  Versioned SwiftData schema for the local layout store (layouts, PiP,
//  source presets, per-tile audio). Server metadata is not stored here.
//

import Foundation
import SwiftData

/// The schema as shipped before versioning was introduced. It references the
/// live model types; before changing any of them, copy this version's models
/// into nested types here, add `GridStreamSchemaV2`, and add a stage to
/// `GridStreamMigrationPlan` so existing stores migrate instead of failing
/// to open.
nonisolated enum GridStreamSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            LayoutState.self,
            TileLayout.self,
            TileFramingState.self,
            PiPPositionState.self,
            PiPLayoutEntry.self,
            SourcePreset.self,
            TileAudioPersistedState.self
        ]
    }
}

nonisolated enum GridStreamMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [GridStreamSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

/// Opens the persistent layout store. When it cannot be opened, the app
/// runs on an in-memory store for the session and tells the user (instead
/// of silently forgetting every layout change), offering to reset the store.
enum LayoutStore {
    struct OpenResult {
        let container: ModelContainer
        /// Why the persistent store could not be opened; nil when it was.
        let failure: String?
    }

    static func open() -> OpenResult {
        let schema = Schema(versionedSchema: GridStreamSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema)

        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: GridStreamMigrationPlan.self,
                configurations: [configuration]
            )
            return OpenResult(container: container, failure: nil)
        } catch {
            NSLog("GridStream iPad: persistent layout store failed to open: \(error)")
            do {
                let memoryConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                let container = try ModelContainer(for: schema, configurations: [memoryConfiguration])
                return OpenResult(container: container, failure: error.localizedDescription)
            } catch {
                fatalError("Failed to create persistent or in-memory ModelContainer: \(error)")
            }
        }
    }

    /// Deletes the on-disk store (and its SQLite sidecar files) so the next
    /// launch starts with an empty one. Takes effect after a relaunch.
    static func resetPersistentStore() throws {
        let storeURL = ModelConfiguration(schema: Schema(versionedSchema: GridStreamSchemaV1.self)).url
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }
}

//
//  SourcePreset.swift
//  gridstream-ipad
//

import Foundation
import SwiftData

@Model
final class SourcePreset {
    var id: UUID
    var name: String
    var tileCount: Int
    var tileConfigsJSON: String
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?

    /// Computed property to decode tileConfigs from JSON
    var tileConfigs: [TileSourceConfig] {
        guard let data = tileConfigsJSON.data(using: .utf8) else {
            return []
        }
        do {
            return try JSONDecoder().decode([TileSourceConfig].self, from: data)
        } catch {
            return []
        }
    }

    func markAsUsed() {
        lastUsedAt = Date()
    }

    init(name: String, tileCount: Int, tileConfigs: [TileSourceConfig]) {
        self.id = UUID()
        self.name = name
        self.tileCount = tileCount
        self.createdAt = Date()
        self.updatedAt = Date()

        // Encode tileConfigs to JSON
        do {
            let data = try JSONEncoder().encode(tileConfigs)
            self.tileConfigsJSON = String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            self.tileConfigsJSON = "[]"
        }
    }
}

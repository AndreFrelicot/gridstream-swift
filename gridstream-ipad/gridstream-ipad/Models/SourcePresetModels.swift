//
//  SourcePresetModels.swift
//  gridstream-ipad
//

import Foundation

/// Represents the type of source assigned to a tile
enum TileSourceType: String, Codable {
    case smartList
    case simpleList
    case directVideo
    case none
}

/// Configuration for a tile's source assignment within a preset
struct TileSourceConfig: Codable {
    let tileIndex: Int
    let sourceType: TileSourceType
    let smartListId: UUID?
    let simpleListId: UUID?
    let videoId: String?

    /// Creates a TileSourceConfig from an existing Tile
    /// - Parameter tile: The tile to extract configuration from
    /// - Returns: A TileSourceConfig representing the tile's current source assignment
    static func from(tile: Tile) -> TileSourceConfig {
        let sourceType: TileSourceType
        if tile.smartListId != nil {
            sourceType = .smartList
        } else if tile.simpleListId != nil {
            sourceType = .simpleList
        } else if tile.videoId != nil {
            sourceType = .directVideo
        } else {
            sourceType = .none
        }

        return TileSourceConfig(
            tileIndex: tile.index,
            sourceType: sourceType,
            smartListId: tile.smartListId,
            simpleListId: tile.simpleListId,
            videoId: tile.videoId
        )
    }
}

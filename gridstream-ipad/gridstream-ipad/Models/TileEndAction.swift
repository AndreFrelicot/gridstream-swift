//
//  TileEndAction.swift
//  gridstream-ipad
//

import Foundation

/// What a tile does when its video plays to the end. Set per tile; `.stop`
/// keeps the end-of-video screen, the others continue without it.
enum TileEndAction: String, CaseIterable {
    case stop
    case loop
    case next
    case shuffle

    var title: LocalizedStringResource {
        switch self {
        case .stop: return "Stop"
        case .loop: return "Loop"
        case .next: return "Play Next"
        case .shuffle: return "Play Random"
        }
    }

    var systemImage: String {
        switch self {
        case .stop: return "stop.fill"
        case .loop: return "repeat"
        case .next: return "forward.end.fill"
        case .shuffle: return "shuffle"
        }
    }

    /// The video that follows `currentId` in `orderedIds`, wrapping around to
    /// the first one. When `currentId` is not in the list, the first video.
    /// Nil when there is nothing else to play.
    static func nextVideoId(after currentId: String?, in orderedIds: [String]) -> String? {
        guard let first = orderedIds.first else { return nil }
        guard let currentId, let position = orderedIds.firstIndex(of: currentId) else {
            return first
        }
        let next = orderedIds[(position + 1) % orderedIds.count]
        return next == currentId ? nil : next
    }
}

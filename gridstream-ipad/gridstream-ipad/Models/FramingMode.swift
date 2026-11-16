//
//  FramingMode.swift
//  gridstream-ipad
//

import Foundation

nonisolated enum FramingMode: String, CaseIterable {
    case fill
    case fit
    case custom

    /// Returns the next mode in the cycle: fill -> fit -> custom -> fill
    var next: FramingMode {
        switch self {
        case .fill: return .fit
        case .fit: return .custom
        case .custom: return .fill
        }
    }

    /// SF Symbol icon name for each mode
    var iconName: String {
        switch self {
        case .fill: return "arrow.up.left.and.arrow.down.right"
        case .fit: return "arrow.down.forward.and.arrow.up.backward"
        case .custom: return "viewfinder"
        }
    }

    /// Human-readable display name for accessibility
    var displayName: LocalizedStringResource {
        switch self {
        case .fill: return "Fill"
        case .fit: return "Fit"
        case .custom: return "Custom"
        }
    }
}

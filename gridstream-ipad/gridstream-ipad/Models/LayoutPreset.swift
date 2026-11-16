//
//  LayoutPreset.swift
//  gridstream-ipad
//

import Foundation

enum LayoutPreset: String, CaseIterable, Identifiable, Codable {
    case symmetric
    case onePlusTwo
    case twoPlusOne
    case onePlusThree
    case threePlusOne
    case twoPlusTwoStacked

    var id: String { rawValue }

    var tileCount: Int {
        switch self {
        case .symmetric:
            return 0
        case .onePlusTwo, .twoPlusOne:
            return 3
        case .onePlusThree, .threePlusOne:
            return 4
        case .twoPlusTwoStacked:
            return 4
        }
    }

    var displayName: LocalizedStringResource {
        switch self {
        case .symmetric:
            return "Symmetric"
        case .onePlusTwo:
            return "1 + 2"
        case .twoPlusOne:
            return "2 + 1"
        case .onePlusThree:
            return "1 + 3"
        case .threePlusOne:
            return "3 + 1"
        case .twoPlusTwoStacked:
            return "2 + 2 Stacked"
        }
    }

    var iconName: String {
        switch self {
        case .symmetric:
            return "square.grid.2x2"
        case .onePlusTwo:
            return "rectangle.split.1x2"
        case .twoPlusOne:
            return "rectangle.split.2x1"
        case .onePlusThree:
            return "rectangle.split.1x2.fill"
        case .threePlusOne:
            return "rectangle.split.2x1.fill"
        case .twoPlusTwoStacked:
            return "rectangle.split.2x2"
        }
    }

    static func compatiblePresets(forTileCount count: Int) -> [LayoutPreset] {
        switch count {
        case 1, 2:
            return [.symmetric]
        case 3:
            return [.symmetric, .onePlusTwo, .twoPlusOne]
        case 4:
            return [.symmetric, .onePlusThree, .threePlusOne, .twoPlusTwoStacked]
        default:
            return [.symmetric]
        }
    }
}

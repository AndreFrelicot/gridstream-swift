//
//  GridConfiguration.swift
//  gridstream-ipad
//

import Foundation

enum GridConfiguration: CaseIterable, Identifiable {
    case oneByOne
    case oneByTwo
    case twoByTwo
    case twoByThree
    case threeByThree
    case threeByFour

    var id: Int { tileCount }

    var columns: Int {
        switch self {
        case .oneByOne:
            return 1
        case .oneByTwo:
            return 2
        case .twoByTwo:
            return 2
        case .twoByThree:
            return 3
        case .threeByThree:
            return 3
        case .threeByFour:
            return 4
        }
    }

    var rows: Int {
        switch self {
        case .oneByOne:
            return 1
        case .oneByTwo:
            return 1
        case .twoByTwo:
            return 2
        case .twoByThree:
            return 2
        case .threeByThree:
            return 3
        case .threeByFour:
            return 3
        }
    }

    var tileCount: Int {
        columns * rows
    }

    var displayName: LocalizedStringResource {
        "\(rows)x\(columns)"
    }

    static func configuration(forTileCount count: Int) -> GridConfiguration {
        switch count {
        case 1:
            return .oneByOne
        case 2:
            return .oneByTwo
        case 3, 4:
            return .twoByTwo
        case 5, 6:
            return .twoByThree
        case 7, 8, 9:
            return .threeByThree
        case 10, 11, 12:
            return .threeByFour
        default:
            if count < 1 {
                return .oneByOne
            }
            return .threeByFour
        }
    }
}

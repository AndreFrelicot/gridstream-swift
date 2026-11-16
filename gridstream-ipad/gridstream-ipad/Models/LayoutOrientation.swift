//
//  LayoutOrientation.swift
//  gridstream-ipad
//

import Foundation

enum LayoutOrientation: String, Codable, CaseIterable {
    case horizontal
    case vertical

    var sfSymbolName: String {
        switch self {
        case .horizontal:
            return "arrow.left.and.right"
        case .vertical:
            return "arrow.up.and.down"
        }
    }
}

//
//  DividerPosition.swift
//  gridstream-ipad
//

import SwiftUI

struct DividerPosition: Identifiable, Equatable {
    let id: UUID
    let axis: Axis
    let position: CGFloat
    let affectedTileIndices: [Int]
    let length: CGFloat

    init(
        axis: Axis,
        position: CGFloat,
        affectedTileIndices: [Int],
        length: CGFloat
    ) {
        self.id = UUID()
        self.axis = axis
        self.position = position
        self.affectedTileIndices = affectedTileIndices
        self.length = length
    }

    func hitRect(touchSize: CGFloat = 44) -> CGRect {
        switch axis {
        case .vertical:
            return CGRect(
                x: position - touchSize / 2,
                y: 0,
                width: touchSize,
                height: length
            )
        case .horizontal:
            return CGRect(
                x: 0,
                y: position - touchSize / 2,
                width: length,
                height: touchSize
            )
        }
    }
}

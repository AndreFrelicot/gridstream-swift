//
//  DividerCalculator.swift
//  gridstream-ipad
//

import SwiftUI

enum DividerCalculator {

    static func calculateDividers(
        from frames: [CGRect],
        preset: LayoutPreset,
        orientation: LayoutOrientation,
        availableSize: CGSize
    ) -> [DividerPosition] {
        guard frames.count >= 2 else { return [] }

        switch preset {
        case .symmetric:
            return []
        case .onePlusTwo:
            return calculateOnePlusTwoDividers(frames: frames, orientation: orientation, availableSize: availableSize)
        case .twoPlusOne:
            return calculateTwoPlusOneDividers(frames: frames, orientation: orientation, availableSize: availableSize)
        case .onePlusThree:
            return calculateOnePlusThreeDividers(frames: frames, orientation: orientation, availableSize: availableSize)
        case .threePlusOne:
            return calculateThreePlusOneDividers(frames: frames, orientation: orientation, availableSize: availableSize)
        case .twoPlusTwoStacked:
            return calculateTwoPlusTwoStackedDividers(frames: frames, orientation: orientation, availableSize: availableSize)
        }
    }

    // MARK: - 1+2 Dividers

    private static func calculateOnePlusTwoDividers(
        frames: [CGRect],
        orientation: LayoutOrientation,
        availableSize: CGSize
    ) -> [DividerPosition] {
        guard frames.count >= 3 else { return [] }

        var dividers: [DividerPosition] = []

        switch orientation {
        case .horizontal:
            // Vertical divider between tile 0 and tiles 1,2
            let mainDividerX = frames[0].maxX + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .vertical,
                position: mainDividerX,
                affectedTileIndices: [0, 1, 2],
                length: availableSize.height
            ))

            // Horizontal divider between tiles 1 and 2
            let secondaryDividerY = frames[1].maxY + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .horizontal,
                position: secondaryDividerY,
                affectedTileIndices: [1, 2],
                length: frames[1].width
            ))

        case .vertical:
            // Horizontal divider between tile 0 and tiles 1,2
            let mainDividerY = frames[0].maxY + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .horizontal,
                position: mainDividerY,
                affectedTileIndices: [0, 1, 2],
                length: availableSize.width
            ))

            // Vertical divider between tiles 1 and 2
            let secondaryDividerX = frames[1].maxX + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .vertical,
                position: secondaryDividerX,
                affectedTileIndices: [1, 2],
                length: frames[1].height
            ))
        }

        return dividers
    }

    // MARK: - 2+1 Dividers

    private static func calculateTwoPlusOneDividers(
        frames: [CGRect],
        orientation: LayoutOrientation,
        availableSize: CGSize
    ) -> [DividerPosition] {
        guard frames.count >= 3 else { return [] }

        var dividers: [DividerPosition] = []

        switch orientation {
        case .horizontal:
            // Vertical divider between tiles 0,1 and tile 2
            let mainDividerX = frames[0].maxX + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .vertical,
                position: mainDividerX,
                affectedTileIndices: [0, 1, 2],
                length: availableSize.height
            ))

            // Horizontal divider between tiles 0 and 1
            let secondaryDividerY = frames[0].maxY + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .horizontal,
                position: secondaryDividerY,
                affectedTileIndices: [0, 1],
                length: frames[0].width
            ))

        case .vertical:
            // Horizontal divider between tiles 0,1 and tile 2
            let mainDividerY = frames[0].maxY + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .horizontal,
                position: mainDividerY,
                affectedTileIndices: [0, 1, 2],
                length: availableSize.width
            ))

            // Vertical divider between tiles 0 and 1
            let secondaryDividerX = frames[0].maxX + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .vertical,
                position: secondaryDividerX,
                affectedTileIndices: [0, 1],
                length: frames[0].height
            ))
        }

        return dividers
    }

    // MARK: - 1+3 Dividers

    private static func calculateOnePlusThreeDividers(
        frames: [CGRect],
        orientation: LayoutOrientation,
        availableSize: CGSize
    ) -> [DividerPosition] {
        guard frames.count >= 4 else { return [] }

        var dividers: [DividerPosition] = []

        switch orientation {
        case .horizontal:
            // Main vertical divider
            let mainDividerX = frames[0].maxX + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .vertical,
                position: mainDividerX,
                affectedTileIndices: [0, 1, 2, 3],
                length: availableSize.height
            ))

            // Horizontal divider between tiles 1 and 2
            let dividerY1 = frames[1].maxY + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .horizontal,
                position: dividerY1,
                affectedTileIndices: [1, 2],
                length: frames[1].width
            ))

            // Horizontal divider between tiles 2 and 3
            let dividerY2 = frames[2].maxY + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .horizontal,
                position: dividerY2,
                affectedTileIndices: [2, 3],
                length: frames[2].width
            ))

        case .vertical:
            // Main horizontal divider
            let mainDividerY = frames[0].maxY + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .horizontal,
                position: mainDividerY,
                affectedTileIndices: [0, 1, 2, 3],
                length: availableSize.width
            ))

            // Vertical divider between tiles 1 and 2
            let dividerX1 = frames[1].maxX + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .vertical,
                position: dividerX1,
                affectedTileIndices: [1, 2],
                length: frames[1].height
            ))

            // Vertical divider between tiles 2 and 3
            let dividerX2 = frames[2].maxX + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .vertical,
                position: dividerX2,
                affectedTileIndices: [2, 3],
                length: frames[2].height
            ))
        }

        return dividers
    }

    // MARK: - 3+1 Dividers

    private static func calculateThreePlusOneDividers(
        frames: [CGRect],
        orientation: LayoutOrientation,
        availableSize: CGSize
    ) -> [DividerPosition] {
        guard frames.count >= 4 else { return [] }

        var dividers: [DividerPosition] = []

        switch orientation {
        case .horizontal:
            // Main vertical divider
            let mainDividerX = frames[0].maxX + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .vertical,
                position: mainDividerX,
                affectedTileIndices: [0, 1, 2, 3],
                length: availableSize.height
            ))

            // Horizontal divider between tiles 0 and 1
            let dividerY1 = frames[0].maxY + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .horizontal,
                position: dividerY1,
                affectedTileIndices: [0, 1],
                length: frames[0].width
            ))

            // Horizontal divider between tiles 1 and 2
            let dividerY2 = frames[1].maxY + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .horizontal,
                position: dividerY2,
                affectedTileIndices: [1, 2],
                length: frames[1].width
            ))

        case .vertical:
            // Main horizontal divider
            let mainDividerY = frames[0].maxY + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .horizontal,
                position: mainDividerY,
                affectedTileIndices: [0, 1, 2, 3],
                length: availableSize.width
            ))

            // Vertical divider between tiles 0 and 1
            let dividerX1 = frames[0].maxX + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .vertical,
                position: dividerX1,
                affectedTileIndices: [0, 1],
                length: frames[0].height
            ))

            // Vertical divider between tiles 1 and 2
            let dividerX2 = frames[1].maxX + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .vertical,
                position: dividerX2,
                affectedTileIndices: [1, 2],
                length: frames[1].height
            ))
        }

        return dividers
    }

    // MARK: - 2+2 Stacked Dividers

    private static func calculateTwoPlusTwoStackedDividers(
        frames: [CGRect],
        orientation: LayoutOrientation,
        availableSize: CGSize
    ) -> [DividerPosition] {
        guard frames.count >= 4 else { return [] }

        var dividers: [DividerPosition] = []

        switch orientation {
        case .horizontal:
            // Main vertical divider (center column)
            let mainDividerX = frames[0].maxX + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .vertical,
                position: mainDividerX,
                affectedTileIndices: [0, 1, 2, 3],
                length: availableSize.height
            ))

            // Main horizontal divider (center row)
            let mainDividerY = frames[0].maxY + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .horizontal,
                position: mainDividerY,
                affectedTileIndices: [0, 1, 2, 3],
                length: availableSize.width
            ))

        case .vertical:
            // Main vertical divider (center column)
            let mainDividerX = frames[0].maxX + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .vertical,
                position: mainDividerX,
                affectedTileIndices: [0, 1, 2, 3],
                length: availableSize.height
            ))

            // Left column horizontal divider
            let leftDividerY = frames[0].maxY + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .horizontal,
                position: leftDividerY,
                affectedTileIndices: [0, 1],
                length: frames[0].width
            ))

            // Right column horizontal divider
            let rightDividerY = frames[2].maxY + GridLayout.defaultSpacing / 2
            dividers.append(DividerPosition(
                axis: .horizontal,
                position: rightDividerY,
                affectedTileIndices: [2, 3],
                length: frames[2].width
            ))
        }

        return dividers
    }
}

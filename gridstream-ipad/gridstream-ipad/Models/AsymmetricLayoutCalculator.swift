//
//  AsymmetricLayoutCalculator.swift
//  gridstream-ipad
//

import CoreGraphics

enum AsymmetricLayoutCalculator {

    static func calculateFrames(
        preset: LayoutPreset,
        orientation: LayoutOrientation,
        availableSize: CGSize,
        spacing: CGFloat = GridLayout.defaultSpacing
    ) -> [CGRect] {
        switch preset {
        case .symmetric:
            return []
        case .onePlusTwo:
            return calculateOnePlusTwo(
                orientation: orientation,
                availableSize: availableSize,
                spacing: spacing
            )
        case .twoPlusOne:
            return calculateTwoPlusOne(
                orientation: orientation,
                availableSize: availableSize,
                spacing: spacing
            )
        case .onePlusThree:
            return calculateOnePlusThree(
                orientation: orientation,
                availableSize: availableSize,
                spacing: spacing
            )
        case .threePlusOne:
            return calculateThreePlusOne(
                orientation: orientation,
                availableSize: availableSize,
                spacing: spacing
            )
        case .twoPlusTwoStacked:
            return calculateTwoPlusTwoStacked(
                orientation: orientation,
                availableSize: availableSize,
                spacing: spacing
            )
        }
    }

    static func calculateFrames(
        preset: LayoutPreset,
        orientation: LayoutOrientation,
        availableSize: CGSize,
        tileLayouts: [TileLayout],
        spacing: CGFloat = GridLayout.defaultSpacing
    ) -> [CGRect] {
        guard !tileLayouts.isEmpty else {
            return calculateFrames(
                preset: preset,
                orientation: orientation,
                availableSize: availableSize,
                spacing: spacing
            )
        }

        switch preset {
        case .symmetric:
            return []
        case .onePlusTwo:
            return calculateOnePlusTwoWithRatios(
                orientation: orientation,
                availableSize: availableSize,
                tileLayouts: tileLayouts,
                spacing: spacing
            )
        case .twoPlusOne:
            return calculateTwoPlusOneWithRatios(
                orientation: orientation,
                availableSize: availableSize,
                tileLayouts: tileLayouts,
                spacing: spacing
            )
        case .onePlusThree:
            return calculateOnePlusThreeWithRatios(
                orientation: orientation,
                availableSize: availableSize,
                tileLayouts: tileLayouts,
                spacing: spacing
            )
        case .threePlusOne:
            return calculateThreePlusOneWithRatios(
                orientation: orientation,
                availableSize: availableSize,
                tileLayouts: tileLayouts,
                spacing: spacing
            )
        case .twoPlusTwoStacked:
            return calculateTwoPlusTwoStackedWithRatios(
                orientation: orientation,
                availableSize: availableSize,
                tileLayouts: tileLayouts,
                spacing: spacing
            )
        }
    }

    // MARK: - 1+2 Layout

    private static func calculateOnePlusTwo(
        orientation: LayoutOrientation,
        availableSize: CGSize,
        spacing: CGFloat
    ) -> [CGRect] {
        let primaryRatio: CGFloat = 0.66

        switch orientation {
        case .horizontal:
            let primaryWidth = (availableSize.width - spacing) * primaryRatio
            let secondaryWidth = availableSize.width - spacing - primaryWidth
            let secondaryHeight = (availableSize.height - spacing) / 2

            return [
                CGRect(x: 0, y: 0, width: primaryWidth, height: availableSize.height),
                CGRect(x: primaryWidth + spacing, y: 0, width: secondaryWidth, height: secondaryHeight),
                CGRect(x: primaryWidth + spacing, y: secondaryHeight + spacing, width: secondaryWidth, height: secondaryHeight)
            ]

        case .vertical:
            let primaryHeight = (availableSize.height - spacing) * primaryRatio
            let secondaryHeight = availableSize.height - spacing - primaryHeight
            let secondaryWidth = (availableSize.width - spacing) / 2

            return [
                CGRect(x: 0, y: 0, width: availableSize.width, height: primaryHeight),
                CGRect(x: 0, y: primaryHeight + spacing, width: secondaryWidth, height: secondaryHeight),
                CGRect(x: secondaryWidth + spacing, y: primaryHeight + spacing, width: secondaryWidth, height: secondaryHeight)
            ]
        }
    }

    private static func calculateOnePlusTwoWithRatios(
        orientation: LayoutOrientation,
        availableSize: CGSize,
        tileLayouts: [TileLayout],
        spacing: CGFloat
    ) -> [CGRect] {
        guard tileLayouts.count >= 3 else {
            return calculateOnePlusTwo(orientation: orientation, availableSize: availableSize, spacing: spacing)
        }

        switch orientation {
        case .horizontal:
            let totalWidth = availableSize.width - spacing
            let primaryWidth = totalWidth * tileLayouts[0].widthRatio
            let secondaryWidth = totalWidth - primaryWidth

            let totalSecondaryHeight = availableSize.height - spacing
            let secondaryHeight1 = totalSecondaryHeight * tileLayouts[1].heightRatio
            let secondaryHeight2 = totalSecondaryHeight - secondaryHeight1

            return [
                CGRect(x: 0, y: 0, width: primaryWidth, height: availableSize.height),
                CGRect(x: primaryWidth + spacing, y: 0, width: secondaryWidth, height: secondaryHeight1),
                CGRect(x: primaryWidth + spacing, y: secondaryHeight1 + spacing, width: secondaryWidth, height: secondaryHeight2)
            ]

        case .vertical:
            let totalHeight = availableSize.height - spacing
            let primaryHeight = totalHeight * tileLayouts[0].heightRatio
            let secondaryHeight = totalHeight - primaryHeight

            let totalSecondaryWidth = availableSize.width - spacing
            let secondaryWidth1 = totalSecondaryWidth * tileLayouts[1].widthRatio
            let secondaryWidth2 = totalSecondaryWidth - secondaryWidth1

            return [
                CGRect(x: 0, y: 0, width: availableSize.width, height: primaryHeight),
                CGRect(x: 0, y: primaryHeight + spacing, width: secondaryWidth1, height: secondaryHeight),
                CGRect(x: secondaryWidth1 + spacing, y: primaryHeight + spacing, width: secondaryWidth2, height: secondaryHeight)
            ]
        }
    }

    // MARK: - 2+1 Layout

    private static func calculateTwoPlusOne(
        orientation: LayoutOrientation,
        availableSize: CGSize,
        spacing: CGFloat
    ) -> [CGRect] {
        let primaryRatio: CGFloat = 0.66

        switch orientation {
        case .horizontal:
            let primaryWidth = (availableSize.width - spacing) * primaryRatio
            let secondaryWidth = availableSize.width - spacing - primaryWidth
            let secondaryHeight = (availableSize.height - spacing) / 2

            return [
                CGRect(x: 0, y: 0, width: secondaryWidth, height: secondaryHeight),
                CGRect(x: 0, y: secondaryHeight + spacing, width: secondaryWidth, height: secondaryHeight),
                CGRect(x: secondaryWidth + spacing, y: 0, width: primaryWidth, height: availableSize.height)
            ]

        case .vertical:
            let primaryHeight = (availableSize.height - spacing) * primaryRatio
            let secondaryHeight = availableSize.height - spacing - primaryHeight
            let secondaryWidth = (availableSize.width - spacing) / 2

            return [
                CGRect(x: 0, y: 0, width: secondaryWidth, height: secondaryHeight),
                CGRect(x: secondaryWidth + spacing, y: 0, width: secondaryWidth, height: secondaryHeight),
                CGRect(x: 0, y: secondaryHeight + spacing, width: availableSize.width, height: primaryHeight)
            ]
        }
    }

    private static func calculateTwoPlusOneWithRatios(
        orientation: LayoutOrientation,
        availableSize: CGSize,
        tileLayouts: [TileLayout],
        spacing: CGFloat
    ) -> [CGRect] {
        guard tileLayouts.count >= 3 else {
            return calculateTwoPlusOne(orientation: orientation, availableSize: availableSize, spacing: spacing)
        }

        switch orientation {
        case .horizontal:
            let totalWidth = availableSize.width - spacing
            let secondaryWidth = totalWidth * (1 - tileLayouts[2].widthRatio)
            let primaryWidth = totalWidth - secondaryWidth

            let totalSecondaryHeight = availableSize.height - spacing
            let secondaryHeight1 = totalSecondaryHeight * tileLayouts[0].heightRatio
            let secondaryHeight2 = totalSecondaryHeight - secondaryHeight1

            return [
                CGRect(x: 0, y: 0, width: secondaryWidth, height: secondaryHeight1),
                CGRect(x: 0, y: secondaryHeight1 + spacing, width: secondaryWidth, height: secondaryHeight2),
                CGRect(x: secondaryWidth + spacing, y: 0, width: primaryWidth, height: availableSize.height)
            ]

        case .vertical:
            let totalHeight = availableSize.height - spacing
            let secondaryHeight = totalHeight * (1 - tileLayouts[2].heightRatio)
            let primaryHeight = totalHeight - secondaryHeight

            let totalSecondaryWidth = availableSize.width - spacing
            let secondaryWidth1 = totalSecondaryWidth * tileLayouts[0].widthRatio
            let secondaryWidth2 = totalSecondaryWidth - secondaryWidth1

            return [
                CGRect(x: 0, y: 0, width: secondaryWidth1, height: secondaryHeight),
                CGRect(x: secondaryWidth1 + spacing, y: 0, width: secondaryWidth2, height: secondaryHeight),
                CGRect(x: 0, y: secondaryHeight + spacing, width: availableSize.width, height: primaryHeight)
            ]
        }
    }

    // MARK: - 1+3 Layout

    private static func calculateOnePlusThree(
        orientation: LayoutOrientation,
        availableSize: CGSize,
        spacing: CGFloat
    ) -> [CGRect] {
        let primaryRatio: CGFloat = 0.66

        switch orientation {
        case .horizontal:
            let primaryWidth = (availableSize.width - spacing) * primaryRatio
            let secondaryWidth = availableSize.width - spacing - primaryWidth
            let secondaryHeight = (availableSize.height - 2 * spacing) / 3

            return [
                CGRect(x: 0, y: 0, width: primaryWidth, height: availableSize.height),
                CGRect(x: primaryWidth + spacing, y: 0, width: secondaryWidth, height: secondaryHeight),
                CGRect(x: primaryWidth + spacing, y: secondaryHeight + spacing, width: secondaryWidth, height: secondaryHeight),
                CGRect(x: primaryWidth + spacing, y: 2 * (secondaryHeight + spacing), width: secondaryWidth, height: secondaryHeight)
            ]

        case .vertical:
            let primaryHeight = (availableSize.height - spacing) * primaryRatio
            let secondaryHeight = availableSize.height - spacing - primaryHeight
            let secondaryWidth = (availableSize.width - 2 * spacing) / 3

            return [
                CGRect(x: 0, y: 0, width: availableSize.width, height: primaryHeight),
                CGRect(x: 0, y: primaryHeight + spacing, width: secondaryWidth, height: secondaryHeight),
                CGRect(x: secondaryWidth + spacing, y: primaryHeight + spacing, width: secondaryWidth, height: secondaryHeight),
                CGRect(x: 2 * (secondaryWidth + spacing), y: primaryHeight + spacing, width: secondaryWidth, height: secondaryHeight)
            ]
        }
    }

    private static func calculateOnePlusThreeWithRatios(
        orientation: LayoutOrientation,
        availableSize: CGSize,
        tileLayouts: [TileLayout],
        spacing: CGFloat
    ) -> [CGRect] {
        guard tileLayouts.count >= 4 else {
            return calculateOnePlusThree(orientation: orientation, availableSize: availableSize, spacing: spacing)
        }

        switch orientation {
        case .horizontal:
            let totalWidth = availableSize.width - spacing
            let primaryWidth = totalWidth * tileLayouts[0].widthRatio
            let secondaryWidth = totalWidth - primaryWidth

            let totalSecondaryHeight = availableSize.height - 2 * spacing
            let ratio1 = tileLayouts[1].heightRatio
            let ratio2 = tileLayouts[2].heightRatio
            let ratio3 = tileLayouts[3].heightRatio
            let totalRatio = ratio1 + ratio2 + ratio3
            let h1 = totalSecondaryHeight * ratio1 / totalRatio
            let h2 = totalSecondaryHeight * ratio2 / totalRatio
            let h3 = totalSecondaryHeight * ratio3 / totalRatio

            return [
                CGRect(x: 0, y: 0, width: primaryWidth, height: availableSize.height),
                CGRect(x: primaryWidth + spacing, y: 0, width: secondaryWidth, height: h1),
                CGRect(x: primaryWidth + spacing, y: h1 + spacing, width: secondaryWidth, height: h2),
                CGRect(x: primaryWidth + spacing, y: h1 + h2 + 2 * spacing, width: secondaryWidth, height: h3)
            ]

        case .vertical:
            let totalHeight = availableSize.height - spacing
            let primaryHeight = totalHeight * tileLayouts[0].heightRatio
            let secondaryHeight = totalHeight - primaryHeight

            let totalSecondaryWidth = availableSize.width - 2 * spacing
            let ratio1 = tileLayouts[1].widthRatio
            let ratio2 = tileLayouts[2].widthRatio
            let ratio3 = tileLayouts[3].widthRatio
            let totalRatio = ratio1 + ratio2 + ratio3
            let w1 = totalSecondaryWidth * ratio1 / totalRatio
            let w2 = totalSecondaryWidth * ratio2 / totalRatio
            let w3 = totalSecondaryWidth * ratio3 / totalRatio

            return [
                CGRect(x: 0, y: 0, width: availableSize.width, height: primaryHeight),
                CGRect(x: 0, y: primaryHeight + spacing, width: w1, height: secondaryHeight),
                CGRect(x: w1 + spacing, y: primaryHeight + spacing, width: w2, height: secondaryHeight),
                CGRect(x: w1 + w2 + 2 * spacing, y: primaryHeight + spacing, width: w3, height: secondaryHeight)
            ]
        }
    }

    // MARK: - 3+1 Layout

    private static func calculateThreePlusOne(
        orientation: LayoutOrientation,
        availableSize: CGSize,
        spacing: CGFloat
    ) -> [CGRect] {
        let primaryRatio: CGFloat = 0.66

        switch orientation {
        case .horizontal:
            let primaryWidth = (availableSize.width - spacing) * primaryRatio
            let secondaryWidth = availableSize.width - spacing - primaryWidth
            let secondaryHeight = (availableSize.height - 2 * spacing) / 3

            return [
                CGRect(x: 0, y: 0, width: secondaryWidth, height: secondaryHeight),
                CGRect(x: 0, y: secondaryHeight + spacing, width: secondaryWidth, height: secondaryHeight),
                CGRect(x: 0, y: 2 * (secondaryHeight + spacing), width: secondaryWidth, height: secondaryHeight),
                CGRect(x: secondaryWidth + spacing, y: 0, width: primaryWidth, height: availableSize.height)
            ]

        case .vertical:
            let primaryHeight = (availableSize.height - spacing) * primaryRatio
            let secondaryHeight = availableSize.height - spacing - primaryHeight
            let secondaryWidth = (availableSize.width - 2 * spacing) / 3

            return [
                CGRect(x: 0, y: 0, width: secondaryWidth, height: secondaryHeight),
                CGRect(x: secondaryWidth + spacing, y: 0, width: secondaryWidth, height: secondaryHeight),
                CGRect(x: 2 * (secondaryWidth + spacing), y: 0, width: secondaryWidth, height: secondaryHeight),
                CGRect(x: 0, y: secondaryHeight + spacing, width: availableSize.width, height: primaryHeight)
            ]
        }
    }

    private static func calculateThreePlusOneWithRatios(
        orientation: LayoutOrientation,
        availableSize: CGSize,
        tileLayouts: [TileLayout],
        spacing: CGFloat
    ) -> [CGRect] {
        guard tileLayouts.count >= 4 else {
            return calculateThreePlusOne(orientation: orientation, availableSize: availableSize, spacing: spacing)
        }

        switch orientation {
        case .horizontal:
            let totalWidth = availableSize.width - spacing
            let secondaryWidth = totalWidth * (1 - tileLayouts[3].widthRatio)
            let primaryWidth = totalWidth - secondaryWidth

            let totalSecondaryHeight = availableSize.height - 2 * spacing
            let ratio0 = tileLayouts[0].heightRatio
            let ratio1 = tileLayouts[1].heightRatio
            let ratio2 = tileLayouts[2].heightRatio
            let totalRatio = ratio0 + ratio1 + ratio2
            let h0 = totalSecondaryHeight * ratio0 / totalRatio
            let h1 = totalSecondaryHeight * ratio1 / totalRatio
            let h2 = totalSecondaryHeight * ratio2 / totalRatio

            return [
                CGRect(x: 0, y: 0, width: secondaryWidth, height: h0),
                CGRect(x: 0, y: h0 + spacing, width: secondaryWidth, height: h1),
                CGRect(x: 0, y: h0 + h1 + 2 * spacing, width: secondaryWidth, height: h2),
                CGRect(x: secondaryWidth + spacing, y: 0, width: primaryWidth, height: availableSize.height)
            ]

        case .vertical:
            let totalHeight = availableSize.height - spacing
            let secondaryHeight = totalHeight * (1 - tileLayouts[3].heightRatio)
            let primaryHeight = totalHeight - secondaryHeight

            let totalSecondaryWidth = availableSize.width - 2 * spacing
            let ratio0 = tileLayouts[0].widthRatio
            let ratio1 = tileLayouts[1].widthRatio
            let ratio2 = tileLayouts[2].widthRatio
            let totalRatio = ratio0 + ratio1 + ratio2
            let w0 = totalSecondaryWidth * ratio0 / totalRatio
            let w1 = totalSecondaryWidth * ratio1 / totalRatio
            let w2 = totalSecondaryWidth * ratio2 / totalRatio

            return [
                CGRect(x: 0, y: 0, width: w0, height: secondaryHeight),
                CGRect(x: w0 + spacing, y: 0, width: w1, height: secondaryHeight),
                CGRect(x: w0 + w1 + 2 * spacing, y: 0, width: w2, height: secondaryHeight),
                CGRect(x: 0, y: secondaryHeight + spacing, width: availableSize.width, height: primaryHeight)
            ]
        }
    }

    // MARK: - 2+2 Stacked Layout

    private static func calculateTwoPlusTwoStacked(
        orientation: LayoutOrientation,
        availableSize: CGSize,
        spacing: CGFloat
    ) -> [CGRect] {
        let topRowHeight = (availableSize.height - spacing) / 2
        let bottomRowHeight = topRowHeight
        let colWidth = (availableSize.width - spacing) / 2

        switch orientation {
        case .horizontal:
            return [
                CGRect(x: 0, y: 0, width: colWidth, height: topRowHeight),
                CGRect(x: colWidth + spacing, y: 0, width: colWidth, height: topRowHeight),
                CGRect(x: 0, y: topRowHeight + spacing, width: colWidth, height: bottomRowHeight),
                CGRect(x: colWidth + spacing, y: topRowHeight + spacing, width: colWidth, height: bottomRowHeight)
            ]

        case .vertical:
            return [
                CGRect(x: 0, y: 0, width: colWidth, height: topRowHeight),
                CGRect(x: 0, y: topRowHeight + spacing, width: colWidth, height: bottomRowHeight),
                CGRect(x: colWidth + spacing, y: 0, width: colWidth, height: topRowHeight),
                CGRect(x: colWidth + spacing, y: topRowHeight + spacing, width: colWidth, height: bottomRowHeight)
            ]
        }
    }

    private static func calculateTwoPlusTwoStackedWithRatios(
        orientation: LayoutOrientation,
        availableSize: CGSize,
        tileLayouts: [TileLayout],
        spacing: CGFloat
    ) -> [CGRect] {
        guard tileLayouts.count >= 4 else {
            return calculateTwoPlusTwoStacked(orientation: orientation, availableSize: availableSize, spacing: spacing)
        }

        let totalWidth = availableSize.width - spacing
        let totalHeight = availableSize.height - spacing

        switch orientation {
        case .horizontal:
            let leftWidth = totalWidth * tileLayouts[0].widthRatio
            let rightWidth = totalWidth - leftWidth
            let topHeight = totalHeight * tileLayouts[0].heightRatio
            let bottomHeight = totalHeight - topHeight

            return [
                CGRect(x: 0, y: 0, width: leftWidth, height: topHeight),
                CGRect(x: leftWidth + spacing, y: 0, width: rightWidth, height: topHeight),
                CGRect(x: 0, y: topHeight + spacing, width: leftWidth, height: bottomHeight),
                CGRect(x: leftWidth + spacing, y: topHeight + spacing, width: rightWidth, height: bottomHeight)
            ]

        case .vertical:
            let leftWidth = totalWidth * tileLayouts[0].widthRatio
            let rightWidth = totalWidth - leftWidth
            let topLeftHeight = totalHeight * tileLayouts[0].heightRatio
            let bottomLeftHeight = totalHeight - topLeftHeight
            let topRightHeight = totalHeight * tileLayouts[2].heightRatio
            let bottomRightHeight = totalHeight - topRightHeight

            return [
                CGRect(x: 0, y: 0, width: leftWidth, height: topLeftHeight),
                CGRect(x: 0, y: topLeftHeight + spacing, width: leftWidth, height: bottomLeftHeight),
                CGRect(x: leftWidth + spacing, y: 0, width: rightWidth, height: topRightHeight),
                CGRect(x: leftWidth + spacing, y: topRightHeight + spacing, width: rightWidth, height: bottomRightHeight)
            ]
        }
    }
}

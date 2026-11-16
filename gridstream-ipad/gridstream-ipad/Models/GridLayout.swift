//
//  GridLayout.swift
//  gridstream-ipad
//

import Foundation

struct GridLayout {
    let columns: Int
    let rows: Int
    let tileSize: CGSize
    let spacing: CGFloat

    static let defaultSpacing: CGFloat = 8

    static func calculate(
        for configuration: GridConfiguration,
        availableSize: CGSize,
        spacing: CGFloat = defaultSpacing,
        orientation: LayoutOrientation = .horizontal
    ) -> GridLayout {
        // For vertical orientation, swap columns and rows to stack tiles vertically
        let columns: Int
        let rows: Int

        if orientation == .vertical {
            columns = configuration.rows
            rows = configuration.columns
        } else {
            columns = configuration.columns
            rows = configuration.rows
        }

        let totalHorizontalSpacing = spacing * CGFloat(columns - 1)
        let totalVerticalSpacing = spacing * CGFloat(rows - 1)

        let availableWidth = availableSize.width - totalHorizontalSpacing
        let availableHeight = availableSize.height - totalVerticalSpacing

        let tileWidth = availableWidth / CGFloat(columns)
        let tileHeight = availableHeight / CGFloat(rows)

        return GridLayout(
            columns: columns,
            rows: rows,
            tileSize: CGSize(width: tileWidth, height: tileHeight),
            spacing: spacing
        )
    }

    func position(forIndex index: Int) -> CGPoint {
        let column = index % columns
        let row = index / columns

        let x = CGFloat(column) * (tileSize.width + spacing) + tileSize.width / 2
        let y = CGFloat(row) * (tileSize.height + spacing) + tileSize.height / 2

        return CGPoint(x: x, y: y)
    }

    func frame(forIndex index: Int) -> CGRect {
        let column = index % columns
        let row = index / columns

        let x = CGFloat(column) * (tileSize.width + spacing)
        let y = CGFloat(row) * (tileSize.height + spacing)

        return CGRect(origin: CGPoint(x: x, y: y), size: tileSize)
    }

    // MARK: - Variable Size Layout Support

    static func calculateVariable(
        preset: LayoutPreset,
        orientation: LayoutOrientation,
        tileLayouts: [TileLayout],
        availableSize: CGSize,
        spacing: CGFloat = defaultSpacing
    ) -> [CGRect] {
        if preset == .symmetric || tileLayouts.isEmpty {
            return []
        }

        return AsymmetricLayoutCalculator.calculateFrames(
            preset: preset,
            orientation: orientation,
            availableSize: availableSize,
            tileLayouts: tileLayouts,
            spacing: spacing
        )
    }

    static func calculateDividers(
        from frames: [CGRect],
        preset: LayoutPreset,
        orientation: LayoutOrientation,
        availableSize: CGSize
    ) -> [DividerPosition] {
        DividerCalculator.calculateDividers(
            from: frames,
            preset: preset,
            orientation: orientation,
            availableSize: availableSize
        )
    }
}

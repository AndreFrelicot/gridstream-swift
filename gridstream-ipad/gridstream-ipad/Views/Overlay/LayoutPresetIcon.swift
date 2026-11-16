//
//  LayoutPresetIcon.swift
//  gridstream-ipad
//

import SwiftUI

struct LayoutPresetIcon: View {
    let preset: LayoutPreset
    var isSelected: Bool = false
    var size: CGSize = CGSize(width: 48, height: 32)

    private let spacing: CGFloat = 2

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                .frame(width: size.width + 6, height: size.height + 6)

            presetLayout
        }
    }

    @ViewBuilder
    private var presetLayout: some View {
        switch preset {
        case .symmetric:
            symmetricLayout
        case .onePlusTwo:
            onePlusTwoLayout
        case .twoPlusOne:
            twoPlusOneLayout
        case .onePlusThree:
            onePlusThreeLayout
        case .threePlusOne:
            threePlusOneLayout
        case .twoPlusTwoStacked:
            twoPlusTwoStackedLayout
        }
    }

    // MARK: - Symmetric Layout (2x2 grid as placeholder)

    private var symmetricLayout: some View {
        let cols = 2
        let rows = 2
        let cellWidth = (size.width - spacing) / CGFloat(cols)
        let cellHeight = (size.height - spacing) / CGFloat(rows)

        return VStack(spacing: spacing) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: spacing) {
                    ForEach(0..<cols, id: \.self) { _ in
                        cellView(width: cellWidth, height: cellHeight)
                    }
                }
            }
        }
    }

    // MARK: - 1+2 Layout: One large left, two stacked right

    private var onePlusTwoLayout: some View {
        let primaryWidth = (size.width - spacing) * 0.6
        let secondaryWidth = size.width - spacing - primaryWidth
        let secondaryHeight = (size.height - spacing) / 2

        return HStack(spacing: spacing) {
            cellView(width: primaryWidth, height: size.height)
            VStack(spacing: spacing) {
                cellView(width: secondaryWidth, height: secondaryHeight)
                cellView(width: secondaryWidth, height: secondaryHeight)
            }
        }
    }

    // MARK: - 2+1 Layout: Two stacked left, one large right

    private var twoPlusOneLayout: some View {
        let primaryWidth = (size.width - spacing) * 0.6
        let secondaryWidth = size.width - spacing - primaryWidth
        let secondaryHeight = (size.height - spacing) / 2

        return HStack(spacing: spacing) {
            VStack(spacing: spacing) {
                cellView(width: secondaryWidth, height: secondaryHeight)
                cellView(width: secondaryWidth, height: secondaryHeight)
            }
            cellView(width: primaryWidth, height: size.height)
        }
    }

    // MARK: - 1+3 Layout: One large left, three stacked right

    private var onePlusThreeLayout: some View {
        let primaryWidth = (size.width - spacing) * 0.6
        let secondaryWidth = size.width - spacing - primaryWidth
        let secondaryHeight = (size.height - 2 * spacing) / 3

        return HStack(spacing: spacing) {
            cellView(width: primaryWidth, height: size.height)
            VStack(spacing: spacing) {
                cellView(width: secondaryWidth, height: secondaryHeight)
                cellView(width: secondaryWidth, height: secondaryHeight)
                cellView(width: secondaryWidth, height: secondaryHeight)
            }
        }
    }

    // MARK: - 3+1 Layout: Three stacked left, one large right

    private var threePlusOneLayout: some View {
        let primaryWidth = (size.width - spacing) * 0.6
        let secondaryWidth = size.width - spacing - primaryWidth
        let secondaryHeight = (size.height - 2 * spacing) / 3

        return HStack(spacing: spacing) {
            VStack(spacing: spacing) {
                cellView(width: secondaryWidth, height: secondaryHeight)
                cellView(width: secondaryWidth, height: secondaryHeight)
                cellView(width: secondaryWidth, height: secondaryHeight)
            }
            cellView(width: primaryWidth, height: size.height)
        }
    }

    // MARK: - 2+2 Stacked Layout: 2x2 grid

    private var twoPlusTwoStackedLayout: some View {
        let cellWidth = (size.width - spacing) / 2
        let cellHeight = (size.height - spacing) / 2

        return VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                cellView(width: cellWidth, height: cellHeight)
                cellView(width: cellWidth, height: cellHeight)
            }
            HStack(spacing: spacing) {
                cellView(width: cellWidth, height: cellHeight)
                cellView(width: cellWidth, height: cellHeight)
            }
        }
    }

    // MARK: - Helper

    private func cellView(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.secondary.opacity(0.5))
            .frame(width: width, height: height)
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 16) {
            ForEach(LayoutPreset.allCases, id: \.self) { preset in
                VStack(spacing: 4) {
                    LayoutPresetIcon(preset: preset)
                    Text(preset.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    .padding()
}

#Preview("Selected State") {
    HStack(spacing: 16) {
        LayoutPresetIcon(preset: .onePlusTwo, isSelected: false)
        LayoutPresetIcon(preset: .onePlusTwo, isSelected: true)
    }
    .padding()
}

#Preview("All Presets Grid") {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 16) {
        ForEach(LayoutPreset.allCases, id: \.self) { preset in
            VStack(spacing: 6) {
                LayoutPresetIcon(preset: preset, isSelected: preset == .onePlusTwo)
                Text(preset.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding()
}

//
//  GridIconMenu.swift
//  gridstream-ipad
//

import SwiftUI

struct GridIconMenu: View {
    @Bindable var gridState: GridState
    var onMenuOpen: (() -> Void)?
    var onMenuClose: (() -> Void)?

    @Environment(SharedPlayerPool.self) private var playerPool
    @Environment(VideoHistoryManager.self) private var historyManager
    @State private var showMenu = false

    private let layouts: [GridConfiguration] = [
        .oneByOne,
        .oneByTwo,
        .twoByTwo,
        .twoByThree,
        .threeByThree,
        .threeByFour
    ]

    private var compatibleAsymmetricPresets: [LayoutPreset] {
        LayoutPreset.compatiblePresets(forTileCount: gridState.tileCount)
            .filter { $0 != .symmetric }
    }

    var body: some View {
        Button(action: { showMenu.toggle() }) {
            HStack(spacing: 6) {
                GridIconThumbnail(configuration: gridState.currentConfiguration, size: 22)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
            }
        }
        .accessibilityLabel("Layout")
        .popover(isPresented: $showMenu, arrowEdge: .top) {
            gridSelectionView
                .presentationCompactAdaptation(.popover)
        }
        .onChange(of: showMenu) { _, isOpen in
            if isOpen {
                onMenuOpen?()
            } else {
                onMenuClose?()
            }
        }
    }

    private var gridSelectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            symmetricGridSection

            if !compatibleAsymmetricPresets.isEmpty {
                Divider()
                asymmetricPresetsSection
            }
        }
        .padding()
    }

    private var symmetricGridSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Symmetric Layouts")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
                ForEach(layouts) { layout in
                    Button(action: {
                        GridSidecarStateCoordinator.setTileCount(
                            layout.tileCount,
                            gridState: gridState,
                            playerPool: playerPool,
                            historyManager: historyManager
                        )
                        gridState.setPreset(.symmetric)
                        showMenu = false
                    }) {
                        VStack(spacing: 4) {
                            GridIconThumbnail(
                                configuration: layout,
                                size: 40,
                                isSelected: gridState.currentConfiguration == layout && gridState.activePreset == .symmetric
                            )

                            Text(layout.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
    }

    private var asymmetricPresetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Asymmetric Layouts")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
                ForEach(compatibleAsymmetricPresets, id: \.self) { preset in
                    Button(action: {
                        gridState.setPreset(preset)
                        showMenu = false
                    }) {
                        VStack(spacing: 4) {
                            LayoutPresetIcon(
                                preset: preset,
                                isSelected: gridState.activePreset == preset,
                                size: CGSize(width: 48, height: 32)
                            )

                            Text(preset.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
    }
}

struct GridIconThumbnail: View {
    let configuration: GridConfiguration
    let size: CGFloat
    var isSelected: Bool = false

    var body: some View {
        let columns = configuration.columns
        let rows = configuration.rows
        let spacing: CGFloat = 2
        let cellWidth = (size - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let cellHeight = (size - spacing * CGFloat(rows - 1)) / CGFloat(rows)

        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                .frame(width: size + 6, height: size + 6)

            VStack(spacing: spacing) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<columns, id: \.self) { column in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(.secondary)
                                .frame(width: cellWidth, height: cellHeight)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    let gridState = GridState()
    return GridIconMenu(gridState: gridState)
        .padding()
}

#Preview("With 3 Tiles") {
    let gridState = GridState()
    gridState.setTileCount(3)
    return GridIconMenu(gridState: gridState)
        .padding()
}

#Preview("With 4 Tiles") {
    let gridState = GridState()
    gridState.setTileCount(4)
    return GridIconMenu(gridState: gridState)
        .padding()
}

#Preview("Thumbnails") {
    HStack(spacing: 16) {
        ForEach(GridConfiguration.allCases) { config in
            VStack {
                GridIconThumbnail(configuration: config, size: 40)
                Text(config.displayName)
                    .font(.caption)
            }
        }
    }
    .padding()
}

#Preview("Selected Thumbnail") {
    GridIconThumbnail(configuration: .twoByTwo, size: 40, isSelected: true)
        .padding()
}

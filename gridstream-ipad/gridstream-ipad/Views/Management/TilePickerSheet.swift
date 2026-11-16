//
//  TilePickerSheet.swift
//  gridstream-ipad
//

import SwiftUI

struct TilePickerSheet: View {
    let tiles: [Tile]
    let listName: String
    let activePreset: LayoutPreset?
    let orientation: LayoutOrientation
    let currentTileIndex: Int?
    let onApply: (Int) -> Void
    let onCancel: () -> Void

    @State private var selectedIndex: Int?

    private let miniGridSize: CGFloat = 280

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Select a tile to apply \"\(listName)\"")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if tiles.isEmpty {
                    emptyTilesView
                } else {
                    miniGridView
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Apply to Tile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        if let index = selectedIndex {
                            onApply(index)
                        }
                    }
                    .disabled(selectedIndex == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var emptyTilesView: some View {
        ContentUnavailableView(
            "No Tiles Available",
            systemImage: "square.grid.2x2",
            description: Text("Add tiles to the grid first.")
        )
    }

    private var miniGridView: some View {
        GeometryReader { geometry in
            let containerSize = CGSize(width: miniGridSize, height: miniGridSize * 0.6)
            let frames = calculateMiniFrames(containerSize: containerSize)

            ZStack(alignment: .topLeading) {
                ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                    let frame = index < frames.count ? frames[index] : .zero

                    miniTileView(index: index, tile: tile)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
            .frame(width: containerSize.width, height: containerSize.height)
            .frame(maxWidth: .infinity)
        }
        .frame(height: miniGridSize * 0.6 + 20)
    }

    private func miniTileView(index: Int, tile: Tile) -> some View {
        Button {
            selectedIndex = index
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(tileBackgroundColor(for: index, tile: tile))

                VStack(spacing: 4) {
                    if tile.hasVideo {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Text("\(index + 1)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }

                if selectedIndex == index {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor, lineWidth: 3)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white, Color.accentColor)
                        .offset(x: 0, y: -8)
                }

                if currentTileIndex == index && selectedIndex != index {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.green.opacity(0.6), lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tile.hasVideo ? "Tile \(index + 1), has video" : "Tile \(index + 1)")
    }

    private func tileBackgroundColor(for index: Int, tile: Tile) -> Color {
        if tile.hasVideo {
            return Color.blue.opacity(0.6)
        } else {
            return Color.gray.opacity(0.4)
        }
    }

    private func calculateMiniFrames(containerSize: CGSize) -> [CGRect] {
        let spacing: CGFloat = 4

        if let preset = activePreset, preset != .symmetric {
            return AsymmetricLayoutCalculator.calculateFrames(
                preset: preset,
                orientation: orientation,
                availableSize: containerSize,
                spacing: spacing
            )
        }

        let config = GridConfiguration.configuration(forTileCount: tiles.count)
        let layout = GridLayout.calculate(
            for: config,
            availableSize: containerSize,
            spacing: spacing,
            orientation: orientation
        )

        return tiles.enumerated().map { index, _ in
            layout.frame(forIndex: index)
        }
    }
}

#Preview("2x2 Grid") {
    TilePickerSheet(
        tiles: [
            Tile(index: 0),
            Tile(index: 1),
            Tile(index: 2),
            Tile(index: 3)
        ],
        listName: "My Favorites",
        activePreset: .symmetric,
        orientation: .horizontal,
        currentTileIndex: 0,
        onApply: { index in
            print("Applied to tile \(index)")
        },
        onCancel: {
            print("Cancelled")
        }
    )
}

#Preview("1+2 Asymmetric") {
    TilePickerSheet(
        tiles: [
            Tile(index: 0),
            Tile(index: 1),
            Tile(index: 2)
        ],
        listName: "Smart List",
        activePreset: .onePlusTwo,
        orientation: .horizontal,
        currentTileIndex: nil,
        onApply: { _ in },
        onCancel: {}
    )
}

#Preview("Empty") {
    TilePickerSheet(
        tiles: [],
        listName: "Test List",
        activePreset: .symmetric,
        orientation: .horizontal,
        currentTileIndex: nil,
        onApply: { _ in },
        onCancel: {}
    )
}

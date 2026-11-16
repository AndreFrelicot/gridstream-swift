//
//  FilterChipRow.swift
//  gridstream-ipad
//

import SwiftUI

/// A horizontal scrollable row of active filter chips.
/// Each chip displays the filter type and value with an "X" button to remove it.
struct FilterChipRow: View {
    let filters: ContentLibraryFilters
    let onRemove: (FilterChip) -> Void

    var body: some View {
        if !filters.activeChips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filters.activeChips) { chip in
                        FilterChipView(chip: chip, onRemove: {
                            onRemove(chip)
                        })
                    }

                    if filters.activeChips.count > 1 {
                        clearAllButton
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var clearAllButton: some View {
        Button {
            // Remove all chips one by one
            for chip in filters.activeChips {
                onRemove(chip)
            }
        } label: {
            Text("Clear All")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.systemGray5))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear all filters")
    }
}

// MARK: - Single Filter Chip View

/// A single filter chip with label and remove button.
struct FilterChipView: View {
    let chip: FilterChip
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            chipIcon

            Text(chip.displayText)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(chip.displayText) filter")
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(chipBackground)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var chipIcon: some View {
        switch chip {
        case .tagFilter:
            Circle()
                .fill(chip.color)
                .frame(width: 8, height: 8)
        case .minRating, .maxRating:
            Image(systemName: "heart.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white)
        case .sourceDirectory:
            Image(systemName: "folder.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white)
        case .search:
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.white)
        case .unplayed:
            Image(systemName: "play.slash.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white)
        case .played:
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10))
                .foregroundStyle(.white)
        case .minPlayCount:
            Image(systemName: "play.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white)
        case .unrated:
            Image(systemName: "star.slash.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white)
        case .hasAnnotations:
            Image(systemName: "pencil.tip.crop.circle")
                .font(.system(size: 10))
                .foregroundStyle(.white)
        case .annotationCountMin, .annotationCountMax:
            Image(systemName: "pencil.tip")
                .font(.system(size: 10))
                .foregroundStyle(.white)
        case .hasTextAnnotations:
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white)
        case .annotationTextSearch:
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.white)
        }
    }

    private var chipBackground: some View {
        chip.color.opacity(0.85)
    }
}

// MARK: - Previews

#Preview("Multiple Filters") {
    var filters = ContentLibraryFilters()
    filters.searchText = "vacation"
    filters.activeTagFilters = [
        TagFilter(tag: TagInfo(id: UUID(), name: "action", color: "#EF4444", ratingEnabled: false)),
        TagFilter(tag: TagInfo(id: UUID(), name: "comedy", color: "#22C55E", ratingEnabled: true))
    ]
    filters.minRating = 5
    filters.sourceDirectoryId = "dir-1"
    filters.sourceDirectoryName = "My Videos"

    return FilterChipRow(
        filters: filters,
        onRemove: { chip in
            print("Remove: \(chip.displayText)")
        }
    )
    .padding()
}

#Preview("Single Tag Filter") {
    var filters = ContentLibraryFilters()
    filters.activeTagFilters = [
        TagFilter(tag: TagInfo(id: UUID(), name: "favorites", color: "#EC4899", ratingEnabled: false))
    ]

    return FilterChipRow(
        filters: filters,
        onRemove: { _ in }
    )
    .padding()
}

#Preview("Rating Filters") {
    var filters = ContentLibraryFilters()
    filters.minRating = 3
    filters.maxRating = 8

    return FilterChipRow(
        filters: filters,
        onRemove: { _ in }
    )
    .padding()
}

#Preview("Play Count Filters") {
    var filters = ContentLibraryFilters()
    filters.unplayedOnly = true
    filters.minPlayCount = 3

    return FilterChipRow(
        filters: filters,
        onRemove: { _ in }
    )
    .padding()
}

#Preview("Search Only") {
    var filters = ContentLibraryFilters()
    filters.searchText = "summer vacation 2024"

    return FilterChipRow(
        filters: filters,
        onRemove: { _ in }
    )
    .padding()
}

#Preview("Empty Filters") {
    let filters = ContentLibraryFilters()

    return VStack {
        Text("No chips should appear below:")
            .font(.caption)
        FilterChipRow(
            filters: filters,
            onRemove: { _ in }
        )
    }
    .padding()
}

#Preview("All Filter Types") {
    var filters = ContentLibraryFilters()
    filters.searchText = "beach"
    filters.activeTagFilters = [
        TagFilter(tag: TagInfo(id: UUID(), name: "summer", color: "#F59E0B", ratingEnabled: false)),
        TagFilter(tag: TagInfo(id: UUID(), name: "travel", color: "#3B82F6", ratingEnabled: true), minRating: 5),
        TagFilter(tag: TagInfo(id: UUID(), name: "family", color: "#10B981", ratingEnabled: false))
    ]
    filters.minRating = 7
    filters.maxRating = 10
    filters.sourceDirectoryId = "vacation-2024"
    filters.sourceDirectoryName = "Vacation 2024"
    filters.unplayedOnly = true
    filters.minPlayCount = 2

    return FilterChipRow(
        filters: filters,
        onRemove: { _ in }
    )
    .padding()
}

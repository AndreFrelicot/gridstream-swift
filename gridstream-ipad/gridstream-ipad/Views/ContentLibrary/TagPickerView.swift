//
//  TagPickerView.swift
//  gridstream-ipad
//

import SwiftUI

/// A multi-select tag picker presented as a sheet or popover.
/// Displays all available tags with color indicators and checkmarks for selected tags.
/// Used to apply tags to one or more videos in the Content Library.
struct TagPickerView: View {
    let availableTags: [TagInfo]
    @Binding var selectedTagIds: Set<UUID>
    let onApply: () -> Void
    let onDismiss: () -> Void

    @State private var localSelection: Set<UUID>

    init(
        availableTags: [TagInfo],
        selectedTagIds: Binding<Set<UUID>>,
        onApply: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.availableTags = availableTags
        self._selectedTagIds = selectedTagIds
        self.onApply = onApply
        self.onDismiss = onDismiss
        self._localSelection = State(initialValue: selectedTagIds.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Group {
                if availableTags.isEmpty {
                    emptyStateView
                } else {
                    tagListView
                }
            }
            .navigationTitle("Select Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        selectedTagIds = localSelection
                        onApply()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Tag List View

    private var tagListView: some View {
        List {
            ForEach(availableTags) { tag in
                TagPickerRow(
                    tag: tag,
                    isSelected: localSelection.contains(tag.id),
                    onToggle: {
                        toggleSelection(for: tag.id)
                    }
                )
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Tags Available",
            systemImage: "tag.slash",
            description: Text("Create tags in Tag Management to organize your videos.")
        )
    }

    // MARK: - Selection Logic

    private func toggleSelection(for tagId: UUID) {
        if localSelection.contains(tagId) {
            localSelection.remove(tagId)
        } else {
            localSelection.insert(tagId)
        }
    }
}

// MARK: - Tag Picker Row

/// Individual row in the tag picker showing tag name, color, and selection state.
private struct TagPickerRow: View {
    let tag: TagInfo
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Color indicator
                Circle()
                    .fill(tag.swiftUIColor)
                    .frame(width: 16, height: 16)

                // Tag name
                Text(tag.name)
                    .foregroundStyle(.primary)

                // Rating enabled indicator
                if tag.ratingEnabled {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Selection checkmark
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tag.name) tag")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Double tap to deselect" : "Double tap to select")
    }
}

// MARK: - Previews

#Preview("With Tags") {
    struct PreviewWrapper: View {
        @State private var selectedIds: Set<UUID> = []

        let tags = [
            TagInfo(id: UUID(), name: "action", color: "#EF4444", ratingEnabled: false),
            TagInfo(id: UUID(), name: "comedy", color: "#22C55E", ratingEnabled: true),
            TagInfo(id: UUID(), name: "drama", color: "#3B82F6", ratingEnabled: false),
            TagInfo(id: UUID(), name: "documentary", color: "#F97316", ratingEnabled: true),
            TagInfo(id: UUID(), name: "horror", color: "#A855F7", ratingEnabled: false)
        ]

        var body: some View {
            TagPickerView(
                availableTags: tags,
                selectedTagIds: $selectedIds,
                onApply: { print("Applied tags: \(selectedIds)") },
                onDismiss: { print("Dismissed") }
            )
        }
    }

    return PreviewWrapper()
}

#Preview("With Pre-selected Tags") {
    struct PreviewWrapper: View {
        let tags = [
            TagInfo(id: UUID(), name: "action", color: "#EF4444", ratingEnabled: false),
            TagInfo(id: UUID(), name: "comedy", color: "#22C55E", ratingEnabled: true),
            TagInfo(id: UUID(), name: "drama", color: "#3B82F6", ratingEnabled: false)
        ]

        @State private var selectedIds: Set<UUID>

        init() {
            let preselected = [tags[1].id]
            _selectedIds = State(initialValue: Set(preselected))
        }

        var body: some View {
            TagPickerView(
                availableTags: tags,
                selectedTagIds: $selectedIds,
                onApply: {},
                onDismiss: {}
            )
        }
    }

    return PreviewWrapper()
}

#Preview("Empty State") {
    struct PreviewWrapper: View {
        @State private var selectedIds: Set<UUID> = []

        var body: some View {
            TagPickerView(
                availableTags: [],
                selectedTagIds: $selectedIds,
                onApply: {},
                onDismiss: {}
            )
        }
    }

    return PreviewWrapper()
}

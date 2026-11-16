//
//  BulkOperationsBar.swift
//  gridstream-ipad
//

import SwiftUI

/// A toolbar displayed when multiple videos are selected in the Content Library.
/// Provides bulk operations like applying tags, setting ratings, and clearing selection.
struct BulkOperationsBar: View {
    let selectedCount: Int
    let onApplyTags: () -> Void
    let onSetRating: () -> Void
    var onAddToList: (() -> Void)? = nil
    let onClearSelection: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Selection count
            selectionCountLabel

            Spacer()

            // Action buttons
            actionButtons
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: - Selection Count Label

    private var selectionCountLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.accentColor)

            Text(selectionText)
                .fontWeight(.medium)
        }
        .accessibilityLabel(selectionText)
    }

    private var selectionText: String {
        String(localized: "\(selectedCount) videos selected")
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                onApplyTags()
            } label: {
                Label("Tags", systemImage: "tag")
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Apply tags to selected videos")

            Button {
                onSetRating()
            } label: {
                Label("Rate", systemImage: "heart")
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Set rating for selected videos")

            if let onAddToList = onAddToList {
                Button {
                    onAddToList()
                } label: {
                    Label("Add", systemImage: "text.badge.plus")
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Add selected videos to a list")
            }

            Button {
                onClearSelection()
            } label: {
                Label("Clear", systemImage: "xmark")
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.secondary)
            .accessibilityLabel("Clear selection")
        }
    }
}

// MARK: - Bulk Rating Picker

/// A sheet for setting a rating on multiple selected videos.
struct BulkRatingPickerView: View {
    @Binding var rating: Int
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Set rating for all selected videos")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HeartRatingView(
                    rating: $rating,
                    maxRating: 10,
                    size: .large,
                    isEditable: true
                )

                Text("\(rating) of 10")
                    .font(.title3)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Set Rating")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Previews

#Preview("Single Selection") {
    VStack {
        Spacer()
        BulkOperationsBar(
            selectedCount: 1,
            onApplyTags: { print("Apply tags") },
            onSetRating: { print("Set rating") },
            onAddToList: { print("Add to list") },
            onClearSelection: { print("Clear selection") }
        )
    }
}

#Preview("Multiple Selection") {
    VStack {
        Spacer()
        BulkOperationsBar(
            selectedCount: 5,
            onApplyTags: { print("Apply tags") },
            onSetRating: { print("Set rating") },
            onAddToList: { print("Add to list") },
            onClearSelection: { print("Clear selection") }
        )
    }
}

#Preview("Large Selection") {
    VStack {
        Spacer()
        BulkOperationsBar(
            selectedCount: 42,
            onApplyTags: { print("Apply tags") },
            onSetRating: { print("Set rating") },
            onAddToList: { print("Add to list") },
            onClearSelection: { print("Clear selection") }
        )
    }
}

#Preview("Bulk Rating Picker") {
    struct PreviewWrapper: View {
        @State private var rating = 7
        @State private var isPresented = true

        var body: some View {
            Color.gray.opacity(0.3)
                .sheet(isPresented: $isPresented) {
                    BulkRatingPickerView(
                        rating: $rating,
                        onApply: { print("Applied rating: \(rating)") },
                        onDismiss: { isPresented = false }
                    )
                }
        }
    }

    return PreviewWrapper()
}

#Preview("In Context") {
    VStack(spacing: 0) {
        // Simulated content area
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 16) {
                ForEach(0..<12) { index in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.2))
                        .aspectRatio(16/9, contentMode: .fit)
                        .overlay {
                            Text("Video \(index + 1)")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .padding()
        }

        // Bulk operations bar at bottom
        BulkOperationsBar(
            selectedCount: 3,
            onApplyTags: {},
            onSetRating: {},
            onAddToList: {},
            onClearSelection: {}
        )
    }
}

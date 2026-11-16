//
//  SmartListManagementView.swift
//  gridstream-ipad
//

import GridStreamAPI
import SwiftUI

/// List view for managing Smart Lists (Tab 2 in TabbedManagementSheet).
/// Shows all Smart Lists with name and condition summary.
/// Provides create, edit, and delete functionality.
///
/// The form view handles service calls directly, so this view only needs
/// to update local state when receiving results via onCreated/onUpdated callbacks.
struct SmartListManagementView: View {
    @Binding var smartLists: [SmartListInfo]
    let smartListVideoCounts: [UUID: Int]
    let tags: [TagInfo]
    let sourceDirectories: [SourceDirectoryDTO]
    let simpleLists: [SimpleListDTO]
    let tiles: [Tile]
    let targetTileIndex: Int?
    let activePreset: LayoutPreset?
    let orientation: LayoutOrientation
    let serverURL: URL?
    let onDeleteSmartList: (UUID) async throws -> Void
    let onApplyToTile: (SmartListInfo, Int) -> Void

    @State private var isShowingCreateForm = false
    @State private var smartListToEdit: SmartListInfo?
    @State private var smartListToDelete: SmartListInfo?
    @State private var showDeleteConfirmation = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var smartListToApply: SmartListInfo?

    private let maxSmartListCount = 50

    var body: some View {
        Group {
            if smartLists.isEmpty {
                emptyStateView
            } else {
                smartListView
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingCreateForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(smartLists.count >= maxSmartListCount)
                .accessibilityLabel("Create smart list")
            }
        }
        .sheet(isPresented: $isShowingCreateForm) {
            SmartListFormView(
                mode: .create,
                existingNames: Set(smartLists.map { $0.name.lowercased() }),
                tags: tags,
                sourceDirectories: sourceDirectories,
                simpleLists: simpleLists,
                smartLists: smartLists,
                tiles: tiles,
                serverURL: serverURL,
                onCreated: handleCreated,
                onUpdated: { _ in },  // Not used in create mode
                onCancel: { isShowingCreateForm = false },
                onApplyToTile: onApplyToTile
            )
        }
        .sheet(item: $smartListToEdit) { smartList in
            SmartListFormView(
                mode: .edit(smartList),
                existingNames: Set(smartLists.filter { $0.id != smartList.id }.map { $0.name.lowercased() }),
                tags: tags,
                sourceDirectories: sourceDirectories,
                simpleLists: simpleLists,
                smartLists: smartLists,
                tiles: tiles,
                serverURL: serverURL,
                onCreated: { _ in },  // Not used in edit mode
                onUpdated: handleUpdated,
                onCancel: { smartListToEdit = nil },
                onApplyToTile: onApplyToTile
            )
        }
        .alert("Delete Smart List", isPresented: $showDeleteConfirmation, presenting: smartListToDelete) { smartList in
            Button("Cancel", role: .cancel) {
                smartListToDelete = nil
            }
            Button("Delete", role: .destructive) {
                handleDelete(smartList)
            }
        } message: { smartList in
            Text("Are you sure you want to delete \"\(smartList.name)\"? This cannot be undone.")
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? String(localized: "An error occurred"))
        }
        .sheet(item: $smartListToApply) { smartList in
            TilePickerSheet(
                tiles: tiles,
                listName: smartList.name,
                activePreset: activePreset,
                orientation: orientation,
                currentTileIndex: targetTileIndex,
                onApply: { tileIndex in
                    onApplyToTile(smartList, tileIndex)
                    smartListToApply = nil
                },
                onCancel: {
                    smartListToApply = nil
                }
            )
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Smart Lists", systemImage: "list.bullet.rectangle")
        } description: {
            Text("Create Smart Lists to automatically filter videos based on tags, ratings, and more.")
        } actions: {
            Button("Create Smart List") {
                isShowingCreateForm = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Smart List View

    private var smartListView: some View {
        List {
            Section {
                ForEach(smartLists) { smartList in
                    SmartListRow(
                        smartList: smartList,
                        videoCount: smartListVideoCounts[smartList.id],
                        hasTargetTile: targetTileIndex != nil,
                        onApplyToTile: {
                            if let tileIndex = targetTileIndex {
                                onApplyToTile(smartList, tileIndex)
                            } else {
                                smartListToApply = smartList
                            }
                        }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            smartListToDelete = smartList
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            smartListToEdit = smartList
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            } footer: {
                smartListCountFooter
            }
        }
        .listStyle(.insetGrouped)
    }

    private var smartListCountFooter: some View {
        Text("\(smartLists.count) of \(maxSmartListCount) smart lists used")
            .foregroundStyle(smartLists.count >= maxSmartListCount ? .red : .secondary)
    }

    // MARK: - Result Handlers

    /// Called when a Smart List is successfully created by the form.
    /// The form handles the service call directly, so we just update local state.
    private func handleCreated(_ smartList: SmartListInfo) {
        smartLists.append(smartList)
        isShowingCreateForm = false
    }

    /// Called when a Smart List is successfully updated by the form.
    /// The form handles the service call directly, so we just update local state.
    private func handleUpdated(_ smartList: SmartListInfo) {
        if let index = smartLists.firstIndex(where: { $0.id == smartList.id }) {
            smartLists[index] = smartList
        }
        smartListToEdit = nil
    }

    private func handleDelete(_ smartList: SmartListInfo) {
        Task {
            do {
                try await onDeleteSmartList(smartList.id)
                await MainActor.run {
                    smartLists.removeAll { $0.id == smartList.id }
                    smartListToDelete = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }
}

// MARK: - Smart List Row

private struct SmartListRow: View {
    let smartList: SmartListInfo
    let videoCount: Int?
    let hasTargetTile: Bool
    let onApplyToTile: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(smartList.name)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text(smartList.criteria.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let count = videoCount {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text("\(count) videos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Button(action: onApplyToTile) {
                Label(hasTargetTile ? "Apply" : "Apply...", systemImage: "square.grid.2x2")
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .accessibilityLabel(hasTargetTile ? "Apply \(smartList.name) to tile" : "Apply \(smartList.name) to a tile")
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(smartList.name), \(String(localized: smartList.criteria.summary))")
    }
}

// MARK: - Previews

#Preview("With Smart Lists") {
    struct PreviewWrapper: View {
        @State private var smartLists = [
            SmartListInfo(
                name: "Favorites",
                criteria: SmartListCriteria(conditions: [
                    FilterCondition(criteriaType: .ratingMin(value: 4), logicOperator: .and)
                ])
            ),
            SmartListInfo(
                name: "Recently Played",
                criteria: SmartListCriteria(conditions: [
                    FilterCondition(criteriaType: .playCountMin(value: 1), logicOperator: .and),
                    FilterCondition(criteriaType: .dateAddedAfter(date: Date().addingTimeInterval(-86400 * 7)), logicOperator: .and)
                ])
            )
        ]

        var body: some View {
            NavigationStack {
                SmartListManagementView(
                    smartLists: $smartLists,
                    smartListVideoCounts: [:],
                    tags: [],
                    sourceDirectories: [],
                    simpleLists: [],
                    tiles: [],
                    targetTileIndex: nil,
                    activePreset: .symmetric,
                    orientation: .horizontal,
                    serverURL: URL(string: "http://localhost:8080"),
                    onDeleteSmartList: { _ in },
                    onApplyToTile: { _, _ in }
                )
                .navigationTitle("Smart Lists")
            }
        }
    }

    return PreviewWrapper()
}

#Preview("Empty State") {
    struct PreviewWrapper: View {
        @State private var smartLists: [SmartListInfo] = []

        var body: some View {
            NavigationStack {
                SmartListManagementView(
                    smartLists: $smartLists,
                    smartListVideoCounts: [:],
                    tags: [],
                    sourceDirectories: [],
                    simpleLists: [],
                    tiles: [],
                    targetTileIndex: nil,
                    activePreset: .symmetric,
                    orientation: .horizontal,
                    serverURL: URL(string: "http://localhost:8080"),
                    onDeleteSmartList: { _ in },
                    onApplyToTile: { _, _ in }
                )
                .navigationTitle("Smart Lists")
            }
        }
    }

    return PreviewWrapper()
}

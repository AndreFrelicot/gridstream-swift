//
//  SimpleListManagementView.swift
//  gridstream-ipad
//

import GridStreamAPI
import SwiftUI

struct SimpleListManagementView: View {
    @Binding var simpleLists: [SimpleListDTO]
    let tiles: [Tile]
    let targetTileIndex: Int?
    let activePreset: LayoutPreset?
    let orientation: LayoutOrientation
    let serverURL: URL?
    let onDeleteSimpleList: (UUID) async throws -> Void
    let onApplyToTile: (SimpleListDTO, Int) -> Void

    @State private var isShowingCreateForm = false
    @State private var simpleListToEdit: SimpleListDTO?
    @State private var simpleListToDelete: SimpleListDTO?
    @State private var showDeleteConfirmation = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var simpleListToApply: SimpleListDTO?

    private let maxSimpleListCount = 50

    var body: some View {
        Group {
            if simpleLists.isEmpty {
                emptyStateView
            } else {
                simpleListView
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingCreateForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(simpleLists.count >= maxSimpleListCount)
                .accessibilityLabel("Create simple list")
            }
        }
        .sheet(isPresented: $isShowingCreateForm) {
            SimpleListFormView(
                mode: .create,
                existingNames: Set(simpleLists.map { $0.name.lowercased() }),
                tiles: tiles,
                serverURL: serverURL,
                onCreated: handleCreated,
                onUpdated: { _ in },
                onCancel: { isShowingCreateForm = false },
                onApplyToTile: onApplyToTile
            )
        }
        .sheet(item: $simpleListToEdit) { simpleList in
            SimpleListFormView(
                mode: .edit(simpleList),
                existingNames: Set(simpleLists.filter { $0.id != simpleList.id }.map { $0.name.lowercased() }),
                tiles: tiles,
                serverURL: serverURL,
                onCreated: { _ in },
                onUpdated: handleUpdated,
                onCancel: { simpleListToEdit = nil },
                onApplyToTile: onApplyToTile
            )
        }
        .alert("Delete Simple List", isPresented: $showDeleteConfirmation, presenting: simpleListToDelete) { simpleList in
            Button("Cancel", role: .cancel) {
                simpleListToDelete = nil
            }
            Button("Delete", role: .destructive) {
                handleDelete(simpleList)
            }
        } message: { simpleList in
            Text("Are you sure you want to delete \"\(simpleList.name)\"? This cannot be undone.")
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? String(localized: "An error occurred"))
        }
        .sheet(item: $simpleListToApply) { simpleList in
            TilePickerSheet(
                tiles: tiles,
                listName: simpleList.name,
                activePreset: activePreset,
                orientation: orientation,
                currentTileIndex: targetTileIndex,
                onApply: { tileIndex in
                    onApplyToTile(simpleList, tileIndex)
                    simpleListToApply = nil
                },
                onCancel: {
                    simpleListToApply = nil
                }
            )
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Simple Lists", systemImage: "rectangle.stack")
        } description: {
            Text("Create Simple Lists to manually curate your favorite videos.")
        } actions: {
            Button("Create Simple List") {
                isShowingCreateForm = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Simple List View

    private var simpleListView: some View {
        List {
            Section {
                ForEach(simpleLists) { simpleList in
                    SimpleListRow(
                        simpleList: simpleList,
                        hasTargetTile: targetTileIndex != nil,
                        onApply: {
                            if let tileIndex = targetTileIndex {
                                onApplyToTile(simpleList, tileIndex)
                            } else {
                                simpleListToApply = simpleList
                            }
                        }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            simpleListToDelete = simpleList
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            simpleListToEdit = simpleList
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            } footer: {
                simpleListCountFooter
            }
        }
        .listStyle(.insetGrouped)
    }

    private var simpleListCountFooter: some View {
        Text("\(simpleLists.count) of \(maxSimpleListCount) simple lists used")
            .foregroundStyle(simpleLists.count >= maxSimpleListCount ? .red : .secondary)
    }

    // MARK: - Result Handlers

    private func handleCreated(_ simpleList: SimpleListDTO) {
        simpleLists.append(simpleList)
        isShowingCreateForm = false
    }

    private func handleUpdated(_ simpleList: SimpleListDTO) {
        if let index = simpleLists.firstIndex(where: { $0.id == simpleList.id }) {
            simpleLists[index] = simpleList
        }
        simpleListToEdit = nil
    }

    private func handleDelete(_ simpleList: SimpleListDTO) {
        Task {
            do {
                try await onDeleteSimpleList(simpleList.id)
                await MainActor.run {
                    simpleLists.removeAll { $0.id == simpleList.id }
                    simpleListToDelete = nil
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

// MARK: - Simple List Row

private struct SimpleListRow: View {
    let simpleList: SimpleListDTO
    let hasTargetTile: Bool
    let onApply: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack")
                .font(.title2)
                .foregroundStyle(.green)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(simpleList.name)
                    .fontWeight(.medium)

                Text("\(simpleList.videoCount) videos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onApply) {
                Label(hasTargetTile ? "Apply" : "Apply...", systemImage: "square.grid.2x2")
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .accessibilityLabel(hasTargetTile ? "Apply \(simpleList.name) to tile" : "Apply \(simpleList.name) to a tile")
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(simpleList.name), \(simpleList.videoCount) videos")
    }
}

#Preview("With Simple Lists") {
    struct PreviewWrapper: View {
        @State private var simpleLists = [
            SimpleListDTO(name: "Favorites", videoIds: ["v1", "v2", "v3"]),
            SimpleListDTO(name: "Watch Later", videoIds: ["v4"])
        ]

        var body: some View {
            NavigationStack {
                SimpleListManagementView(
                    simpleLists: $simpleLists,
                    tiles: [],
                    targetTileIndex: nil,
                    activePreset: .symmetric,
                    orientation: .horizontal,
                    serverURL: URL(string: "http://localhost:8080"),
                    onDeleteSimpleList: { _ in },
                    onApplyToTile: { _, _ in }
                )
            }
        }
    }

    return PreviewWrapper()
}

#Preview("Empty State") {
    struct PreviewWrapper: View {
        @State private var simpleLists: [SimpleListDTO] = []

        var body: some View {
            NavigationStack {
                SimpleListManagementView(
                    simpleLists: $simpleLists,
                    tiles: [],
                    targetTileIndex: nil,
                    activePreset: .symmetric,
                    orientation: .horizontal,
                    serverURL: URL(string: "http://localhost:8080"),
                    onDeleteSimpleList: { _ in },
                    onApplyToTile: { _, _ in }
                )
            }
        }
    }

    return PreviewWrapper()
}

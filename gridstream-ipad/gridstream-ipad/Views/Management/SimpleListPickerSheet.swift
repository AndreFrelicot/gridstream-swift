//
//  SimpleListPickerSheet.swift
//  gridstream-ipad
//

import GridStreamAPI
import SwiftUI

struct SimpleListPickerSheet: View {
    let videoIds: [String]
    let serverURL: URL?
    let onDismiss: () -> Void
    let onSuccess: (SimpleListDTO) -> Void

    @State private var simpleLists: [SimpleListDTO] = []
    @State private var isLoading = true
    @State private var error: Error?
    @State private var showCreateForm = false
    @State private var newListName = ""
    @State private var isCreating = false
    @State private var isAdding = false

    private let simpleListService = SimpleListService()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let error = error {
                    errorView(error)
                } else {
                    contentView
                }
            }
            .navigationTitle(videoIds.count == 1 ? "Add to List" : "Add \(videoIds.count) Videos to List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            await loadSimpleLists()
        }
    }

    // MARK: - Content View

    private var contentView: some View {
        List {
            createNewListSection

            if !simpleLists.isEmpty {
                existingListsSection
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Create New List Section

    private var createNewListSection: some View {
        Section {
            if showCreateForm {
                HStack {
                    TextField("List name", text: $newListName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit {
                            Task { await createNewList() }
                        }
                        .disabled(isCreating)

                    if isCreating {
                        ProgressView()
                            .padding(.leading, 8)
                    } else {
                        Button("Create") {
                            Task { await createNewList() }
                        }
                        .disabled(newListName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } else {
                Button {
                    showCreateForm = true
                } label: {
                    Label("Create New List", systemImage: "plus.circle.fill")
                }
            }
        }
    }

    // MARK: - Existing Lists Section

    private var existingListsSection: some View {
        Section("Your Lists") {
            ForEach(simpleLists) { list in
                Button {
                    Task { await addToList(list) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(list.name)
                                .foregroundStyle(.primary)

                            Text("\(list.videoCount) videos")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if isAdding {
                            ProgressView()
                        } else {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isAdding)
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading lists...")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Error View

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView {
            Label("Unable to Load Lists", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Retry") {
                Task { await loadSimpleLists() }
            }
        }
    }

    // MARK: - Data Loading

    private func loadSimpleLists() async {
        guard let serverURL = serverURL else {
            error = APIError.invalidURL
            isLoading = false
            return
        }

        isLoading = true
        error = nil

        do {
            simpleLists = try await simpleListService.fetchSimpleLists(from: serverURL)
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }

    // MARK: - Create New List

    private func createNewList() async {
        guard let serverURL = serverURL else { return }

        let trimmedName = newListName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        isCreating = true

        do {
            let newList = try await simpleListService.createSimpleList(name: trimmedName, serverURL: serverURL)
            let updatedList = try await simpleListService.addVideosToList(videoIds: videoIds, listId: newList.id, serverURL: serverURL)
            onSuccess(updatedList)
        } catch {
            self.error = error
            isCreating = false
        }
    }

    // MARK: - Add to Existing List

    private func addToList(_ list: SimpleListDTO) async {
        guard let serverURL = serverURL else { return }

        isAdding = true

        do {
            let updatedList = try await simpleListService.addVideosToList(videoIds: videoIds, listId: list.id, serverURL: serverURL)
            onSuccess(updatedList)
        } catch {
            self.error = error
            isAdding = false
        }
    }
}

#Preview("Single Video") {
    SimpleListPickerSheet(
        videoIds: ["video-123"],
        serverURL: URL(string: "http://localhost:8080"),
        onDismiss: { print("Dismissed") },
        onSuccess: { list in print("Added to \(list.name)") }
    )
}

#Preview("Multiple Videos") {
    SimpleListPickerSheet(
        videoIds: ["video-1", "video-2", "video-3"],
        serverURL: URL(string: "http://localhost:8080"),
        onDismiss: { print("Dismissed") },
        onSuccess: { list in print("Added to \(list.name)") }
    )
}

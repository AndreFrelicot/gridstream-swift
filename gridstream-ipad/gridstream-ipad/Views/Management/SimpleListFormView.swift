//
//  SimpleListFormView.swift
//  gridstream-ipad
//

import GridStreamAPI
import SwiftUI

struct SimpleListFormView: View {
    enum Mode {
        case create
        case edit(SimpleListDTO)

        var title: LocalizedStringResource {
            switch self {
            case .create: return "Create Simple List"
            case .edit: return "Edit Simple List"
            }
        }

        var saveButtonTitle: LocalizedStringResource {
            switch self {
            case .create: return "Create"
            case .edit: return "Save"
            }
        }

        var simpleListId: UUID? {
            switch self {
            case .create: return nil
            case .edit(let simpleList): return simpleList.id
            }
        }
    }

    let mode: Mode
    let existingNames: Set<String>
    let tiles: [Tile]
    let serverURL: URL?
    let onCreated: (SimpleListDTO) -> Void
    let onUpdated: (SimpleListDTO) -> Void
    let onCancel: () -> Void
    let onApplyToTile: (SimpleListDTO, Int) -> Void

    @State private var name: String = ""
    @State private var sortOrder: SimpleListSortOrder = .filename
    @State private var isSaving = false
    @State private var saveError: Error?
    @State private var showSaveError = false

    private let simpleListService = SimpleListService()

    init(
        mode: Mode,
        existingNames: Set<String>,
        tiles: [Tile],
        serverURL: URL?,
        onCreated: @escaping (SimpleListDTO) -> Void,
        onUpdated: @escaping (SimpleListDTO) -> Void,
        onCancel: @escaping () -> Void,
        onApplyToTile: @escaping (SimpleListDTO, Int) -> Void
    ) {
        self.mode = mode
        self.existingNames = existingNames
        self.tiles = tiles
        self.serverURL = serverURL
        self.onCreated = onCreated
        self.onUpdated = onUpdated
        self.onCancel = onCancel
        self.onApplyToTile = onApplyToTile

        if case .edit(let simpleList) = mode {
            _name = State(initialValue: simpleList.name)
            _sortOrder = State(initialValue: simpleList.sortOrder)
        }
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isNameValid: Bool {
        !normalizedName.isEmpty && !existingNames.contains(normalizedName.lowercased())
    }

    private var nameValidationMessage: String? {
        let trimmed = normalizedName
        if trimmed.isEmpty {
            return nil
        }
        if existingNames.contains(trimmed.lowercased()) {
            return String(localized: "A simple list with this name already exists")
        }
        return nil
    }

    private var canSave: Bool {
        isNameValid && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("List name", text: $name)
                        .textInputAutocapitalization(.words)

                    if let message = nameValidationMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Sort Order") {
                    Picker("Sort by", selection: $sortOrder) {
                        ForEach(SimpleListSortOrder.allCases, id: \.self) { order in
                            Text(order.displayName).tag(order)
                        }
                    }
                }

                if case .edit(let simpleList) = mode {
                    Section("Videos") {
                        if simpleList.videoCount == 0 {
                            Text("No videos in this list")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(simpleList.videoCount) videos in this list")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.saveButtonTitle) {
                        Task { await save() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .alert("Error Saving", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {
                    saveError = nil
                }
            } message: {
                Text(saveError?.localizedDescription ?? String(localized: "An error occurred"))
            }
            .overlay {
                if isSaving {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView("Saving...")
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - Save

    private func save() async {
        guard let serverURL = serverURL else {
            saveError = APIError.invalidURL
            showSaveError = true
            return
        }

        isSaving = true

        do {
            switch mode {
            case .create:
                let created = try await simpleListService.createSimpleList(name: normalizedName, serverURL: serverURL)
                await MainActor.run {
                    isSaving = false
                    onCreated(created)
                }

            case .edit(let simpleList):
                let updated = try await simpleListService.updateSimpleList(
                    id: simpleList.id,
                    name: normalizedName,
                    sortOrder: sortOrder,
                    serverURL: serverURL
                )
                await MainActor.run {
                    isSaving = false
                    onUpdated(updated)
                }
            }
        } catch {
            await MainActor.run {
                isSaving = false
                saveError = error
                showSaveError = true
            }
        }
    }
}

#Preview("Create Mode") {
    SimpleListFormView(
        mode: .create,
        existingNames: ["existing list"],
        tiles: [],
        serverURL: URL(string: "http://localhost:8080"),
        onCreated: { _ in },
        onUpdated: { _ in },
        onCancel: {},
        onApplyToTile: { _, _ in }
    )
}

#Preview("Edit Mode") {
    SimpleListFormView(
        mode: .edit(SimpleListDTO(name: "My List", videoIds: ["v1", "v2", "v3"])),
        existingNames: [],
        tiles: [],
        serverURL: URL(string: "http://localhost:8080"),
        onCreated: { _ in },
        onUpdated: { _ in },
        onCancel: {},
        onApplyToTile: { _, _ in }
    )
}

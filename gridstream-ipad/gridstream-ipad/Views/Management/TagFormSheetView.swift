//
//  TagFormSheetView.swift
//  gridstream-ipad
//

import GridStreamAPI
import SwiftUI

/// Form view for creating or editing a tag.
/// This view calls ContentLibraryService directly to avoid callback chain corruption issues.
/// The onCreated/onUpdated callbacks only receive the result after the service call completes.
struct TagFormSheetView: View {
    enum Mode {
        case create
        case edit(TagInfo)

        var title: LocalizedStringResource {
            switch self {
            case .create: return "Create Tag"
            case .edit: return "Edit Tag"
            }
        }

        var saveButtonTitle: LocalizedStringResource {
            switch self {
            case .create: return "Create"
            case .edit: return "Save"
            }
        }

        var tagId: UUID? {
            switch self {
            case .create: return nil
            case .edit(let tag): return tag.id
            }
        }
    }

    let mode: Mode
    let existingTagNames: Set<String>
    let serverURL: URL?
    let onCreated: (TagInfo) -> Void
    let onUpdated: (TagInfo) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var selectedColor: String = TagColorPalette.red
    @State private var tagDescription: String = ""
    @State private var ratingEnabled: Bool = false
    @State private var isSaving = false
    @State private var saveError: Error?
    @State private var showSaveError = false

    private let contentLibraryService = ContentLibraryService()

    init(
        mode: Mode,
        existingTagNames: Set<String>,
        serverURL: URL?,
        onCreated: @escaping (TagInfo) -> Void,
        onUpdated: @escaping (TagInfo) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.existingTagNames = existingTagNames
        self.serverURL = serverURL
        self.onCreated = onCreated
        self.onUpdated = onUpdated
        self.onCancel = onCancel

        if case .edit(let tag) = mode {
            _name = State(initialValue: tag.name)
            _selectedColor = State(initialValue: tag.color)
            _tagDescription = State(initialValue: "")
            _ratingEnabled = State(initialValue: tag.ratingEnabled)
        }
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isNameValid: Bool {
        !normalizedName.isEmpty && !existingTagNames.contains(normalizedName)
    }

    private var nameValidationMessage: String? {
        if normalizedName.isEmpty {
            return nil
        }
        if existingTagNames.contains(normalizedName) {
            return String(localized: "A tag with this name already exists")
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tag Name", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if let validationMessage = nameValidationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Name")
                } footer: {
                    Text("Tag names are case-insensitive and will be normalized to lowercase.")
                }

                Section("Color") {
                    ColorPaletteView(selectedColor: $selectedColor)
                }

                Section("Description (Optional)") {
                    TextField("Description", text: $tagDescription, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Toggle("Enable Per-Tag Rating", isOn: $ratingEnabled)
                } footer: {
                    Text("When enabled, videos with this tag can have a separate rating specific to this tag.")
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
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(mode.saveButtonTitle) {
                            Task {
                                await saveTag()
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(!isNameValid)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .alert("Error", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {
                    saveError = nil
                }
            } message: {
                Text(saveError?.localizedDescription ?? String(localized: "An error occurred"))
            }
        }
    }

    // MARK: - Save Tag (Direct Service Call)

    private func saveTag() async {
        guard let serverURL = serverURL else {
            saveError = APIError.invalidURL
            showSaveError = true
            return
        }

        isSaving = true

        let tagName = normalizedName
        let tagColor = selectedColor
        let tagDescription = tagDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagRatingEnabled = ratingEnabled

        do {
            switch mode {
            case .create:
                let createdTag = try await contentLibraryService.createTag(
                    name: tagName,
                    color: tagColor,
                    description: tagDescription.isEmpty ? nil : tagDescription,
                    ratingEnabled: tagRatingEnabled,
                    serverURL: serverURL
                )
                onCreated(createdTag)

            case .edit(let existingTag):
                let updatedTag = try await contentLibraryService.updateTag(
                    id: existingTag.id,
                    name: tagName,
                    color: tagColor,
                    description: tagDescription.isEmpty ? nil : tagDescription,
                    ratingEnabled: tagRatingEnabled,
                    serverURL: serverURL
                )
                onUpdated(updatedTag)
            }
        } catch {
            saveError = error
            showSaveError = true
        }

        isSaving = false
    }
}

// MARK: - Color Palette View

struct ColorPaletteView: View {
    @Binding var selectedColor: String

    private let columns = [
        GridItem(.adaptive(minimum: 44), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(TagColorPalette.allColors, id: \.self) { color in
                ColorSwatchButtonView(
                    color: color,
                    isSelected: selectedColor == color,
                    onSelect: {
                        selectedColor = color
                    }
                )
            }
        }
        .padding(.vertical, 8)
    }
}

struct ColorSwatchButtonView: View {
    let color: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                Circle()
                    .fill(Color(hex: color) ?? .gray)
                    .frame(width: 36, height: 36)

                if isSelected {
                    Circle()
                        .stroke(Color.primary, lineWidth: 3)
                        .frame(width: 44, height: 44)

                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(colorName(for: color))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func colorName(for hex: String) -> LocalizedStringResource {
        switch hex {
        case TagColorPalette.red: return "Red"
        case TagColorPalette.orange: return "Orange"
        case TagColorPalette.amber: return "Amber"
        case TagColorPalette.green: return "Green"
        case TagColorPalette.emerald: return "Emerald"
        case TagColorPalette.cyan: return "Cyan"
        case TagColorPalette.blue: return "Blue"
        case TagColorPalette.violet: return "Violet"
        case TagColorPalette.purple: return "Purple"
        case TagColorPalette.pink: return "Pink"
        default: return "Color"
        }
    }
}

// MARK: - Previews

#Preview("Create Tag") {
    TagFormSheetView(
        mode: .create,
        existingTagNames: ["action", "comedy"],
        serverURL: URL(string: "http://localhost:8080"),
        onCreated: { _ in },
        onUpdated: { _ in },
        onCancel: {}
    )
}

#Preview("Edit Tag") {
    let tag = TagInfo(id: UUID(), name: "drama", color: "#3B82F6", ratingEnabled: true)
    return TagFormSheetView(
        mode: .edit(tag),
        existingTagNames: ["action", "comedy"],
        serverURL: URL(string: "http://localhost:8080"),
        onCreated: { _ in },
        onUpdated: { _ in },
        onCancel: {}
    )
}

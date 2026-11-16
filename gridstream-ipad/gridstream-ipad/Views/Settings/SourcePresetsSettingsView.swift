//
//  SourcePresetsSettingsView.swift
//  gridstream-ipad
//

import GridStreamAPI
import SwiftUI

struct SourcePresetsSettingsView: View {
    @Environment(GridState.self) private var gridState
    @Environment(SourcePresetService.self) private var presetService: SourcePresetService?
    @Environment(SharedPlayerPool.self) private var playerPool
    @Environment(VideoHistoryManager.self) private var historyManager

    let smartLists: [SmartListInfo]
    let simpleLists: [SimpleListDTO]
    var onDismiss: (() -> Void)?

    @State private var presets: [SourcePreset] = []
    @State private var newPresetName: String = ""
    @State private var showingDeleteConfirmation = false
    @State private var presetToDelete: SourcePreset?
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var applicationWarnings: [String] = []
    @State private var showingWarnings = false

    var body: some View {
        Form {
            // Save Current Section
            Section {
                HStack {
                    TextField("Preset Name", text: $newPresetName)
                    Button("Save") {
                        saveCurrentConfiguration()
                    }
                    .disabled(newPresetName.isEmpty)
                }
            } header: {
                Text("Save Current Configuration")
            } footer: {
                Text("Save your current \(gridState.tileCount) tile layout as a named preset.")
            }

            // Saved Presets Section
            Section {
                if presets.isEmpty {
                    Text("No saved presets")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(presets) { preset in
                        presetRow(preset)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    presetToDelete = preset
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            } header: {
                Text("Saved Presets")
            }

            // Info Section
            Section {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Presets save the tile count and source assignments (Smart Lists, Simple Lists, or direct videos) for quick recall.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .onAppear {
            loadPresets()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? String(localized: "An error occurred"))
        }
        .alert("Preset Applied", isPresented: $showingWarnings) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(applicationWarnings.joined(separator: "\n"))
        }
        .confirmationDialog("Delete Preset?", isPresented: $showingDeleteConfirmation, presenting: presetToDelete) { preset in
            Button("Delete", role: .destructive) {
                deletePreset(preset)
            }
            Button("Cancel", role: .cancel) { }
        } message: { preset in
            Text("Are you sure you want to delete '\(preset.name)'?")
        }
    }

    @ViewBuilder
    private func presetRow(_ preset: SourcePreset) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .fontWeight(.medium)
                Text(presetSummary(preset))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Load") {
                loadPreset(preset)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 8)
    }

    private func presetSummary(_ preset: SourcePreset) -> String {
        let configs = preset.tileConfigs
        let smartCount = configs.filter { $0.sourceType == .smartList }.count
        let simpleCount = configs.filter { $0.sourceType == .simpleList }.count
        let videoCount = configs.filter { $0.sourceType == .directVideo }.count

        var parts: [String] = [String(localized: "\(preset.tileCount) tiles")]
        if smartCount > 0 { parts.append(String(localized: "\(smartCount) smart")) }
        if simpleCount > 0 { parts.append(String(localized: "\(simpleCount) simple")) }
        if videoCount > 0 { parts.append(String(localized: "\(videoCount) video")) }

        return parts.joined(separator: ", ")
    }

    private func loadPresets() {
        presets = presetService?.fetchAllPresets() ?? []
    }

    private func saveCurrentConfiguration() {
        guard let service = presetService else { return }

        do {
            let configs = gridState.exportTileConfigs()
            _ = try service.createPreset(name: newPresetName, tileCount: gridState.tileCount, configs: configs)
            newPresetName = ""
            loadPresets()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func loadPreset(_ preset: SourcePreset) {
        let result = SourcePresetApplicator.apply(
            preset,
            to: gridState,
            playerPool: playerPool,
            historyManager: historyManager,
            smartLists: smartLists,
            simpleLists: simpleLists
        )

        presetService?.markPresetAsUsed(preset)

        if !result.warnings.isEmpty {
            applicationWarnings = result.warnings
            showingWarnings = true
        }

        onDismiss?()
    }

    private func deletePreset(_ preset: SourcePreset) {
        presetService?.deletePreset(preset)
        loadPresets()
    }
}

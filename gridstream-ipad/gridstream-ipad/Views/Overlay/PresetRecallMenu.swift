//
//  PresetRecallMenu.swift
//  gridstream-ipad
//

import GridStreamAPI
import SwiftUI

struct PresetRecallMenu: View {
    let gridState: GridState
    let smartLists: [SmartListInfo]
    let simpleLists: [SimpleListDTO]
    var onApplied: (() -> Void)?
    var onMenuOpen: (() -> Void)?
    var onMenuClose: (() -> Void)?

    @Environment(SourcePresetService.self) private var presetService: SourcePresetService?
    @Environment(SharedPlayerPool.self) private var playerPool
    @Environment(VideoHistoryManager.self) private var historyManager
    @State private var presets: [SourcePreset] = []
    @State private var showMenu = false

    var body: some View {
        Button(action: {
            if !showMenu { loadPresets() }
            showMenu.toggle()
        }) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 18))
        }
        .popover(isPresented: $showMenu, arrowEdge: .top) {
            presetListView
                .presentationCompactAdaptation(.popover)
        }
        .onChange(of: showMenu) { _, isOpen in
            if isOpen {
                onMenuOpen?()
            } else {
                onMenuClose?()
            }
        }
        .accessibilityLabel("Recall preset")
    }

    private var presetListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Presets")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            if !presets.isEmpty {
                ForEach(presets) { preset in
                    Button {
                        applyPreset(preset)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: preset.lastUsedAt != nil ? "clock.arrow.circlepath" : "square.stack.3d.up")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Text("\(preset.tileCount) tiles")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Divider()
            }

            Button {
                resetAll()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                        .frame(width: 20)

                    Text("Reset All")
                        .font(.subheadline)
                        .foregroundStyle(.red)

                    Spacer()
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(minWidth: 200)
    }

    private func loadPresets() {
        presets = presetService?.fetchPresetsForRecall() ?? []
    }

    private func resetAll() {
        showMenu = false
        GridSidecarStateCoordinator.clearAllSources(
            gridState: gridState,
            playerPool: playerPool,
            historyManager: historyManager,
            resetSidecarState: true
        )
        onApplied?()
    }

    private func applyPreset(_ preset: SourcePreset) {
        showMenu = false
        let _ = SourcePresetApplicator.apply(
            preset,
            to: gridState,
            playerPool: playerPool,
            historyManager: historyManager,
            smartLists: smartLists,
            simpleLists: simpleLists
        )
        presetService?.markPresetAsUsed(preset)
        loadPresets()
        onApplied?()
    }
}

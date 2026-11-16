//
//  AudioSettingsTabView.swift
//  gridstream-ipad
//
//  Audio normalization settings UI for the Content Library Audio tab.
//  Provides preset selection and custom parameter adjustment.
//

import SwiftUI

struct AudioSettingsTabView: View {

    @State private var settingsManager = AudioNormalizationSettingsManager.shared

    var body: some View {
        Form {
            presetSection

            if settingsManager.preset == .custom {
                customParametersSection
                resetSection
            } else if settingsManager.preset != .off {
                readOnlyParametersSection
            }

            infoSection
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Preset Section

    private var presetSection: some View {
        Section {
            Picker("Normalization Preset", selection: $settingsManager.preset) {
                ForEach(AudioNormalizationPreset.allCases, id: \.self) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Audio normalization preset")
        } header: {
            Text("Audio Normalization")
        } footer: {
            Text(presetDescription)
        }
    }

    private var presetDescription: LocalizedStringResource {
        switch settingsManager.preset {
        case .off:
            return "Audio passes through unprocessed. No normalization is applied."
        case .gentle:
            return "Light compression for subtle volume leveling. Minimal effect on dynamics."
        case .moderate:
            return "Balanced compression to reduce volume spikes while preserving dynamics."
        case .aggressive:
            return "Heavy compression for maximum volume consistency across all videos."
        case .custom:
            return "Adjust compression parameters manually for fine-tuned control."
        }
    }

    // MARK: - Custom Parameters Section

    private var customParametersSection: some View {
        Section {
            // Threshold slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Threshold")
                    Spacer()
                    Text("\(Int(settingsManager.customThreshold)) dB")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { Double(settingsManager.customThreshold) },
                        set: { settingsManager.customThreshold = Float($0) }
                    ),
                    in: Double(AudioNormalizationParameters.thresholdRange.lowerBound)...Double(AudioNormalizationParameters.thresholdRange.upperBound),
                    step: 1
                )
                .accessibilityLabel("Threshold: \(Int(settingsManager.customThreshold)) dB")
            }

            // Ratio slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Ratio")
                    Spacer()
                    Text(formatRatio(settingsManager.customRatio))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { Double(settingsManager.customRatio) },
                        set: { settingsManager.customRatio = Float($0) }
                    ),
                    in: Double(AudioNormalizationParameters.ratioRange.lowerBound)...Double(AudioNormalizationParameters.ratioRange.upperBound),
                    step: 0.5
                )
                .accessibilityLabel("Ratio: \(formatRatio(settingsManager.customRatio))")
            }

            // Attack slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Attack")
                    Spacer()
                    Text("\(Int(settingsManager.customAttackTime)) ms")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { Double(settingsManager.customAttackTime) },
                        set: { settingsManager.customAttackTime = Float($0) }
                    ),
                    in: Double(AudioNormalizationParameters.attackTimeRange.lowerBound)...Double(AudioNormalizationParameters.attackTimeRange.upperBound),
                    step: 1
                )
                .accessibilityLabel("Attack: \(Int(settingsManager.customAttackTime)) milliseconds")
            }

            // Release slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Release")
                    Spacer()
                    Text("\(Int(settingsManager.customReleaseTime)) ms")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { Double(settingsManager.customReleaseTime) },
                        set: { settingsManager.customReleaseTime = Float($0) }
                    ),
                    in: Double(AudioNormalizationParameters.releaseTimeRange.lowerBound)...Double(AudioNormalizationParameters.releaseTimeRange.upperBound),
                    step: 10
                )
                .accessibilityLabel("Release: \(Int(settingsManager.customReleaseTime)) milliseconds")
            }

            // Makeup Gain slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Makeup Gain")
                    Spacer()
                    Text("\(Int(settingsManager.customMakeupGain)) dB")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { Double(settingsManager.customMakeupGain) },
                        set: { settingsManager.customMakeupGain = Float($0) }
                    ),
                    in: Double(AudioNormalizationParameters.makeupGainRange.lowerBound)...Double(AudioNormalizationParameters.makeupGainRange.upperBound),
                    step: 1
                )
                .accessibilityLabel("Makeup Gain: \(Int(settingsManager.customMakeupGain)) dB")
            }
        } header: {
            Text("Custom Parameters")
        } footer: {
            Text("Threshold: Level above which compression begins. Ratio: Amount of compression (e.g., 4:1 means 4dB over threshold becomes 1dB). Attack/Release: How quickly compression engages/releases. Makeup Gain: Volume boost after compression.")
        }
    }

    // MARK: - Read-Only Parameters Section (for preset display)

    private var readOnlyParametersSection: some View {
        Section {
            let params = settingsManager.preset.parameters

            // Threshold
            HStack {
                Text("Threshold")
                Spacer()
                Text("\(Int(params.thresholdDB)) dB")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // Ratio
            HStack {
                Text("Ratio")
                Spacer()
                Text(formatRatio(params.ratio))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // Attack
            HStack {
                Text("Attack")
                Spacer()
                Text("\(Int(params.attackTimeMS)) ms")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // Release
            HStack {
                Text("Release")
                Spacer()
                Text("\(Int(params.releaseTimeMS)) ms")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // Makeup Gain
            HStack {
                Text("Makeup Gain")
                Spacer()
                Text("\(Int(params.makeupGainDB)) dB")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } header: {
            Text("Preset Parameters")
        } footer: {
            Text("These are the parameters used by the \(String(localized: settingsManager.preset.displayName)) preset. Select \"Custom\" to modify these values.")
        }
    }

    // MARK: - Reset Section

    private var resetSection: some View {
        Section {
            Button("Reset to Default") {
                settingsManager.resetCustomToDefaults()
            }
            .foregroundStyle(.red)
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("Audio normalization helps prevent sudden volume spikes when multiple videos play simultaneously.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func formatRatio(_ ratio: Float) -> String {
        if ratio == Float(Int(ratio)) {
            return "\(Int(ratio)):1"
        } else {
            return String(format: "%.1f:1", ratio)
        }
    }
}

// MARK: - Previews

#Preview("Off Preset") {
    NavigationStack {
        AudioSettingsTabView()
            .navigationTitle("Audio Settings")
    }
    .onAppear {
        AudioNormalizationSettingsManager.shared.preset = .off
    }
}

#Preview("Moderate Preset") {
    NavigationStack {
        AudioSettingsTabView()
            .navigationTitle("Audio Settings")
    }
    .onAppear {
        AudioNormalizationSettingsManager.shared.preset = .moderate
    }
}

#Preview("Custom Preset") {
    NavigationStack {
        AudioSettingsTabView()
            .navigationTitle("Audio Settings")
    }
    .onAppear {
        AudioNormalizationSettingsManager.shared.preset = .custom
    }
}

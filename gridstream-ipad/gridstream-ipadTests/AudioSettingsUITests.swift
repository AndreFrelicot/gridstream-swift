//
//  AudioSettingsUITests.swift
//  gridstream-ipadTests
//
//  Tests for Audio settings UI in UnifiedContentLibraryView.
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class AudioSettingsUITests: XCTestCase {

    private var manager: AudioNormalizationSettingsManager!

    override func setUp() async throws {
        try await super.setUp()
        manager = AudioNormalizationSettingsManager.shared
        manager.resetToDefaults()
    }

    override func tearDown() async throws {
        manager.resetToDefaults()
        try await super.tearDown()
    }

    // MARK: - Test Audio Tab Exists in UnifiedContentTab

    func testAudioTabExistsInUnifiedContentTab() async {
        // Given the UnifiedContentTab enum
        let allTabs = UnifiedContentTab.allCases

        // Then it should contain the audio tab
        XCTAssertTrue(allTabs.contains(.audio), "Audio tab should exist in UnifiedContentTab")

        // And audio tab should have correct title and icon
        XCTAssertEqual(String(localized: UnifiedContentTab.audio.title), "Audio")
        XCTAssertEqual(UnifiedContentTab.audio.icon, "speaker.wave.3")
    }

    // MARK: - Test Preset Picker Displays All Options

    func testPresetPickerDisplaysAllOptions() async {
        // Given all audio normalization presets
        let allPresets = AudioNormalizationPreset.allCases

        // Then there should be 5 preset options
        XCTAssertEqual(allPresets.count, 5)

        // And each preset should have a display name
        XCTAssertEqual(String(localized: AudioNormalizationPreset.off.displayName), "Off")
        XCTAssertEqual(String(localized: AudioNormalizationPreset.gentle.displayName), "Gentle")
        XCTAssertEqual(String(localized: AudioNormalizationPreset.moderate.displayName), "Moderate")
        XCTAssertEqual(String(localized: AudioNormalizationPreset.aggressive.displayName), "Aggressive")
        XCTAssertEqual(String(localized: AudioNormalizationPreset.custom.displayName), "Custom")
    }

    // MARK: - Test Custom Parameters Visibility Based on Preset

    func testCustomParametersOnlyVisibleWhenCustomPresetSelected() async {
        // Given default preset (moderate)
        manager.preset = .moderate

        // Then custom parameters should not be the effective ones
        // (effective parameters come from preset, not custom values)
        let moderateParams = AudioNormalizationPreset.moderate.parameters
        XCTAssertEqual(manager.effectiveThreshold, moderateParams.thresholdDB, accuracy: 0.01)

        // When switching to custom preset
        manager.preset = .custom
        manager.customThreshold = -35.0

        // Then custom parameters should be effective
        XCTAssertEqual(manager.effectiveThreshold, -35.0, accuracy: 0.01)

        // When switching back to a preset
        manager.preset = .gentle

        // Then preset parameters should be effective again
        let gentleParams = AudioNormalizationPreset.gentle.parameters
        XCTAssertEqual(manager.effectiveThreshold, gentleParams.thresholdDB, accuracy: 0.01)
    }

    // MARK: - Test Reset to Default Button

    func testResetToDefaultResetsCustomParameters() async {
        // Given custom preset with modified parameters
        manager.preset = .custom
        manager.customThreshold = -45.0
        manager.customRatio = 15.0
        manager.customAttackTime = 50.0
        manager.customReleaseTime = 500.0
        manager.customMakeupGain = 12.0

        // Verify custom values are set
        XCTAssertEqual(manager.customThreshold, -45.0, accuracy: 0.01)
        XCTAssertEqual(manager.customRatio, 15.0, accuracy: 0.01)
        XCTAssertEqual(manager.customAttackTime, 50.0, accuracy: 0.01)
        XCTAssertEqual(manager.customReleaseTime, 500.0, accuracy: 0.01)
        XCTAssertEqual(manager.customMakeupGain, 12.0, accuracy: 0.01)

        // When resetting custom parameters to defaults
        manager.resetCustomToDefaults()

        // Then custom parameters should be at default values
        XCTAssertEqual(manager.customThreshold, AudioNormalizationParameters.defaultThreshold, accuracy: 0.01)
        XCTAssertEqual(manager.customRatio, AudioNormalizationParameters.defaultRatio, accuracy: 0.01)
        XCTAssertEqual(manager.customAttackTime, AudioNormalizationParameters.defaultAttackTime, accuracy: 0.01)
        XCTAssertEqual(manager.customReleaseTime, AudioNormalizationParameters.defaultReleaseTime, accuracy: 0.01)
        XCTAssertEqual(manager.customMakeupGain, AudioNormalizationParameters.defaultMakeupGain, accuracy: 0.01)
    }

    // MARK: - Test Settings Persistence

    func testSettingsPersistAcrossSettingsChanges() async {
        // Given a specific preset and custom parameters
        manager.preset = .aggressive

        // Force synchronize
        UserDefaults.standard.synchronize()

        // Verify the preset was stored
        let storedPreset = UserDefaults.standard.string(forKey: "audioNormalizationPreset")
        XCTAssertEqual(storedPreset, "aggressive")

        // When switching to custom and setting values
        manager.preset = .custom
        manager.customThreshold = -40.0
        manager.customRatio = 12.0

        UserDefaults.standard.synchronize()

        // Then values should be persisted
        let storedThreshold = UserDefaults.standard.float(forKey: "audioNormalizationThreshold")
        let storedRatio = UserDefaults.standard.float(forKey: "audioNormalizationRatio")

        XCTAssertEqual(storedThreshold, -40.0, accuracy: 0.01)
        XCTAssertEqual(storedRatio, 12.0, accuracy: 0.01)
    }

    // MARK: - Test Slider Ranges

    func testSliderRangesAreCorrect() async {
        // Verify parameter ranges match spec requirements
        XCTAssertEqual(AudioNormalizationParameters.thresholdRange, -60.0...0.0)
        XCTAssertEqual(AudioNormalizationParameters.ratioRange, 1.0...20.0)
        XCTAssertEqual(AudioNormalizationParameters.attackTimeRange, 1.0...100.0)
        XCTAssertEqual(AudioNormalizationParameters.releaseTimeRange, 50.0...1000.0)
        XCTAssertEqual(AudioNormalizationParameters.makeupGainRange, 0.0...24.0)
    }
}

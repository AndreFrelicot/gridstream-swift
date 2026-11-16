//
//  AudioNormalizationSettingsTests.swift
//  gridstream-ipadTests
//
//  Tests for audio normalization settings model and persistence.
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class AudioNormalizationSettingsTests: XCTestCase {

    private var manager: AudioNormalizationSettingsManager!
    private let testSuite = "com.gridstream.test.audioSettings"

    override func setUp() async throws {
        try await super.setUp()
        // Create a fresh manager for each test with test-specific UserDefaults
        // Clear any existing test data
        clearTestUserDefaults()
        manager = AudioNormalizationSettingsManager.shared
        // Reset to defaults for clean test state
        manager.resetToDefaults()
    }

    override func tearDown() async throws {
        clearTestUserDefaults()
        try await super.tearDown()
    }

    private func clearTestUserDefaults() {
        let keys = [
            "audioNormalizationPreset",
            "audioNormalizationThreshold",
            "audioNormalizationRatio",
            "audioNormalizationAttack",
            "audioNormalizationRelease",
            "audioNormalizationMakeupGain"
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.synchronize()
    }

    // MARK: - Preset Initialization Tests

    func testPresetEnumInitializationWithExpectedParameterValues() async {
        // Test that preset enum contains expected cases
        let allPresets = AudioNormalizationPreset.allCases
        XCTAssertEqual(allPresets.count, 5)
        XCTAssertTrue(allPresets.contains(.off))
        XCTAssertTrue(allPresets.contains(.gentle))
        XCTAssertTrue(allPresets.contains(.moderate))
        XCTAssertTrue(allPresets.contains(.aggressive))
        XCTAssertTrue(allPresets.contains(.custom))

        // Test Gentle preset parameters
        let gentleParams = AudioNormalizationPreset.gentle.parameters
        XCTAssertEqual(gentleParams.thresholdDB, -12.0, accuracy: 0.01)
        XCTAssertEqual(gentleParams.ratio, 2.0, accuracy: 0.01)
        XCTAssertEqual(gentleParams.attackTimeMS, 20.0, accuracy: 0.01)
        XCTAssertEqual(gentleParams.releaseTimeMS, 200.0, accuracy: 0.01)
        XCTAssertEqual(gentleParams.makeupGainDB, 0.0, accuracy: 0.01)

        // Test Moderate preset parameters
        let moderateParams = AudioNormalizationPreset.moderate.parameters
        XCTAssertEqual(moderateParams.thresholdDB, -20.0, accuracy: 0.01)
        XCTAssertEqual(moderateParams.ratio, 4.0, accuracy: 0.01)
        XCTAssertEqual(moderateParams.attackTimeMS, 10.0, accuracy: 0.01)
        XCTAssertEqual(moderateParams.releaseTimeMS, 100.0, accuracy: 0.01)
        XCTAssertEqual(moderateParams.makeupGainDB, 3.0, accuracy: 0.01)

        // Test Aggressive preset parameters
        let aggressiveParams = AudioNormalizationPreset.aggressive.parameters
        XCTAssertEqual(aggressiveParams.thresholdDB, -18.0, accuracy: 0.01)
        XCTAssertEqual(aggressiveParams.ratio, 6.0, accuracy: 0.01)
        XCTAssertEqual(aggressiveParams.attackTimeMS, 5.0, accuracy: 0.01)
        XCTAssertEqual(aggressiveParams.releaseTimeMS, 150.0, accuracy: 0.01)
        XCTAssertEqual(aggressiveParams.makeupGainDB, 4.0, accuracy: 0.01)

        // Test Off preset bypasses
        XCTAssertTrue(AudioNormalizationPreset.off.isBypassed)
        XCTAssertFalse(AudioNormalizationPreset.gentle.isBypassed)
        XCTAssertFalse(AudioNormalizationPreset.moderate.isBypassed)
        XCTAssertFalse(AudioNormalizationPreset.aggressive.isBypassed)
    }

    // MARK: - Custom Mode Tests

    func testCustomModeStoresIndividualParametersCorrectly() async {
        // Set preset to custom
        manager.preset = .custom

        // Set custom parameters
        manager.customThreshold = -25.0
        manager.customRatio = 6.0
        manager.customAttackTime = 15.0
        manager.customReleaseTime = 150.0
        manager.customMakeupGain = 4.0

        // Verify parameters are stored
        XCTAssertEqual(manager.customThreshold, -25.0, accuracy: 0.01)
        XCTAssertEqual(manager.customRatio, 6.0, accuracy: 0.01)
        XCTAssertEqual(manager.customAttackTime, 15.0, accuracy: 0.01)
        XCTAssertEqual(manager.customReleaseTime, 150.0, accuracy: 0.01)
        XCTAssertEqual(manager.customMakeupGain, 4.0, accuracy: 0.01)

        // Verify effective parameters reflect custom values
        XCTAssertEqual(manager.effectiveThreshold, -25.0, accuracy: 0.01)
        XCTAssertEqual(manager.effectiveRatio, 6.0, accuracy: 0.01)
        XCTAssertEqual(manager.effectiveAttackTime, 15.0, accuracy: 0.01)
        XCTAssertEqual(manager.effectiveReleaseTime, 150.0, accuracy: 0.01)
        XCTAssertEqual(manager.effectiveMakeupGain, 4.0, accuracy: 0.01)
    }

    // MARK: - UserDefaults Persistence Tests

    func testUserDefaultsPersistenceSavesAndRestoresCorrectly() async {
        // Set a preset
        manager.preset = .aggressive

        // Force synchronize
        UserDefaults.standard.synchronize()

        // Verify the value was stored
        let storedPresetRaw = UserDefaults.standard.string(forKey: "audioNormalizationPreset")
        XCTAssertEqual(storedPresetRaw, "aggressive")

        // Set custom parameters
        manager.preset = .custom
        manager.customThreshold = -35.0
        manager.customRatio = 10.0

        UserDefaults.standard.synchronize()

        // Verify custom values are stored
        let storedThreshold = UserDefaults.standard.float(forKey: "audioNormalizationThreshold")
        let storedRatio = UserDefaults.standard.float(forKey: "audioNormalizationRatio")
        XCTAssertEqual(storedThreshold, -35.0, accuracy: 0.01)
        XCTAssertEqual(storedRatio, 10.0, accuracy: 0.01)
    }

    // MARK: - Default Values Tests

    func testDefaultValuesAreAppliedCorrectlyOnFirstLaunch() async {
        // Clear all settings to simulate first launch
        clearTestUserDefaults()

        // Create a new manager instance
        // Note: Since it's a singleton, we verify through the manager's initial state
        manager.resetToDefaults()

        // Verify default preset is moderate
        XCTAssertEqual(manager.preset, .moderate)

        // Verify default custom parameters
        XCTAssertEqual(manager.customThreshold, -20.0, accuracy: 0.01)
        XCTAssertEqual(manager.customRatio, 4.0, accuracy: 0.01)
        XCTAssertEqual(manager.customAttackTime, 10.0, accuracy: 0.01)
        XCTAssertEqual(manager.customReleaseTime, 100.0, accuracy: 0.01)
        XCTAssertEqual(manager.customMakeupGain, 0.0, accuracy: 0.01)
    }

    // MARK: - Effective Parameters Tests

    func testEffectiveParametersReflectPresetWhenNotCustom() async {
        // Set to gentle preset
        manager.preset = .gentle

        // Effective parameters should match gentle preset
        XCTAssertEqual(manager.effectiveThreshold, -12.0, accuracy: 0.01)
        XCTAssertEqual(manager.effectiveRatio, 2.0, accuracy: 0.01)
        XCTAssertEqual(manager.effectiveAttackTime, 20.0, accuracy: 0.01)
        XCTAssertEqual(manager.effectiveReleaseTime, 200.0, accuracy: 0.01)
        XCTAssertEqual(manager.effectiveMakeupGain, 0.0, accuracy: 0.01)
        XCTAssertFalse(manager.isBypassed)

        // Switch to off - should be bypassed
        manager.preset = .off
        XCTAssertTrue(manager.isBypassed)
    }

    // MARK: - Parameter Clamping Tests

    func testParameterClampingEnforcesValidRanges() async {
        manager.preset = .custom

        // Test threshold clamping (-60 to 0)
        manager.customThreshold = -100.0
        XCTAssertGreaterThanOrEqual(manager.effectiveThreshold, -60.0)

        manager.customThreshold = 10.0
        XCTAssertLessThanOrEqual(manager.effectiveThreshold, 0.0)

        // Test ratio clamping (1.0 to 20.0)
        manager.customRatio = 0.5
        XCTAssertGreaterThanOrEqual(manager.effectiveRatio, 1.0)

        manager.customRatio = 50.0
        XCTAssertLessThanOrEqual(manager.effectiveRatio, 20.0)

        // Test attack time clamping (1 to 100 ms)
        manager.customAttackTime = 0.1
        XCTAssertGreaterThanOrEqual(manager.effectiveAttackTime, 1.0)

        manager.customAttackTime = 500.0
        XCTAssertLessThanOrEqual(manager.effectiveAttackTime, 100.0)

        // Test release time clamping (50 to 1000 ms)
        manager.customReleaseTime = 10.0
        XCTAssertGreaterThanOrEqual(manager.effectiveReleaseTime, 50.0)

        manager.customReleaseTime = 2000.0
        XCTAssertLessThanOrEqual(manager.effectiveReleaseTime, 1000.0)

        // Test makeup gain clamping (0 to 24 dB)
        manager.customMakeupGain = -5.0
        XCTAssertGreaterThanOrEqual(manager.effectiveMakeupGain, 0.0)

        manager.customMakeupGain = 30.0
        XCTAssertLessThanOrEqual(manager.effectiveMakeupGain, 24.0)
    }
}

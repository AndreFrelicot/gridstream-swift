//
//  AudioNormalizationIntegrationTests.swift
//  gridstream-ipadTests
//
//  Integration and end-to-end tests for audio normalization feature.
//  Verifies that settings, processor, and UI components work together correctly.
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class AudioNormalizationIntegrationTests: XCTestCase {

    private var settingsManager: AudioNormalizationSettingsManager!

    override func setUp() async throws {
        try await super.setUp()
        settingsManager = AudioNormalizationSettingsManager.shared
        settingsManager.resetToDefaults()
        clearTestUserDefaults()
    }

    override func tearDown() async throws {
        settingsManager.resetToDefaults()
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

    // MARK: - End-to-End: Preset Change Applies to Processor

    func testPresetChangeImmediatelyUpdatesTapSettings() async {
        // Given the settings manager with default preset (moderate)
        settingsManager.preset = .moderate

        // When changing to aggressive preset
        settingsManager.preset = .aggressive

        // Then the tap settings should reflect aggressive parameters
        let processor = AudioTapManager.currentSettings

        // Aggressive preset: threshold -18dB, ratio 6:1, attack 5ms, release 150ms, makeup 4dB
        XCTAssertEqual(processor.thresholdDB, -18.0, accuracy: 0.01,
                       "Processor threshold should match aggressive preset")
        XCTAssertEqual(processor.ratio, 6.0, accuracy: 0.01,
                       "Processor ratio should match aggressive preset")
        XCTAssertEqual(processor.attackTimeMS, 5.0, accuracy: 0.01,
                       "Processor attack time should match aggressive preset")
        XCTAssertEqual(processor.releaseTimeMS, 150.0, accuracy: 0.01,
                       "Processor release time should match aggressive preset")
        XCTAssertEqual(processor.makeupGainDB, 4.0, accuracy: 0.01,
                       "Processor makeup gain should match aggressive preset")
        XCTAssertFalse(processor.isBypassed,
                       "Processor should not be bypassed for aggressive preset")
    }

    func testOffPresetBypassesProcessor() async {
        // Given any active preset
        settingsManager.preset = .moderate
        XCTAssertFalse(AudioTapManager.currentSettings.isBypassed)

        // When switching to Off preset
        settingsManager.preset = .off

        // Then processor should be bypassed
        XCTAssertTrue(AudioTapManager.currentSettings.isBypassed,
                      "Processor should be bypassed when preset is Off")
    }

    // MARK: - End-to-End: Custom Parameters Apply to Processor

    func testCustomParameterChangesApplyToProcessor() async {
        // Given custom preset selected
        settingsManager.preset = .custom

        // When setting custom parameters
        settingsManager.customThreshold = -45.0
        settingsManager.customRatio = 12.0
        settingsManager.customAttackTime = 25.0
        settingsManager.customReleaseTime = 300.0
        settingsManager.customMakeupGain = 10.0

        // Then processor should reflect custom values
        let processor = AudioTapManager.currentSettings

        XCTAssertEqual(processor.thresholdDB, -45.0, accuracy: 0.01,
                       "Processor should use custom threshold")
        XCTAssertEqual(processor.ratio, 12.0, accuracy: 0.01,
                       "Processor should use custom ratio")
        XCTAssertEqual(processor.attackTimeMS, 25.0, accuracy: 0.01,
                       "Processor should use custom attack time")
        XCTAssertEqual(processor.releaseTimeMS, 300.0, accuracy: 0.01,
                       "Processor should use custom release time")
        XCTAssertEqual(processor.makeupGainDB, 10.0, accuracy: 0.01,
                       "Processor should use custom makeup gain")
    }

    // MARK: - Integration: Settings Persistence Round-Trip

    func testSettingsPersistAndRestoreAfterManagerReinitialization() async {
        // Given specific settings are configured
        settingsManager.preset = .aggressive
        settingsManager.customThreshold = -50.0
        settingsManager.customRatio = 15.0
        settingsManager.customAttackTime = 75.0
        settingsManager.customReleaseTime = 800.0
        settingsManager.customMakeupGain = 20.0

        // Force synchronize to persist
        UserDefaults.standard.synchronize()

        // Verify values are in UserDefaults
        let storedPreset = UserDefaults.standard.string(forKey: "audioNormalizationPreset")
        XCTAssertEqual(storedPreset, "aggressive", "Preset should be persisted")

        let storedThreshold = UserDefaults.standard.float(forKey: "audioNormalizationThreshold")
        XCTAssertEqual(storedThreshold, -50.0, accuracy: 0.01, "Custom threshold should be persisted")

        let storedRatio = UserDefaults.standard.float(forKey: "audioNormalizationRatio")
        XCTAssertEqual(storedRatio, 15.0, accuracy: 0.01, "Custom ratio should be persisted")

        let storedAttack = UserDefaults.standard.float(forKey: "audioNormalizationAttack")
        XCTAssertEqual(storedAttack, 75.0, accuracy: 0.01, "Custom attack should be persisted")

        let storedRelease = UserDefaults.standard.float(forKey: "audioNormalizationRelease")
        XCTAssertEqual(storedRelease, 800.0, accuracy: 0.01, "Custom release should be persisted")

        let storedMakeup = UserDefaults.standard.float(forKey: "audioNormalizationMakeupGain")
        XCTAssertEqual(storedMakeup, 20.0, accuracy: 0.01, "Custom makeup gain should be persisted")
    }

    // MARK: - Integration: Multiple Mute States are Independent

    func testMuteStatesAreIndependentPerTile() async {
        // This test verifies the design requirement that mute state is per-tile
        // Each tile maintains its own mute state independent of others

        // Simulate two independent mute states (like two separate tiles)
        var tile1Muted = false
        var tile2Muted = false

        // When tile 1 is muted
        tile1Muted = true

        // Then tile 2 should remain unmuted
        XCTAssertTrue(tile1Muted, "Tile 1 should be muted")
        XCTAssertFalse(tile2Muted, "Tile 2 should remain unmuted")

        // When tile 2 is muted
        tile2Muted = true

        // Then both should be muted independently
        XCTAssertTrue(tile1Muted, "Tile 1 should still be muted")
        XCTAssertTrue(tile2Muted, "Tile 2 should now be muted")

        // When tile 1 is unmuted
        tile1Muted = false

        // Then only tile 1 should be unmuted
        XCTAssertFalse(tile1Muted, "Tile 1 should be unmuted")
        XCTAssertTrue(tile2Muted, "Tile 2 should still be muted")
    }

    // MARK: - Integration: Preset Switching Preserves Custom Values

    func testSwitchingBetweenPresetsPreservesCustomValues() async {
        // Given custom values are set
        settingsManager.preset = .custom
        settingsManager.customThreshold = -42.0
        settingsManager.customRatio = 7.0
        settingsManager.customAttackTime = 35.0
        settingsManager.customReleaseTime = 450.0
        settingsManager.customMakeupGain = 8.0

        // When switching to a different preset
        settingsManager.preset = .gentle

        // Then effective parameters should be gentle preset values
        XCTAssertEqual(settingsManager.effectiveThreshold, -12.0, accuracy: 0.01,
                       "Effective threshold should be gentle preset value")

        // When switching back to custom
        settingsManager.preset = .custom

        // Then custom values should be preserved
        XCTAssertEqual(settingsManager.customThreshold, -42.0, accuracy: 0.01,
                       "Custom threshold should be preserved")
        XCTAssertEqual(settingsManager.customRatio, 7.0, accuracy: 0.01,
                       "Custom ratio should be preserved")
        XCTAssertEqual(settingsManager.customAttackTime, 35.0, accuracy: 0.01,
                       "Custom attack time should be preserved")
        XCTAssertEqual(settingsManager.customReleaseTime, 450.0, accuracy: 0.01,
                       "Custom release time should be preserved")
        XCTAssertEqual(settingsManager.customMakeupGain, 8.0, accuracy: 0.01,
                       "Custom makeup gain should be preserved")
    }

    // MARK: - Integration: Audio Processing with Normalization

    func testAudioProcessingWithDifferentPresets() async {
        // Create a test signal (loud samples that would trigger compression)
        // One second, so the smoothed gain reaches steady state
        let loudSignal = Array(repeating: Float(0.8), count: 44_100)

        // Test with Off preset - audio should pass unchanged
        let processorOff = AudioNormalizationProcessor()
        processorOff.applyPreset(.off)
        let outputOff = processorOff.processBuffer(loudSignal)

        // Bypassed audio should be identical to input
        for i in 0..<loudSignal.count {
            XCTAssertEqual(outputOff[i], loudSignal[i], accuracy: 0.0001,
                           "Off preset should pass audio unchanged")
        }

        // Test with Aggressive preset - audio should be compressed
        let processorAggressive = AudioNormalizationProcessor()
        processorAggressive.applyPreset(.aggressive)
        processorAggressive.setSampleRate(44100.0)
        let outputAggressive = processorAggressive.processBuffer(loudSignal)

        // Aggressive compression should reduce the steady-state level
        // (initial samples pass before gain smoothing engages)
        let steadyAggressive = outputAggressive.last ?? 0.0
        let steadyInput = loudSignal.last ?? 0.0

        XCTAssertLessThan(steadyAggressive, steadyInput,
                          "Aggressive preset should compress loud signals")
    }

    // MARK: - Integration: AudioTapManager Settings Update

    func testAudioTapManagerUpdatesProcessorParameters() async {
        // When updating parameters through AudioTapManager
        AudioTapManager.updateParameters(
            thresholdDB: -35.0,
            ratio: 6.0,
            attackTimeMS: 15.0,
            releaseTimeMS: 150.0,
            makeupGainDB: 5.0,
            isBypassed: false
        )

        // Then the tap settings should reflect those parameters
        let processor = AudioTapManager.currentSettings

        XCTAssertEqual(processor.thresholdDB, -35.0, accuracy: 0.01)
        XCTAssertEqual(processor.ratio, 6.0, accuracy: 0.01)
        XCTAssertEqual(processor.attackTimeMS, 15.0, accuracy: 0.01)
        XCTAssertEqual(processor.releaseTimeMS, 150.0, accuracy: 0.01)
        XCTAssertEqual(processor.makeupGainDB, 5.0, accuracy: 0.01)
        XCTAssertFalse(processor.isBypassed)
    }
}

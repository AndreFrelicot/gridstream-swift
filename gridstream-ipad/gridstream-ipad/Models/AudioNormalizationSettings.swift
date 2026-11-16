//
//  AudioNormalizationSettings.swift
//  gridstream-ipad
//
//  Audio normalization settings model and persistence.
//  Uses @AppStorage for reactive UserDefaults persistence.
//

import Foundation
import SwiftUI
import OSLog

// MARK: - Preset Enum

/// Audio normalization preset options
enum AudioNormalizationPreset: String, CaseIterable, Codable {
    case off
    case gentle
    case moderate
    case aggressive
    case custom

    /// Display name for UI
    var displayName: LocalizedStringResource {
        switch self {
        case .off: return "Off"
        case .gentle: return "Gentle"
        case .moderate: return "Moderate"
        case .aggressive: return "Aggressive"
        case .custom: return "Custom"
        }
    }

    /// Whether this preset bypasses audio processing
    var isBypassed: Bool {
        self == .off
    }

    /// Preset parameter values
    var parameters: AudioNormalizationParameters {
        switch self {
        case .off:
            // Off bypasses processing, parameters don't matter but provide defaults
            return AudioNormalizationParameters(
                thresholdDB: -20.0,
                ratio: 4.0,
                attackTimeMS: 10.0,
                releaseTimeMS: 100.0,
                makeupGainDB: 0.0
            )
        case .gentle:
            return AudioNormalizationParameters(
                thresholdDB: -12.0,
                ratio: 2.0,
                attackTimeMS: 20.0,
                releaseTimeMS: 200.0,
                makeupGainDB: 0.0
            )
        case .moderate:
            return AudioNormalizationParameters(
                thresholdDB: -20.0,
                ratio: 4.0,
                attackTimeMS: 10.0,
                releaseTimeMS: 100.0,
                makeupGainDB: 3.0
            )
        case .aggressive:
            // Adjusted from -30dB/-50ms which caused constant compression modulation ("hatching")
            // -18dB threshold prevents compression on very quiet content
            // 150ms release prevents rapid gain pumping
            return AudioNormalizationParameters(
                thresholdDB: -18.0,
                ratio: 6.0,
                attackTimeMS: 5.0,
                releaseTimeMS: 150.0,
                makeupGainDB: 4.0
            )
        case .custom:
            // Custom returns moderate as default values
            return AudioNormalizationParameters(
                thresholdDB: -20.0,
                ratio: 4.0,
                attackTimeMS: 10.0,
                releaseTimeMS: 100.0,
                makeupGainDB: 0.0
            )
        }
    }
}

// MARK: - Parameters Structure

/// Audio normalization parameter values
struct AudioNormalizationParameters {
    let thresholdDB: Float
    let ratio: Float
    let attackTimeMS: Float
    let releaseTimeMS: Float
    let makeupGainDB: Float

    /// Parameter ranges for validation
    static let thresholdRange: ClosedRange<Float> = -60.0...0.0
    static let ratioRange: ClosedRange<Float> = 1.0...20.0
    static let attackTimeRange: ClosedRange<Float> = 1.0...100.0
    static let releaseTimeRange: ClosedRange<Float> = 50.0...1000.0
    static let makeupGainRange: ClosedRange<Float> = 0.0...24.0

    /// Default values
    static let defaultThreshold: Float = -20.0
    static let defaultRatio: Float = 4.0
    static let defaultAttackTime: Float = 10.0
    static let defaultReleaseTime: Float = 100.0
    static let defaultMakeupGain: Float = 0.0

    /// Clamps a threshold value to valid range
    static func clampThreshold(_ value: Float) -> Float {
        max(thresholdRange.lowerBound, min(thresholdRange.upperBound, value))
    }

    /// Clamps a ratio value to valid range
    static func clampRatio(_ value: Float) -> Float {
        max(ratioRange.lowerBound, min(ratioRange.upperBound, value))
    }

    /// Clamps an attack time value to valid range
    static func clampAttackTime(_ value: Float) -> Float {
        max(attackTimeRange.lowerBound, min(attackTimeRange.upperBound, value))
    }

    /// Clamps a release time value to valid range
    static func clampReleaseTime(_ value: Float) -> Float {
        max(releaseTimeRange.lowerBound, min(releaseTimeRange.upperBound, value))
    }

    /// Clamps a makeup gain value to valid range
    static func clampMakeupGain(_ value: Float) -> Float {
        max(makeupGainRange.lowerBound, min(makeupGainRange.upperBound, value))
    }
}

// MARK: - Settings Manager

/// Observable singleton manager for audio normalization settings.
/// Uses @AppStorage for reactive UserDefaults persistence.
@Observable
final class AudioNormalizationSettingsManager {

    // MARK: - Singleton

    /// Shared instance
    static let shared = AudioNormalizationSettingsManager()

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let preset = "audioNormalizationPreset"
        static let threshold = "audioNormalizationThreshold"
        static let ratio = "audioNormalizationRatio"
        static let attack = "audioNormalizationAttack"
        static let release = "audioNormalizationRelease"
        static let makeupGain = "audioNormalizationMakeupGain"
    }

    // MARK: - Stored Properties

    /// Current preset selection
    var preset: AudioNormalizationPreset {
        didSet {
            UserDefaults.standard.set(preset.rawValue, forKey: Keys.preset)
            applySettingsToProcessor()
            AppLogger.video.info("Audio normalization preset changed to: \(self.preset.rawValue)")
        }
    }

    /// Custom threshold in dB (-60 to 0)
    var customThreshold: Float {
        didSet {
            let clamped = AudioNormalizationParameters.clampThreshold(customThreshold)
            if clamped != customThreshold {
                customThreshold = clamped
            }
            UserDefaults.standard.set(customThreshold, forKey: Keys.threshold)
            if preset == .custom {
                applySettingsToProcessor()
            }
        }
    }

    /// Custom compression ratio (1.0 to 20.0)
    var customRatio: Float {
        didSet {
            let clamped = AudioNormalizationParameters.clampRatio(customRatio)
            if clamped != customRatio {
                customRatio = clamped
            }
            UserDefaults.standard.set(customRatio, forKey: Keys.ratio)
            if preset == .custom {
                applySettingsToProcessor()
            }
        }
    }

    /// Custom attack time in ms (1 to 100)
    var customAttackTime: Float {
        didSet {
            let clamped = AudioNormalizationParameters.clampAttackTime(customAttackTime)
            if clamped != customAttackTime {
                customAttackTime = clamped
            }
            UserDefaults.standard.set(customAttackTime, forKey: Keys.attack)
            if preset == .custom {
                applySettingsToProcessor()
            }
        }
    }

    /// Custom release time in ms (50 to 1000)
    var customReleaseTime: Float {
        didSet {
            let clamped = AudioNormalizationParameters.clampReleaseTime(customReleaseTime)
            if clamped != customReleaseTime {
                customReleaseTime = clamped
            }
            UserDefaults.standard.set(customReleaseTime, forKey: Keys.release)
            if preset == .custom {
                applySettingsToProcessor()
            }
        }
    }

    /// Custom makeup gain in dB (0 to 24)
    var customMakeupGain: Float {
        didSet {
            let clamped = AudioNormalizationParameters.clampMakeupGain(customMakeupGain)
            if clamped != customMakeupGain {
                customMakeupGain = clamped
            }
            UserDefaults.standard.set(customMakeupGain, forKey: Keys.makeupGain)
            if preset == .custom {
                applySettingsToProcessor()
            }
        }
    }

    // MARK: - Computed Properties

    /// Effective threshold based on current preset or custom value
    var effectiveThreshold: Float {
        if preset == .custom {
            return AudioNormalizationParameters.clampThreshold(customThreshold)
        }
        return preset.parameters.thresholdDB
    }

    /// Effective ratio based on current preset or custom value
    var effectiveRatio: Float {
        if preset == .custom {
            return AudioNormalizationParameters.clampRatio(customRatio)
        }
        return preset.parameters.ratio
    }

    /// Effective attack time based on current preset or custom value
    var effectiveAttackTime: Float {
        if preset == .custom {
            return AudioNormalizationParameters.clampAttackTime(customAttackTime)
        }
        return preset.parameters.attackTimeMS
    }

    /// Effective release time based on current preset or custom value
    var effectiveReleaseTime: Float {
        if preset == .custom {
            return AudioNormalizationParameters.clampReleaseTime(customReleaseTime)
        }
        return preset.parameters.releaseTimeMS
    }

    /// Effective makeup gain based on current preset or custom value
    var effectiveMakeupGain: Float {
        if preset == .custom {
            return AudioNormalizationParameters.clampMakeupGain(customMakeupGain)
        }
        return preset.parameters.makeupGainDB
    }

    /// Whether audio processing is bypassed
    var isBypassed: Bool {
        preset.isBypassed
    }

    // MARK: - Initialization

    private init() {
        // Load preset from UserDefaults or use default
        if let presetString = UserDefaults.standard.string(forKey: Keys.preset),
           let loadedPreset = AudioNormalizationPreset(rawValue: presetString) {
            preset = loadedPreset
        } else {
            preset = .moderate
        }

        // Load custom parameters from UserDefaults or use defaults
        let storedThreshold = UserDefaults.standard.object(forKey: Keys.threshold) as? Float
        customThreshold = storedThreshold ?? AudioNormalizationParameters.defaultThreshold

        let storedRatio = UserDefaults.standard.object(forKey: Keys.ratio) as? Float
        customRatio = storedRatio ?? AudioNormalizationParameters.defaultRatio

        let storedAttack = UserDefaults.standard.object(forKey: Keys.attack) as? Float
        customAttackTime = storedAttack ?? AudioNormalizationParameters.defaultAttackTime

        let storedRelease = UserDefaults.standard.object(forKey: Keys.release) as? Float
        customReleaseTime = storedRelease ?? AudioNormalizationParameters.defaultReleaseTime

        let storedMakeup = UserDefaults.standard.object(forKey: Keys.makeupGain) as? Float
        customMakeupGain = storedMakeup ?? AudioNormalizationParameters.defaultMakeupGain

        // Apply initial settings to processor
        applySettingsToProcessor()

        AppLogger.video.info("Audio normalization settings loaded: preset=\(self.preset.rawValue)")
    }

    // MARK: - Public Methods

    /// Resets all settings to their default values
    func resetToDefaults() {
        preset = .moderate
        customThreshold = AudioNormalizationParameters.defaultThreshold
        customRatio = AudioNormalizationParameters.defaultRatio
        customAttackTime = AudioNormalizationParameters.defaultAttackTime
        customReleaseTime = AudioNormalizationParameters.defaultReleaseTime
        customMakeupGain = AudioNormalizationParameters.defaultMakeupGain

        AppLogger.video.info("Audio normalization settings reset to defaults")
    }

    /// Resets custom parameters to default values (for Reset to Default button)
    func resetCustomToDefaults() {
        customThreshold = AudioNormalizationParameters.defaultThreshold
        customRatio = AudioNormalizationParameters.defaultRatio
        customAttackTime = AudioNormalizationParameters.defaultAttackTime
        customReleaseTime = AudioNormalizationParameters.defaultReleaseTime
        customMakeupGain = AudioNormalizationParameters.defaultMakeupGain

        AppLogger.video.info("Audio normalization custom parameters reset to defaults")
    }

    // MARK: - Processor Integration

    /// Applies current settings to the AudioTapManager's shared processor
    private func applySettingsToProcessor() {
        AudioTapManager.updateParameters(
            thresholdDB: effectiveThreshold,
            ratio: effectiveRatio,
            attackTimeMS: effectiveAttackTime,
            releaseTimeMS: effectiveReleaseTime,
            makeupGainDB: effectiveMakeupGain,
            isBypassed: isBypassed
        )
    }
}

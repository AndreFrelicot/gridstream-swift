//
//  AudioNormalizationProcessorTests.swift
//  gridstream-ipadTests
//
//  Tests for the audio normalization DSP processor.
//

import AVFoundation
import XCTest
@testable import gridstream_ipad

@MainActor
final class AudioNormalizationProcessorTests: XCTestCase {

    // MARK: - Preset Initialization Tests

    func testPresetInitializationAppliesCorrectParameters() async {
        // Test that each preset applies the expected parameter values
        let processor = AudioNormalizationProcessor()

        // Test Gentle preset
        processor.applyPreset(.gentle)
        XCTAssertEqual(processor.thresholdDB, -12.0, accuracy: 0.01)
        XCTAssertEqual(processor.ratio, 2.0, accuracy: 0.01)
        XCTAssertEqual(processor.attackTimeMS, 20.0, accuracy: 0.01)
        XCTAssertEqual(processor.releaseTimeMS, 200.0, accuracy: 0.01)
        XCTAssertEqual(processor.makeupGainDB, 0.0, accuracy: 0.01)
        XCTAssertFalse(processor.isBypassed)

        // Test Moderate preset
        processor.applyPreset(.moderate)
        XCTAssertEqual(processor.thresholdDB, -20.0, accuracy: 0.01)
        XCTAssertEqual(processor.ratio, 4.0, accuracy: 0.01)
        XCTAssertEqual(processor.attackTimeMS, 10.0, accuracy: 0.01)
        XCTAssertEqual(processor.releaseTimeMS, 100.0, accuracy: 0.01)
        XCTAssertEqual(processor.makeupGainDB, 3.0, accuracy: 0.01)
        XCTAssertFalse(processor.isBypassed)

        // Test Aggressive preset
        processor.applyPreset(.aggressive)
        XCTAssertEqual(processor.thresholdDB, -18.0, accuracy: 0.01)
        XCTAssertEqual(processor.ratio, 6.0, accuracy: 0.01)
        XCTAssertEqual(processor.attackTimeMS, 5.0, accuracy: 0.01)
        XCTAssertEqual(processor.releaseTimeMS, 150.0, accuracy: 0.01)
        XCTAssertEqual(processor.makeupGainDB, 4.0, accuracy: 0.01)
        XCTAssertFalse(processor.isBypassed)
    }

    // MARK: - Bypass Mode Tests

    func testBypassModeProducesUnmodifiedAudio() async {
        let processor = AudioNormalizationProcessor(isBypassed: true)

        // Create test input with various values
        let input: [Float] = [0.0, 0.5, -0.5, 1.0, -1.0, 0.25, -0.75]

        let output = processor.processBuffer(input)

        // Output should be identical to input when bypassed
        XCTAssertEqual(output.count, input.count)
        for i in 0..<input.count {
            XCTAssertEqual(output[i], input[i], accuracy: 0.0001,
                           "Sample \(i) should be unmodified when bypassed")
        }
    }

    func testOffPresetEnablesBypassMode() async {
        let processor = AudioNormalizationProcessor()
        processor.applyPreset(.off)

        XCTAssertTrue(processor.isBypassed)

        // Verify audio passes through unmodified
        let input: [Float] = [0.8, -0.6, 0.9, -0.7]
        let output = processor.processBuffer(input)

        for i in 0..<input.count {
            XCTAssertEqual(output[i], input[i], accuracy: 0.0001)
        }
    }

    // MARK: - Compression Ratio Tests

    func testCompressionRatioReducesLoudSignals() async {
        // Set up processor with low threshold to trigger compression
        let processor = AudioNormalizationProcessor(
            thresholdDB: -20.0,  // About 0.1 linear
            ratio: 4.0,
            attackTimeMS: 1.0,   // Fast attack for immediate effect
            releaseTimeMS: 50.0,
            makeupGainDB: 0.0,
            isBypassed: false
        )
        processor.setSampleRate(44100.0)

        // Create a loud signal well above threshold
        // Peak at 0.8 (~-2dB) is well above threshold of -20dB
        // One second, so the smoothed gain (>= 50ms) reaches steady state
        let loudSignal = Array(repeating: Float(0.8), count: 44_100)

        let output = processor.processBuffer(loudSignal)

        // The first samples pass before gain smoothing engages (no lookahead),
        // so compare the steady-state level rather than the peak.
        let steadyOutput = output.last ?? 0.0
        let input = loudSignal.last ?? 0.0

        XCTAssertLessThan(steadyOutput, input,
                          "Loud signals should be compressed to lower levels")
    }

    // MARK: - Makeup Gain Tests

    func testMakeupGainIncreasesOutputLevel() async {
        // Create processor with significant makeup gain
        let processorNoGain = AudioNormalizationProcessor(
            thresholdDB: 0.0,    // High threshold so no compression occurs
            ratio: 1.0,
            attackTimeMS: 10.0,
            releaseTimeMS: 100.0,
            makeupGainDB: 0.0,
            isBypassed: false
        )

        let processorWithGain = AudioNormalizationProcessor(
            thresholdDB: 0.0,
            ratio: 1.0,
            attackTimeMS: 10.0,
            releaseTimeMS: 100.0,
            makeupGainDB: 6.0,   // +6dB gain (approx 2x)
            isBypassed: false
        )

        let input: [Float] = [0.3, 0.3, 0.3, 0.3, 0.3]

        let outputNoGain = processorNoGain.processBuffer(input)
        let outputWithGain = processorWithGain.processBuffer(input)

        // With 6dB makeup gain, output should be approximately 2x the no-gain output
        let avgNoGain = outputNoGain.reduce(0, +) / Float(outputNoGain.count)
        let avgWithGain = outputWithGain.reduce(0, +) / Float(outputWithGain.count)

        // 6dB = 10^(6/20) = ~1.995
        let expectedRatio: Float = 1.995
        let actualRatio = avgWithGain / avgNoGain

        XCTAssertEqual(actualRatio, expectedRatio, accuracy: 0.1,
                       "Makeup gain of 6dB should double the output level")
    }

    // MARK: - Attack/Release Behavior Tests

    func testAttackTimingBehavior() async {
        // Fast attack processor
        let fastProcessor = AudioNormalizationProcessor(
            thresholdDB: -20.0,
            ratio: 4.0,
            attackTimeMS: 1.0,    // Very fast attack
            releaseTimeMS: 100.0,
            makeupGainDB: 0.0,
            isBypassed: false
        )
        fastProcessor.setSampleRate(44100.0)

        // Slow attack processor
        let slowProcessor = AudioNormalizationProcessor(
            thresholdDB: -20.0,
            ratio: 4.0,
            attackTimeMS: 100.0,  // Slow attack
            releaseTimeMS: 100.0,
            makeupGainDB: 0.0,
            isBypassed: false
        )
        slowProcessor.setSampleRate(44100.0)

        // Create a signal that jumps from silence to loud
        var signal = Array(repeating: Float(0.0), count: 100)
        signal.append(contentsOf: Array(repeating: Float(0.8), count: 200))

        let fastOutput = fastProcessor.processBuffer(signal)
        let slowOutput = slowProcessor.processBuffer(signal)

        // Look at samples just after the loud section begins (around index 100-110)
        // Fast attack should compress more quickly than slow attack
        let earlyFastAvg = fastOutput[105..<115].reduce(0, +) / 10.0
        let earlySlowAvg = slowOutput[105..<115].reduce(0, +) / 10.0

        // With fast attack, the early loud samples should be more compressed (lower)
        // than with slow attack (which lets more through initially)
        XCTAssertLessThan(earlyFastAvg, earlySlowAvg,
                          "Fast attack should compress early transients more than slow attack")
    }

    func testResetClearsEnvelopeState() async {
        let processor = AudioNormalizationProcessor(
            thresholdDB: -20.0,
            ratio: 4.0,
            attackTimeMS: 10.0,
            releaseTimeMS: 1000.0,  // Very slow release to hold envelope
            makeupGainDB: 0.0,
            isBypassed: false
        )
        processor.setSampleRate(44100.0)

        // Process a loud signal to build up envelope
        let loudSignal = Array(repeating: Float(0.8), count: 500)
        _ = processor.processBuffer(loudSignal)

        // Reset the processor
        processor.reset()

        // Process a quiet signal - should not be affected by previous envelope
        let quietSignal = Array(repeating: Float(0.05), count: 100)
        let output = processor.processBuffer(quietSignal)

        // After reset, quiet signal should pass through nearly uncompressed
        // (since it's below threshold)
        let avgOutput = output.reduce(0, +) / Float(output.count)
        let avgInput = quietSignal.reduce(0, +) / Float(quietSignal.count)

        XCTAssertEqual(avgOutput, avgInput, accuracy: 0.01,
                       "After reset, quiet signals should pass uncompressed")
    }

    // MARK: - Per-Tap Isolation

    func testTwoProcessorsDoNotShareEnvelopeState() async {
        let settings = AudioNormalizationProcessor.Settings(
            thresholdDB: -20.0,
            ratio: 8.0,
            attackTimeMS: 1.0,
            releaseTimeMS: 1000.0,
            makeupGainDB: 0.0,
            isBypassed: false
        )
        let loudTap = AudioNormalizationProcessor(settings: settings)
        let quietTap = AudioNormalizationProcessor(settings: settings)
        let reference = AudioNormalizationProcessor(settings: settings)

        // Pump one processor hard: its envelope and smoothed gain drop
        _ = loudTap.processBuffer(Array(repeating: Float(0.9), count: 44_100))

        // The other processor must behave exactly like a fresh one
        let quietSignal = Array(repeating: Float(0.05), count: 512)
        let quietOutput = quietTap.processBuffer(quietSignal)
        let referenceOutput = reference.processBuffer(quietSignal)
        XCTAssertEqual(quietOutput, referenceOutput,
                       "A loud stream on one tap must not compress another tap")
    }

    func testSampleRateIsPerProcessor() async {
        let first = AudioNormalizationProcessor()
        let second = AudioNormalizationProcessor()

        first.setSampleRate(48_000)
        second.setSampleRate(22_050)

        XCTAssertEqual(first.sampleRate, 48_000)
        XCTAssertEqual(second.sampleRate, 22_050)
    }

    func testParameterUpdateKeepsSampleRate() async {
        let processor = AudioNormalizationProcessor()
        processor.setSampleRate(48_000)

        processor.applyPreset(.aggressive)

        XCTAssertEqual(processor.sampleRate, 48_000)
        XCTAssertEqual(processor.thresholdDB, -18.0, accuracy: 0.01)
    }

    func testTapManagerGivesEachTapItsOwnProcessorAndUpdatesAll() async {
        let first = AudioTapManager.makeProcessor()
        let second = AudioTapManager.makeProcessor()
        XCTAssertFalse(first === second)

        AudioTapManager.updateParameters(
            thresholdDB: -33.0,
            ratio: 5.0,
            attackTimeMS: 12.0,
            releaseTimeMS: 200.0,
            makeupGainDB: 2.0,
            isBypassed: false
        )

        XCTAssertEqual(first.thresholdDB, -33.0, accuracy: 0.01)
        XCTAssertEqual(second.thresholdDB, -33.0, accuracy: 0.01)
        XCTAssertEqual(AudioTapManager.makeProcessor().thresholdDB, -33.0, accuracy: 0.01,
                       "New taps start from the current settings")

        AudioTapManager.applyPreset(.moderate)
    }

    // MARK: - Stereo Pan

    func testStereoPanAppliesWhenBypassed() async {
        let processor = AudioNormalizationProcessor(isBypassed: true)
        var left: [Float] = Array(repeating: 0.5, count: 64)
        var right: [Float] = Array(repeating: 0.5, count: 64)

        left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                let bufferList = AudioBufferList.allocate(maximumBuffers: 2)
                defer { free(bufferList.unsafeMutablePointer) }
                bufferList[0] = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(64 * MemoryLayout<Float>.size),
                    mData: UnsafeMutableRawPointer(leftBuffer.baseAddress)
                )
                bufferList[1] = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(64 * MemoryLayout<Float>.size),
                    mData: UnsafeMutableRawPointer(rightBuffer.baseAddress)
                )
                processor.process(buffer: bufferList.unsafeMutablePointer, frameCount: 64, panValue: -1.0)
            }
        }

        XCTAssertEqual(left[0], 0.5, accuracy: 0.001, "Full left keeps the left channel")
        XCTAssertEqual(right[0], 0.0, accuracy: 0.001, "Full left silences the right channel even in bypass")
    }
}

//
//  AudioNormalizationProcessor.swift
//  gridstream-ipad
//
//  Real-time audio compressor/limiter DSP algorithm for audio normalization.
//  Implements an envelope follower with adjustable attack/release for gain reduction.
//
//  Thread Safety:
//  One processor per audio tap: envelope, gain smoothing and ramp state belong to
//  a single render thread and are never shared between players.
//  Parameters are published by writers (UI thread, tap prepare callback) into a
//  pre-allocated snapshot ring; the render thread reads them without taking a
//  lock and without allocating (see `ParameterSnapshotRing`).
//

import AVFoundation
import Accelerate
import os.lock

/// Atomic parameter snapshot for thread-safe audio processing.
/// All parameters needed by the audio thread in a single struct for atomic reads.
nonisolated private struct ProcessorParameters {
    var thresholdDB: Float = -20.0
    var ratio: Float = 4.0
    var attackTimeMS: Float = 10.0
    var releaseTimeMS: Float = 100.0
    var makeupGainDB: Float = 0.0
    var isBypassed: Bool = false
    var sampleRate: Float = 44100.0

    // Pre-calculated coefficients (avoid calculation on audio thread)
    var attackCoeff: Float = 0.0
    var releaseCoeff: Float = 0.0
    var thresholdLinear: Float = 0.0
    var makeupGainLinear: Float = 1.0

    // Gain smoothing coefficient (prevents rapid gain oscillation / "pumping")
    // Uses slower time constant than envelope for smooth gain transitions
    var gainSmoothingCoeff: Float = 0.0

    // Soft knee parameters (prevents hard on/off at threshold)
    var kneeWidthDB: Float = 6.0  // Soft knee width in dB
    var kneeStartLinear: Float = 0.0  // Threshold - knee/2
    var kneeEndLinear: Float = 0.0    // Threshold + knee/2

    // Stereo panning parameters
    var panValue: Float = 0.0  // -1.0 (full left) to 1.0 (full right)
    var leftGain: Float = 1.0  // Pre-calculated left channel gain
    var rightGain: Float = 1.0 // Pre-calculated right channel gain

    mutating func updateDerivedCoefficients() {
        // Convert threshold from dB to linear amplitude
        thresholdLinear = powf(10.0, thresholdDB / 20.0)

        // Convert makeup gain from dB to linear amplitude
        makeupGainLinear = powf(10.0, makeupGainDB / 20.0)

        // Calculate attack/release coefficients
        let attackSeconds = attackTimeMS / 1000.0
        let releaseSeconds = releaseTimeMS / 1000.0

        if attackSeconds > 0 && sampleRate > 0 {
            attackCoeff = expf(-1.0 / (attackSeconds * sampleRate))
        } else {
            attackCoeff = 0.0
        }

        if releaseSeconds > 0 && sampleRate > 0 {
            releaseCoeff = expf(-1.0 / (releaseSeconds * sampleRate))
        } else {
            releaseCoeff = 0.0
        }

        // Gain smoothing uses longer time constant to prevent "pumping"
        // Minimum 50ms smoothing to prevent audible gain modulation, scales with release
        // For aggressive compression, longer smoothing is essential
        let gainSmoothingMs = max(50.0, releaseTimeMS * 0.75)
        let gainSmoothingSeconds = gainSmoothingMs / 1000.0
        if gainSmoothingSeconds > 0 && sampleRate > 0 {
            gainSmoothingCoeff = expf(-1.0 / (gainSmoothingSeconds * sampleRate))
        } else {
            gainSmoothingCoeff = 0.99  // Fallback
        }

        // Calculate soft knee boundaries
        let halfKneeDB = kneeWidthDB / 2.0
        kneeStartLinear = powf(10.0, (thresholdDB - halfKneeDB) / 20.0)
        kneeEndLinear = powf(10.0, (thresholdDB + halfKneeDB) / 20.0)

        // Calculate equal-power pan gains for smooth stereo positioning
        // Equal-power panning maintains perceived loudness when panning
        // panValue: -1.0 = full left, 0.0 = center, 1.0 = full right
        let panAngle = (panValue + 1.0) * Float.pi / 4.0  // Maps -1..1 to 0..π/2
        leftGain = cos(panAngle)
        rightGain = sin(panAngle)
    }
}

/// Publishes `ProcessorParameters` from writer threads to the audio render
/// thread without locks or allocation on the read side.
///
/// Writers serialize among themselves with a lock (they never run on the
/// render thread), write the new value into the next slot of a small
/// pre-allocated ring and then advance `generation`. The render thread reads
/// `generation`, copies that slot, and re-reads `generation`: if the writers
/// advanced far enough to wrap around onto the slot being copied it retries a
/// bounded number of times. With eight slots, a writer would have to publish
/// seven times during a single ~100-byte copy for a retry to even be needed.
/// Every field is a plain `Float`/`Bool`, so even a theoretically torn read
/// only mixes two valid parameter sets for one buffer — never invalid memory.
nonisolated private final class ParameterSnapshotRing: @unchecked Sendable {
    private static let slotCount = 8
    private static let maxReadAttempts = 4

    private let slots: UnsafeMutablePointer<ProcessorParameters>
    private let generation: UnsafeMutablePointer<Int>
    private let writerLock = OSAllocatedUnfairLock()

    init(_ initial: ProcessorParameters) {
        slots = .allocate(capacity: Self.slotCount)
        slots.initialize(repeating: initial, count: Self.slotCount)
        generation = .allocate(capacity: 1)
        generation.initialize(to: 0)
    }

    deinit {
        slots.deinitialize(count: Self.slotCount)
        slots.deallocate()
        generation.deinitialize(count: 1)
        generation.deallocate()
    }

    /// Lock-free, allocation-free read. Safe on the audio render thread.
    func read() -> ProcessorParameters {
        var attempt = 0
        while true {
            let before = generation.pointee
            let value = slots[before % Self.slotCount]
            let after = generation.pointee
            attempt += 1
            if after &- before < Self.slotCount - 1 || attempt >= Self.maxReadAttempts {
                return value
            }
        }
    }

    /// Read-modify-publish for writers. Never call from the render thread.
    func update(_ transform: (inout ProcessorParameters) -> Void) {
        writerLock.lock()
        defer { writerLock.unlock() }
        let current = generation.pointee
        var value = slots[current % Self.slotCount]
        transform(&value)
        let next = current &+ 1
        slots[next % Self.slotCount] = value
        generation.pointee = next
    }
}

/// Audio compressor/limiter processor for real-time normalization.
///
/// Each `MTAudioProcessingTap` owns its own instance: the envelope follower,
/// gain smoother and makeup-gain ramp are per-stream state and must never be
/// shared between players. Parameters are pushed in from the UI by
/// `AudioTapManager` and read lock-free on the render thread.
nonisolated final class AudioNormalizationProcessor: @unchecked Sendable {

    /// The user-facing compressor settings shared by every processor. The
    /// sample rate (and the coefficients derived from it) stay per-processor.
    struct Settings: Equatable, Sendable {
        var thresholdDB: Float
        var ratio: Float
        var attackTimeMS: Float
        var releaseTimeMS: Float
        var makeupGainDB: Float
        var isBypassed: Bool

        /// The same settings with every value clamped to its supported range.
        func clamped() -> Settings {
            Settings(
                thresholdDB: max(-60.0, min(0.0, thresholdDB)),
                ratio: max(1.0, min(20.0, ratio)),
                attackTimeMS: max(1.0, min(100.0, attackTimeMS)),
                releaseTimeMS: max(50.0, min(1000.0, releaseTimeMS)),
                makeupGainDB: max(0.0, min(24.0, makeupGainDB)),
                isBypassed: isBypassed
            )
        }
    }

    // MARK: - Compressor Parameters (for external access)

    /// Threshold in decibels. Signals above this level are compressed.
    /// Range: -60 to 0 dB
    var thresholdDB: Float { snapshots.read().thresholdDB }

    /// Compression ratio (e.g., 4.0 means 4:1 compression)
    /// Range: 1.0 to 20.0
    var ratio: Float { snapshots.read().ratio }

    /// Attack time in milliseconds. How quickly compression engages.
    /// Range: 1 to 100 ms
    var attackTimeMS: Float { snapshots.read().attackTimeMS }

    /// Release time in milliseconds. How quickly compression releases.
    /// Range: 50 to 1000 ms
    var releaseTimeMS: Float { snapshots.read().releaseTimeMS }

    /// Makeup gain in decibels. Applied after compression.
    /// Range: 0 to 24 dB
    var makeupGainDB: Float { snapshots.read().makeupGainDB }

    /// When true the compressor is skipped (stereo pan still applies)
    var isBypassed: Bool { snapshots.read().isBypassed }

    /// Sample rate the derived coefficients are computed for.
    var sampleRate: Float { snapshots.read().sampleRate }

    /// Current user-facing settings.
    var settings: Settings {
        let params = snapshots.read()
        return Settings(
            thresholdDB: params.thresholdDB,
            ratio: params.ratio,
            attackTimeMS: params.attackTimeMS,
            releaseTimeMS: params.releaseTimeMS,
            makeupGainDB: params.makeupGainDB,
            isBypassed: params.isBypassed
        )
    }

    // MARK: - Internal State

    /// Parameter snapshots published to the render thread.
    private let snapshots: ParameterSnapshotRing

    /// Maximum supported audio channels. Pre-allocated state arrays use this size
    /// to avoid allocation on the real-time audio thread.
    /// Covers mono, stereo, quad, 5.1, and 7.1 layouts.
    private static let maxChannels = 8

    /// Per-channel envelope levels (supports stereo without interference)
    /// Pre-sized to `maxChannels` so the render path never allocates.
    private var envelopeLevels: [Float] = Array(repeating: 0.0, count: maxChannels)

    /// Per-channel smoothed gain (prevents rapid gain oscillation / "pumping")
    /// Pre-sized to `maxChannels` so the render path never allocates.
    private var smoothedGains: [Float] = Array(repeating: 1.0, count: maxChannels)

    /// Target envelope for smooth reset transitions
    private var targetEnvelopeLevel: Float = 0.0
    private var isResetting: Bool = false
    private let resetSmoothingCoeff: Float = 0.9995  // ~100ms fade at 44.1kHz

    // Equal-power pan gains for the last pan value seen on the render thread.
    // Recomputed only when the pan changes, not on every buffer.
    private var cachedPanValue: Float = 0.0
    private var cachedLeftPanGain: Float = 1.0
    private var cachedRightPanGain: Float = 1.0

    // MARK: - Makeup-gain ramp state (audio thread only)
    //
    // updateParameters() swaps the entire ProcessorParameters atomically. Without
    // ramping, a UI-driven makeupGainDB change produces a sample-accurate step in
    // output level, which is audible as a click during loud passages. We linearly
    // interpolate makeupGainLinear over `parameterRampSamples` (~5ms @ 48kHz)
    // toward each new snapshot. The fields below are mutated only on the audio
    // render thread, in lock-step with the buffer being processed, so they need
    // no synchronization beyond the audio thread's serial execution.
    //
    // Threshold/ratio/knee changes are NOT ramped: re-deriving them per sample
    // would balloon the inner loop, and the existing per-sample `smoothedGain`
    // already attenuates the audibility of those transitions.
    private static let parameterRampSamples: Int = 256

    private var rampStartMakeupGainLinear: Float = 1.0
    private var rampTargetMakeupGainLinear: Float = 1.0
    private var rampPosition: Int = parameterRampSamples
    private var rampInitialized: Bool = false

    // MARK: - Initialization

    /// Creates a processor with specified parameters.
    init(
        thresholdDB: Float = -20.0,
        ratio: Float = 4.0,
        attackTimeMS: Float = 10.0,
        releaseTimeMS: Float = 100.0,
        makeupGainDB: Float = 0.0,
        isBypassed: Bool = false
    ) {
        var initial = ProcessorParameters()
        initial.thresholdDB = thresholdDB
        initial.ratio = ratio
        initial.attackTimeMS = attackTimeMS
        initial.releaseTimeMS = releaseTimeMS
        initial.makeupGainDB = makeupGainDB
        initial.isBypassed = isBypassed
        initial.updateDerivedCoefficients()
        snapshots = ParameterSnapshotRing(initial)
    }

    /// Creates a processor configured with the given settings.
    convenience init(settings: Settings) {
        self.init()
        apply(settings)
    }

    // MARK: - Parameter Updates

    /// Updates all parameters. Never call from the render thread. The new set
    /// is published as a whole, so the render thread uses either the old or the
    /// new parameters for a given buffer.
    func updateParameters(
        thresholdDB: Float,
        ratio: Float,
        attackTimeMS: Float,
        releaseTimeMS: Float,
        makeupGainDB: Float,
        isBypassed: Bool
    ) {
        let settings = Settings(
            thresholdDB: thresholdDB,
            ratio: ratio,
            attackTimeMS: attackTimeMS,
            releaseTimeMS: releaseTimeMS,
            makeupGainDB: makeupGainDB,
            isBypassed: isBypassed
        ).clamped()
        snapshots.update { params in
            params.thresholdDB = settings.thresholdDB
            params.ratio = settings.ratio
            params.attackTimeMS = settings.attackTimeMS
            params.releaseTimeMS = settings.releaseTimeMS
            params.makeupGainDB = settings.makeupGainDB
            params.isBypassed = settings.isBypassed
            // The sample rate is kept: it belongs to this processor's stream.
            params.updateDerivedCoefficients()
        }
    }

    /// Applies user-facing settings, keeping this processor's sample rate.
    func apply(_ settings: Settings) {
        updateParameters(
            thresholdDB: settings.thresholdDB,
            ratio: settings.ratio,
            attackTimeMS: settings.attackTimeMS,
            releaseTimeMS: settings.releaseTimeMS,
            makeupGainDB: settings.makeupGainDB,
            isBypassed: settings.isBypassed
        )
    }

    /// Updates the sample rate (call when this processor's audio format changes)
    func setSampleRate(_ rate: Float) {
        guard rate > 0 else { return }
        snapshots.update { params in
            params.sampleRate = rate
            params.updateDerivedCoefficients()
        }
    }

    // MARK: - Audio Processing

    /// Processes audio samples in-place with optional stereo panning.
    /// Real-time safe: no locks, no allocation.
    /// - Parameters:
    ///   - buffer: Audio buffer list containing samples to process
    ///   - frameCount: Number of frames to process
    ///   - panValue: Stereo pan position from -1.0 (left) to 1.0 (right), 0.0 = center
    func process(buffer: UnsafeMutablePointer<AudioBufferList>, frameCount: UInt32, panValue: Float = 0.0) {
        guard frameCount > 0 else { return }

        // Snapshot parameters once for the whole buffer (lock-free)
        let params = snapshots.read()
        let bufferList = UnsafeMutableAudioBufferListPointer(buffer)
        let isPanning = panValue != 0.0 && bufferList.count >= 2

        if isPanning && panValue != cachedPanValue {
            // Equal-power panning maintains perceived loudness when panning
            let panAngle = (panValue + 1.0) * Float.pi / 4.0
            cachedLeftPanGain = cos(panAngle)
            cachedRightPanGain = sin(panAngle)
            cachedPanValue = panValue
        }

        // Bypass skips the compressor only: stereo placement is a separate
        // feature and must keep working with normalization turned off.
        guard !params.isBypassed else {
            if isPanning {
                applyPanOnly(to: bufferList)
            }
            return
        }

        // Initialize ramp state on the first real process() call so we do not
        // emit a ramp from 1.0 → first-real-target on startup.
        if !rampInitialized {
            rampStartMakeupGainLinear = params.makeupGainLinear
            rampTargetMakeupGainLinear = params.makeupGainLinear
            rampPosition = Self.parameterRampSamples
            rampInitialized = true
        }

        // If the snapshot's makeup gain differs from our current target, start
        // (or re-target mid-ramp) a new ramp from where we are right now.
        if params.makeupGainLinear != rampTargetMakeupGainLinear {
            rampStartMakeupGainLinear = currentRampedMakeupGain()
            rampTargetMakeupGainLinear = params.makeupGainLinear
            rampPosition = 0
        }

        // Snapshot the ramp window for this buffer so every channel uses the
        // same interpolation curve.
        let bufferRampStart = rampPosition
        let bufferRampStartGain = rampStartMakeupGainLinear
        let bufferRampTargetGain = rampTargetMakeupGainLinear

        // Bound the channel loop by our pre-allocated state arrays so the
        // render path never allocates. Buffers with more than `maxChannels`
        // channels (extremely rare on iPad) will leave the extra channels
        // unprocessed rather than risk a heap allocation.
        let channelCount = min(bufferList.count, envelopeLevels.count)

        // Process each channel with appropriate pan gain
        for bufferIndex in 0..<channelCount {
            guard let data = bufferList[bufferIndex].mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            let sampleCount = Int(bufferList[bufferIndex].mDataByteSize) / MemoryLayout<Float>.size

            // Determine pan gain for this channel (0 = left, 1 = right)
            let channelPanGain = isPanning ? panGain(forChannel: bufferIndex) : 1.0

            processChannel(
                samples: samples,
                count: sampleCount,
                channelIndex: bufferIndex,
                params: params,
                panGain: channelPanGain,
                rampStartIndex: bufferRampStart,
                rampStartMakeupGain: bufferRampStartGain,
                rampTargetMakeupGain: bufferRampTargetGain
            )
        }

        // Advance the ramp position by the number of samples we just consumed
        // (frameCount is the per-channel sample count; all channels share it).
        rampPosition = min(Self.parameterRampSamples, rampPosition + Int(frameCount))
    }

    private func panGain(forChannel channel: Int) -> Float {
        switch channel {
        case 0: return cachedLeftPanGain
        case 1: return cachedRightPanGain
        default: return 1.0
        }
    }

    /// Applies only the stereo pan gains (bypass path).
    private func applyPanOnly(to bufferList: UnsafeMutableAudioBufferListPointer) {
        for channel in 0..<min(bufferList.count, 2) {
            guard let data = bufferList[channel].mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            let sampleCount = Int(bufferList[channel].mDataByteSize) / MemoryLayout<Float>.size
            var gain = panGain(forChannel: channel)
            vDSP_vsmul(samples, 1, &gain, samples, 1, vDSP_Length(sampleCount))
        }
    }

    /// Linear interpolation of the makeup-gain ramp at the current
    /// `rampPosition`. Used when a new target arrives mid-ramp so we restart
    /// from the value we were emitting, not from the stale ramp start.
    private func currentRampedMakeupGain() -> Float {
        let total = Float(Self.parameterRampSamples)
        let t = min(Float(rampPosition), total) / total
        return rampStartMakeupGainLinear + (rampTargetMakeupGainLinear - rampStartMakeupGainLinear) * t
    }

    /// Processes a single channel of audio samples in-place.
    /// Uses pre-snapshotted parameters for consistency across the buffer.
    /// Implements soft knee compression with gain smoothing to prevent pumping artifacts.
    /// - Parameters:
    ///   - samples: Pointer to float samples
    ///   - count: Number of samples to process
    ///   - channelIndex: Index of the audio channel (for per-channel state)
    ///   - params: Pre-snapshotted parameters for this buffer
    ///   - panGain: Pan gain multiplier for this channel (1.0 = full, 0.0 = silent)
    ///   - rampStartIndex: Sample offset into the makeup-gain ramp at sample 0 of this buffer.
    ///   - rampStartMakeupGain: Makeup gain at the start of the active ramp.
    ///   - rampTargetMakeupGain: Makeup gain at the end of the active ramp.
    private func processChannel(
        samples: UnsafeMutablePointer<Float>,
        count: Int,
        channelIndex: Int,
        params: ProcessorParameters,
        panGain: Float,
        rampStartIndex: Int,
        rampStartMakeupGain: Float,
        rampTargetMakeupGain: Float
    ) {
        guard !params.isBypassed else { return }
        guard count > 0 else { return }

        // Cache parameters locally for tight loop (avoid struct access overhead)
        let attackCoeff = params.attackCoeff
        let releaseCoeff = params.releaseCoeff
        let thresholdLinear = params.thresholdLinear
        let ratio = params.ratio
        let gainSmoothingCoeff = params.gainSmoothingCoeff
        let kneeStartLinear = params.kneeStartLinear
        let kneeEndLinear = params.kneeEndLinear
        let kneeWidthDB = params.kneeWidthDB

        let rampSamples = Self.parameterRampSamples
        let invRampSamples = 1.0 / Float(rampSamples)
        let makeupDelta = rampTargetMakeupGain - rampStartMakeupGain

        // Use the canonical threshold in dB directly from the snapshot.
        // (Recomputing it from `thresholdLinear` via log10f would be a
        // redundant round-trip — they are equivalent by construction.)
        let thresholdDB = params.thresholdDB
        let kneeStartDB = thresholdDB - kneeWidthDB / 2.0

        // Get per-channel state
        var envelopeLevel = envelopeLevels[channelIndex]
        var smoothedGain = smoothedGains[channelIndex]

        for i in 0..<count {
            let input = samples[i]

            // Get absolute value for envelope detection
            let inputAbs = abs(input)

            // Handle smooth envelope reset (fade to target instead of jump)
            if isResetting {
                envelopeLevel = resetSmoothingCoeff * envelopeLevel + (1.0 - resetSmoothingCoeff) * targetEnvelopeLevel
                if abs(envelopeLevel - targetEnvelopeLevel) < 0.0001 {
                    envelopeLevel = targetEnvelopeLevel
                    // Note: isResetting is shared; will be cleared when all channels converge
                }
            }

            // Envelope follower with attack/release
            if inputAbs > envelopeLevel {
                // Attack phase: envelope rises toward input
                envelopeLevel = attackCoeff * envelopeLevel + (1.0 - attackCoeff) * inputAbs
            } else {
                // Release phase: envelope falls toward input
                envelopeLevel = releaseCoeff * envelopeLevel + (1.0 - releaseCoeff) * inputAbs
            }

            // Calculate target gain with soft knee
            var targetGain: Float = 1.0

            if envelopeLevel > kneeStartLinear && thresholdLinear > 0 {
                let envelopeDB = 20.0 * log10f(max(envelopeLevel, 1e-10))

                var gainReductionDB: Float = 0.0

                if envelopeLevel >= kneeEndLinear {
                    // Above knee: full compression
                    let overThresholdDB = envelopeDB - thresholdDB
                    gainReductionDB = overThresholdDB * (1.0 - 1.0 / ratio)
                } else {
                    // In the knee: gradual compression (quadratic interpolation)
                    // Smoothly transitions from no compression to full compression
                    let kneePositionDB = envelopeDB - kneeStartDB
                    let kneeRatio = kneePositionDB / kneeWidthDB  // 0 to 1 through knee
                    // Quadratic curve: starts slow, ends at full compression rate
                    let compressionFactor = kneeRatio * kneeRatio * (1.0 - 1.0 / ratio)
                    gainReductionDB = kneePositionDB * compressionFactor
                }

                // Convert gain reduction from dB to linear
                targetGain = powf(10.0, -gainReductionDB / 20.0)
            }

            // Smooth the gain to prevent rapid oscillation ("pumping")
            // This is the key fix: gain changes gradually, not instantly
            if targetGain < smoothedGain {
                // Gain decreasing (compression engaging): use faster smoothing
                smoothedGain = gainSmoothingCoeff * smoothedGain + (1.0 - gainSmoothingCoeff) * targetGain
            } else {
                // Gain increasing (compression releasing): use same smoothing
                // Could use slower release here if needed, but symmetric works well
                smoothedGain = gainSmoothingCoeff * smoothedGain + (1.0 - gainSmoothingCoeff) * targetGain
            }

            // Interpolate makeup gain across the ramp window so UI-driven
            // parameter changes do not produce an audible step in output level.
            let rampPos = rampStartIndex + i
            let currentMakeupGain: Float
            if rampPos >= rampSamples {
                currentMakeupGain = rampTargetMakeupGain
            } else {
                currentMakeupGain = rampStartMakeupGain + makeupDelta * Float(rampPos) * invRampSamples
            }

            // Apply smoothed gain, makeup gain, and pan gain
            samples[i] = input * smoothedGain * currentMakeupGain * panGain
        }

        // Store updated per-channel state
        envelopeLevels[channelIndex] = envelopeLevel
        smoothedGains[channelIndex] = smoothedGain

        // Check if reset is complete (all channels converged)
        if isResetting && abs(envelopeLevel - targetEnvelopeLevel) < 0.0001 {
            var allConverged = true
            for level in envelopeLevels {
                if abs(level - targetEnvelopeLevel) >= 0.0001 {
                    allConverged = false
                    break
                }
            }
            if allConverged {
                isResetting = false
            }
        }
    }

    /// Processes a single channel of audio samples in-place (public version for testing).
    /// - Parameters:
    ///   - samples: Pointer to float samples
    ///   - count: Number of samples to process
    func processChannel(samples: UnsafeMutablePointer<Float>, count: Int) {
        let params = snapshots.read()

        // Use channel 0 for single-channel testing.
        // Test helpers bypass the makeup-gain ramp by setting both ramp ends to
        // the current target — the ramp arithmetic collapses to a constant.
        processChannel(
            samples: samples,
            count: count,
            channelIndex: 0,
            params: params,
            panGain: 1.0,
            rampStartIndex: Self.parameterRampSamples,
            rampStartMakeupGain: params.makeupGainLinear,
            rampTargetMakeupGain: params.makeupGainLinear
        )
    }

    /// Processes a buffer of samples and returns the result (for testing).
    /// - Parameters:
    ///   - input: Array of input samples
    /// - Returns: Array of processed samples
    func processBuffer(_ input: [Float]) -> [Float] {
        let params = snapshots.read()

        guard !params.isBypassed else { return input }

        var output = input
        output.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            // Use channel 0 for single-channel testing
            processChannel(
                samples: baseAddress,
                count: buffer.count,
                channelIndex: 0,
                params: params,
                panGain: 1.0,
                rampStartIndex: Self.parameterRampSamples,
                rampStartMakeupGain: params.makeupGainLinear,
                rampTargetMakeupGain: params.makeupGainLinear
            )
        }
        return output
    }

    /// Resets the envelope state with smooth transition (call when seeking or switching tracks).
    /// Instead of abruptly setting envelope to 0, fades smoothly to prevent glitches.
    /// Only affects this processor, i.e. this tap's stream.
    func reset() {
        // Smooth reset: fade envelope to 0 over ~100ms instead of instant jump
        targetEnvelopeLevel = 0.0
        isResetting = true
    }
}

// MARK: - Preset Configuration

nonisolated extension AudioNormalizationProcessor {

    /// Preset configurations for common use cases
    enum Preset: String, CaseIterable {
        case off
        case gentle
        case moderate
        case aggressive
        case custom

        var displayName: String {
            switch self {
            case .off: return "Off"
            case .gentle: return "Gentle"
            case .moderate: return "Moderate"
            case .aggressive: return "Aggressive"
            case .custom: return "Custom"
            }
        }
    }

    /// Returns default parameters for a preset
    static func parameters(for preset: Preset) -> (thresholdDB: Float, ratio: Float, attackTimeMS: Float, releaseTimeMS: Float, makeupGainDB: Float, isBypassed: Bool) {
        switch preset {
        case .off:
            return (thresholdDB: -20.0, ratio: 4.0, attackTimeMS: 10.0, releaseTimeMS: 100.0, makeupGainDB: 0.0, isBypassed: true)
        case .gentle:
            return (thresholdDB: -12.0, ratio: 2.0, attackTimeMS: 20.0, releaseTimeMS: 200.0, makeupGainDB: 0.0, isBypassed: false)
        case .moderate:
            return (thresholdDB: -20.0, ratio: 4.0, attackTimeMS: 10.0, releaseTimeMS: 100.0, makeupGainDB: 3.0, isBypassed: false)
        case .aggressive:
            // Adjusted from original -30dB/-50ms which caused constant compression modulation ("hatching")
            // -18dB threshold prevents compression on very quiet content
            // 150ms release prevents rapid gain pumping
            return (thresholdDB: -18.0, ratio: 6.0, attackTimeMS: 5.0, releaseTimeMS: 150.0, makeupGainDB: 4.0, isBypassed: false)
        case .custom:
            // Custom returns moderate as default
            return (thresholdDB: -20.0, ratio: 4.0, attackTimeMS: 10.0, releaseTimeMS: 100.0, makeupGainDB: 0.0, isBypassed: false)
        }
    }

    /// Configures the processor with a preset
    func applyPreset(_ preset: Preset) {
        let params = Self.parameters(for: preset)
        updateParameters(
            thresholdDB: params.thresholdDB,
            ratio: params.ratio,
            attackTimeMS: params.attackTimeMS,
            releaseTimeMS: params.releaseTimeMS,
            makeupGainDB: params.makeupGainDB,
            isBypassed: params.isBypassed
        )
    }
}

//
//  AudioTapManager.swift
//  gridstream-ipad
//
//  MTAudioProcessingTap wrapper for attaching audio processing to AVPlayerItem.
//  Handles tap lifecycle and routes audio through AudioNormalizationProcessor.
//

import AVFoundation
import MediaToolbox
import OSLog

/// Manages MTAudioProcessingTap attachment to AVPlayerItem for real-time audio processing.
final class AudioTapManager {

    // MARK: - Settings

    /// The compressor settings every tap uses. Each tap gets its own
    /// `AudioNormalizationProcessor` (its envelope / gain state belongs to one
    /// stream), initialised from these settings and kept in sync with them.
    private(set) static var currentSettings = AudioNormalizationProcessor().settings

    /// Processors of the taps that are still alive. Weak: a processor lives
    /// exactly as long as its tap context, which the tap's finalize releases.
    private static var liveProcessors: [WeakProcessor] = []

    private final class WeakProcessor {
        weak var processor: AudioNormalizationProcessor?
        init(_ processor: AudioNormalizationProcessor) { self.processor = processor }
    }

    /// Makes a processor for a new tap with the current settings and tracks
    /// it so later settings changes reach it.
    static func makeProcessor() -> AudioNormalizationProcessor {
        let processor = AudioNormalizationProcessor(settings: currentSettings)
        liveProcessors.removeAll { $0.processor == nil }
        liveProcessors.append(WeakProcessor(processor))
        return processor
    }

    private static func applyToLiveProcessors(_ settings: AudioNormalizationProcessor.Settings) {
        currentSettings = settings
        liveProcessors.removeAll { $0.processor == nil }
        for entry in liveProcessors {
            entry.processor?.apply(settings)
        }
    }

    // MARK: - Tap Context

    /// Context passed to tap callbacks. Owns the tap's processor.
    private class TapContext {
        let processor: AudioNormalizationProcessor
        let tileIndex: Int?
        var audioFormat: AudioStreamBasicDescription?
        // Latched on first failure inside the render callback so we never
        // log on every audio buffer when the source can't be read.
        var hasLoggedSourceAudioFailure: Bool = false
        // Cached pan value for this tap. Written from the main thread via
        // `StereoPanState`'s observer callback, read from the audio render
        // thread. A naturally aligned 4-byte `Float` load/store is atomic on
        // ARM64/x86_64, so the render thread can read it without acquiring
        // any lock.
        var panValue: Float = 0.0
        // Holds the `StereoPanState` observer registration. Releasing the
        // token (which happens when this context is released) unregisters
        // the observer automatically.
        var panObserverToken: PanObserverToken?

        init(processor: AudioNormalizationProcessor, tileIndex: Int? = nil) {
            self.processor = processor
            self.tileIndex = tileIndex
        }
    }

    // MARK: - Public API

    /// Creates an AVAudioMix with an audio processing tap attached to the audio track.
    /// - Parameters:
    ///   - playerItem: The AVPlayerItem to process
    ///   - tileIndex: Optional tile index for stereo panning (nil = no panning, e.g. fullscreen video)
    /// - Returns: An AVAudioMix configured with the processing tap, or nil if creation fails
    static func createAudioMix(for playerItem: AVPlayerItem, tileIndex: Int? = nil) async -> AVAudioMix? {
        guard let audioTrack = try? await playerItem.asset.loadTracks(withMediaType: .audio).first else {
            AppLogger.video.debug("No audio track found for audio tap")
            return nil
        }

        // Each tap gets its own processor: compressor state is per stream
        let context = TapContext(processor: makeProcessor(), tileIndex: tileIndex)

        // Subscribe to pan changes so the render thread never has to take a
        // lock to read the current pan value. The callback writes a single
        // aligned `Float` (atomic on supported architectures), which the
        // render thread reads via `context.panValue`. The token is owned by
        // the context, so when the context is released the observer is
        // unregistered automatically.
        if let tileIndex = tileIndex {
            context.panObserverToken = StereoPanState.shared.registerPanObserver(tileIndex: tileIndex) { [weak context] newPan in
                context?.panValue = newPan
            }
        }

        let contextPointer = Unmanaged.passRetained(context).toOpaque()

        // Set up callbacks
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: contextPointer,
            init: tapInitCallback,
            finalize: tapFinalizeCallback,
            prepare: tapPrepareCallback,
            unprepare: tapUnprepareCallback,
            process: tapProcessCallback
        )

        // Create the tap
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tap
        )

        guard status == noErr, let audioTap = tap else {
            AppLogger.video.error("Failed to create audio processing tap: \(status)")
            Unmanaged<TapContext>.fromOpaque(contextPointer).release()
            return nil
        }

        // Create audio mix input parameters
        let inputParams = AVMutableAudioMixInputParameters(track: audioTrack)
        inputParams.audioTapProcessor = audioTap

        // Create and configure audio mix
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [inputParams]

        AppLogger.video.debug("Audio processing tap created successfully")

        return audioMix
    }

    /// Applies a preset to every tap
    static func applyPreset(_ preset: AudioNormalizationProcessor.Preset) {
        let params = AudioNormalizationProcessor.parameters(for: preset)
        updateParameters(
            thresholdDB: params.thresholdDB,
            ratio: params.ratio,
            attackTimeMS: params.attackTimeMS,
            releaseTimeMS: params.releaseTimeMS,
            makeupGainDB: params.makeupGainDB,
            isBypassed: params.isBypassed
        )
        AppLogger.video.info("Applied audio normalization preset: \(preset.displayName)")
    }

    /// Applies custom parameters to every tap
    static func updateParameters(
        thresholdDB: Float,
        ratio: Float,
        attackTimeMS: Float,
        releaseTimeMS: Float,
        makeupGainDB: Float,
        isBypassed: Bool
    ) {
        let settings = AudioNormalizationProcessor.Settings(
            thresholdDB: thresholdDB,
            ratio: ratio,
            attackTimeMS: attackTimeMS,
            releaseTimeMS: releaseTimeMS,
            makeupGainDB: makeupGainDB,
            isBypassed: isBypassed
        ).clamped()
        applyToLiveProcessors(settings)
        AppLogger.video.debug("Updated audio normalization parameters")
    }

    // MARK: - Tap Callbacks

    /// Called when tap is initialized
    private static let tapInitCallback: MTAudioProcessingTapInitCallback = { tap, clientInfo, tapStorageOut in
        // Store context pointer in tap storage for later callbacks
        tapStorageOut.pointee = clientInfo
    }

    /// Called when tap is finalized
    private static let tapFinalizeCallback: MTAudioProcessingTapFinalizeCallback = { tap in
        // Release the context
        let storage = MTAudioProcessingTapGetStorage(tap)
        Unmanaged<TapContext>.fromOpaque(storage).release()
    }

    /// Called when tap is preparing to process audio
    private static let tapPrepareCallback: MTAudioProcessingTapPrepareCallback = { tap, maxFrames, processingFormat in
        let storage = MTAudioProcessingTapGetStorage(tap)
        let context = Unmanaged<TapContext>.fromOpaque(storage).takeUnretainedValue()

        // Store the audio format
        context.audioFormat = processingFormat.pointee

        // Update this tap's processor sample rate (other taps keep their own)
        let sampleRate = Float(processingFormat.pointee.mSampleRate)
        context.processor.setSampleRate(sampleRate)

        AppLogger.video.debug("Audio tap prepared - sample rate: \(sampleRate), max frames: \(maxFrames)")
    }

    /// Called when tap is unpreparing
    private static let tapUnprepareCallback: MTAudioProcessingTapUnprepareCallback = { tap in
        let storage = MTAudioProcessingTapGetStorage(tap)
        let context = Unmanaged<TapContext>.fromOpaque(storage).takeUnretainedValue()

        // Reset this tap's processor state only
        context.processor.reset()

        AppLogger.video.debug("Audio tap unprepared")
    }

    /// Called for each buffer of audio to process
    private static let tapProcessCallback: MTAudioProcessingTapProcessCallback = { tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut in
        let storage = MTAudioProcessingTapGetStorage(tap)
        let context = Unmanaged<TapContext>.fromOpaque(storage).takeUnretainedValue()

        // Get source audio
        let status = MTAudioProcessingTapGetSourceAudio(
            tap,
            numberFrames,
            bufferListInOut,
            flagsOut,
            nil,
            numberFramesOut
        )

        guard status == noErr else {
            // Log only the first failure for this tap to avoid spamming the
            // audio render thread (which is not safe for repeated logging).
            if !context.hasLoggedSourceAudioFailure {
                context.hasLoggedSourceAudioFailure = true
                AppLogger.video.error("Failed to get source audio: \(status)")
            }
            return
        }

        // Read the cached pan value. This is updated on the main thread via
        // the observer registered in `createAudioMix`. No lock needed: an
        // aligned `Float` load is atomic on ARM64/x86_64.
        let panValue = context.panValue

        // Process the audio in-place with optional panning
        context.processor.process(buffer: bufferListInOut, frameCount: UInt32(numberFramesOut.pointee), panValue: panValue)
    }
}

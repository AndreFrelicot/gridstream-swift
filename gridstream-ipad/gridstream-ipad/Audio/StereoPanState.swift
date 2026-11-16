//
//  StereoPanState.swift
//  gridstream-ipad
//
//  Thread-safe storage for stereo panning state.
//  Accessed from both main thread (UI) and audio render thread (MTAudioProcessingTap).
//
//  The audio render thread does NOT call into this type. Instead it reads a
//  cached `panValue` on its `TapContext`, which the main thread keeps in sync
//  via `registerPanObserver`. This keeps the render path lock-free.
//

import Foundation
import os.lock

/// Opaque token returned by `StereoPanState.registerPanObserver`.
/// Releasing the token (typically by deinitialising its owner) automatically
/// unregisters the observer.
nonisolated final class PanObserverToken: Sendable {
    fileprivate let id = UUID()
    private let onDeinit: @Sendable (UUID) -> Void

    fileprivate init(onDeinit: @escaping @Sendable (UUID) -> Void) {
        self.onDeinit = onDeinit
    }

    deinit {
        onDeinit(id)
    }
}

/// Thread-safe storage for stereo panning configuration.
/// Uses unfair lock for fast access from the audio render thread.
/// All mutable state is guarded by `lock`, hence `@unchecked Sendable`.
nonisolated final class StereoPanState: @unchecked Sendable {

    // MARK: - Shared Instance

    static let shared = StereoPanState()

    // MARK: - Private Storage

    private var _isEnabled: Bool = false
    private var _panValues: [Int: Float] = [:]  // tileIndex -> pan (-1.0 to 1.0)
    private let lock = OSAllocatedUnfairLock()

    /// Observer registry. Each entry has a mutable `tileIndex` so that reindex
    /// operations can update it in place without forcing observers to
    /// re-register.
    private final class Observation {
        var tileIndex: Int
        let callback: (Float) -> Void
        init(tileIndex: Int, callback: @escaping (Float) -> Void) {
            self.tileIndex = tileIndex
            self.callback = callback
        }
    }

    private var observers: [UUID: Observation] = [:]

    // MARK: - UserDefaults Keys

    private let enabledKey = "stereoPanningEnabled"

    // MARK: - Initialization

    private init() {
        // Load persisted enabled state
        _isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
    }

    // MARK: - Public API

    /// Whether stereo panning is enabled
    var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isEnabled
    }

    /// Enables or disables stereo panning
    /// - Parameter enabled: Whether to enable stereo panning
    func setEnabled(_ enabled: Bool) {
        lock.lock()
        _isEnabled = enabled
        if !enabled {
            // Reset all pan values when disabled
            _panValues.removeAll()
        }
        // Notify every observer with its effective value under the new state.
        for obs in observers.values {
            let value = _isEnabled ? (_panValues[obs.tileIndex] ?? 0.0) : 0.0
            obs.callback(value)
        }
        lock.unlock()

        // Persist to UserDefaults (outside lock since it's main thread safe)
        UserDefaults.standard.set(enabled, forKey: enabledKey)
    }

    /// Sets the pan value for a specific tile
    /// - Parameters:
    ///   - pan: Pan value from -1.0 (full left) to 1.0 (full right)
    ///   - tileIndex: The tile index to set pan for
    func setPan(_ pan: Float, for tileIndex: Int) {
        let clampedPan = max(-1.0, min(1.0, pan))
        lock.lock()
        _panValues[tileIndex] = clampedPan
        if _isEnabled {
            for obs in observers.values where obs.tileIndex == tileIndex {
                obs.callback(clampedPan)
            }
        }
        lock.unlock()
    }

    /// Gets the pan value for a specific tile.
    /// Returns 0.0 (center) if panning is disabled or tile has no pan value set.
    ///
    /// - Important: This API takes a lock. Real-time audio code should NOT
    ///   call this — use `registerPanObserver` to receive cached updates.
    ///
    /// - Parameter tileIndex: The tile index to get pan for
    /// - Returns: Pan value from -1.0 to 1.0, or 0.0 if disabled/not set
    func panValue(for tileIndex: Int) -> Float {
        lock.lock()
        defer { lock.unlock() }

        guard _isEnabled else { return 0.0 }
        return _panValues[tileIndex] ?? 0.0
    }

    /// Clears the pan value for a specific tile
    /// - Parameter tileIndex: The tile index to clear
    func clearPan(for tileIndex: Int) {
        lock.lock()
        _panValues.removeValue(forKey: tileIndex)
        if _isEnabled {
            for obs in observers.values where obs.tileIndex == tileIndex {
                obs.callback(0.0)
            }
        }
        lock.unlock()
    }

    /// Reindexes pan values when tiles are removed or reordered.
    /// Observers whose `tileIndex` appears in `newIndices` are remapped in
    /// place and notified with their new effective value.
    func reindexPanValues(newIndices: [Int: Int]) {
        lock.lock()
        var newPanValues: [Int: Float] = [:]
        for (oldIndex, newIndex) in newIndices {
            if let pan = _panValues[oldIndex] {
                newPanValues[newIndex] = pan
            }
        }
        _panValues = newPanValues

        // Remap observers in place and notify with current effective value.
        for obs in observers.values {
            if let newIdx = newIndices[obs.tileIndex] {
                obs.tileIndex = newIdx
            }
            let value = _isEnabled ? (_panValues[obs.tileIndex] ?? 0.0) : 0.0
            obs.callback(value)
        }
        lock.unlock()
    }

    /// Clears all pan values
    func clearAllPanValues() {
        lock.lock()
        _panValues.removeAll()
        // After clearing, every observed tile resolves to 0.0.
        for obs in observers.values {
            obs.callback(0.0)
        }
        lock.unlock()
    }

    // MARK: - Observer Registration

    /// Register a callback that fires whenever the effective pan for
    /// `tileIndex` changes (set, clear, enable toggle, or reindex).
    ///
    /// The callback fires once synchronously with the current effective value
    /// before the call returns, so the caller can use that initial value to
    /// seed any cached state.
    ///
    /// Releasing the returned token (typically when its owner is freed)
    /// automatically unregisters the observer. The callback may be invoked
    /// from any thread that calls into this type — most commonly main thread.
    ///
    /// - Important: Callbacks run while the internal lock is held. Do NOT
    ///   re-enter `StereoPanState` from inside a callback or you will
    ///   deadlock. Keep callbacks to simple field assignments.
    func registerPanObserver(tileIndex: Int, callback: @escaping (Float) -> Void) -> PanObserverToken {
        lock.lock()
        defer { lock.unlock() }
        let token = PanObserverToken { [weak self] id in
            self?.unregister(id)
        }
        observers[token.id] = Observation(tileIndex: tileIndex, callback: callback)
        let initialValue: Float = _isEnabled ? (_panValues[tileIndex] ?? 0.0) : 0.0
        callback(initialValue)
        return token
    }

    private func unregister(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        observers.removeValue(forKey: id)
    }
}

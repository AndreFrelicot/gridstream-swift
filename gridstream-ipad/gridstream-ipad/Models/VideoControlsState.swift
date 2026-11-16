//
//  VideoControlsState.swift
//  gridstream-ipad
//

import Foundation
import OSLog

@Observable
final class VideoControlsState {
    private(set) var isVisible = false
    private(set) var isPinned = false

    /// When true, auto-hide is temporarily suspended (e.g., while a popover is open)
    private(set) var isSuspended = false

    // Only touched on the main actor, and in deinit once nothing else holds
    // the object.
    @ObservationIgnored nonisolated(unsafe) private var hideTask: Task<Void, Never>?
    private let autoHideDelay: UInt64 = 3_000_000_000

    func show() {
        isVisible = true
        if !isPinned && !isSuspended {
            startAutoHideTimer()
        }
        AppLogger.video.debug("Video controls shown")
    }

    func hide() {
        guard !isPinned && !isSuspended else {
            AppLogger.video.debug("Video controls hide blocked - controls are pinned or suspended")
            return
        }

        cancelTimer()
        isVisible = false
        AppLogger.video.debug("Video controls hidden")
    }

    /// Suspends auto-hide timer (use when popover is open)
    func suspendAutoHide() {
        isSuspended = true
        cancelTimer()
        AppLogger.video.debug("Video controls auto-hide suspended")
    }

    /// Resumes auto-hide timer (use when popover is closed)
    func resumeAutoHide() {
        isSuspended = false
        if isVisible && !isPinned {
            startAutoHideTimer()
        }
        AppLogger.video.debug("Video controls auto-hide resumed")
    }

    /// Force hides controls immediately, ignoring pinned state.
    /// Used for double-tap to instantly dismiss controls.
    func forceHide() {
        cancelTimer()
        isPinned = false
        isVisible = false
        AppLogger.video.debug("Video controls force hidden via double-tap")
    }

    func togglePin() {
        isPinned.toggle()

        if isPinned {
            cancelTimer()
            AppLogger.video.debug("Video controls pinned")
        } else {
            startAutoHideTimer()
            AppLogger.video.debug("Video controls unpinned")
        }
    }

    func resetTimer() {
        guard isVisible, !isPinned, !isSuspended else { return }
        startAutoHideTimer()
    }

    private func startAutoHideTimer() {
        guard !isSuspended else { return }
        cancelTimer()

        hideTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.autoHideDelay ?? 3_000_000_000)
                guard self?.isPinned == false && self?.isSuspended == false else { return }
                self?.isVisible = false
                AppLogger.video.debug("Video controls auto-hidden after timeout")
            } catch {
                // Task was cancelled, which is expected behavior
            }
        }
    }

    private func cancelTimer() {
        hideTask?.cancel()
        hideTask = nil
    }

    deinit {
        hideTask?.cancel()
    }
}

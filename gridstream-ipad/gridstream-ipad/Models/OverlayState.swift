//
//  OverlayState.swift
//  gridstream-ipad
//

import Foundation
import OSLog

@Observable
final class OverlayState {
    private(set) var isVisible = false
    private(set) var isSuspended = false
    // Only touched on the main actor, and in deinit once nothing else holds
    // the object.
    @ObservationIgnored nonisolated(unsafe) private var hideTask: Task<Void, Never>?
    private let autoHideDelay: UInt64 = 4_000_000_000

    func show() {
        isVisible = true
        if !isSuspended {
            startAutoHideTimer()
        }
        AppLogger.overlay.debug("Overlay shown")
    }

    func hide() {
        guard !isSuspended else { return }
        cancelTimer()
        isVisible = false
        AppLogger.overlay.debug("Overlay hidden")
    }

    func resetTimer() {
        guard isVisible, !isSuspended else { return }
        startAutoHideTimer()
        AppLogger.overlay.debug("Overlay timer reset")
    }

    func suspendAutoHide() {
        isSuspended = true
        cancelTimer()
        AppLogger.overlay.debug("Overlay auto-hide suspended")
    }

    func resumeAutoHide() {
        isSuspended = false
        if isVisible {
            startAutoHideTimer()
        }
        AppLogger.overlay.debug("Overlay auto-hide resumed")
    }

    private func startAutoHideTimer() {
        guard !isSuspended else { return }
        cancelTimer()

        hideTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.autoHideDelay ?? 4_000_000_000)
                guard self?.isSuspended == false else { return }
                self?.isVisible = false
                AppLogger.overlay.debug("Overlay auto-hidden after timeout")
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

//
//  CatalogStatusManager.swift
//  gridstream-ipad
//
//  Manages catalog version tracking and polling to detect when the
//  video catalog on the server has changed.
//

import Foundation
import OSLog
import SwiftUI

/// Manages catalog version tracking and polling.
/// Detects when the video catalog has changed on the macOS server.
@Observable
@MainActor
final class CatalogStatusManager {
    /// Whether the catalog is dirty (server version differs from stored version)
    private(set) var catalogIsDirty = false

    /// The last-known catalog version from the server
    private(set) var storedVersion: Int64 = 0

    /// Whether polling is currently active
    private(set) var isPolling = false

    /// The server URL to poll
    var configuredServerURL: URL? { serverURL }

    private var serverURL: URL?
    private var latestServerVersion: Int64?

    /// Polling interval in seconds
    private let pollingInterval: TimeInterval = 10.0

    /// UserDefaults key for storing the catalog version
    private let versionKey = "catalogVersion"

    /// The content library service for API calls
    private let contentLibraryService = ContentLibraryService()

    /// The polling task
    private var pollingTask: Task<Void, Never>?

    /// Scene phase tracking for background/foreground detection
    private var scenePhase: ScenePhase = .active

    // MARK: - Initialization

    init() {
        loadStoredVersion()
    }

    // MARK: - Configuration

    /// Configures the manager with a server URL and starts polling.
    /// - Parameter serverURL: The base server URL
    func configure(serverURL: URL) {
        if self.serverURL != serverURL { latestServerVersion = nil }
        self.serverURL = serverURL
        AppLogger.video.info("CatalogStatusManager configured with server: \(serverURL.absoluteString)")
        startPolling()
    }

    /// Stops polling and forgets the server until `configure(serverURL:)` is
    /// called again. Used while there is no authorized session: polling
    /// without one only produces 401s.
    func suspend() {
        stopPolling()
        serverURL = nil
    }

    // MARK: - Scene Phase Handling

    /// Updates the scene phase and manages polling accordingly.
    /// - Parameter phase: The current scene phase
    func updateScenePhase(_ phase: ScenePhase) {
        let previousPhase = scenePhase
        scenePhase = phase

        switch phase {
        case .active:
            if previousPhase != .active, serverURL != nil {
                AppLogger.video.info("App became active, resuming catalog polling")
                startPolling()
                // Immediately check for updates when coming to foreground
                Task {
                    await checkCatalogStatus()
                }
            }
        case .inactive, .background:
            if previousPhase == .active {
                AppLogger.video.info("App going to background, stopping catalog polling")
                stopPolling()
            }
        @unknown default:
            break
        }
    }

    // MARK: - Polling Control

    /// Starts periodic polling of the catalog status endpoint.
    func startPolling() {
        guard serverURL != nil else {
            AppLogger.video.warning("Cannot start polling: no server URL configured")
            return
        }

        guard !isPolling else {
            AppLogger.video.debug("Polling already active, skipping start")
            return
        }

        isPolling = true
        AppLogger.video.info("Starting catalog status polling (interval: \(Int(self.pollingInterval))s)")

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }

                await self.checkCatalogStatus()

                do {
                    try await Task.sleep(for: .seconds(pollingInterval))
                } catch {
                    // Task was cancelled
                    break
                }
            }
        }
    }

    /// Stops periodic polling.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
        AppLogger.video.info("Stopped catalog status polling")
    }

    // MARK: - Status Checking

    /// Checks the catalog status and updates the dirty flag.
    func checkCatalogStatus() async {
        guard let serverURL = serverURL else {
            AppLogger.video.warning("Cannot check catalog status: no server URL")
            return
        }

        do {
            let serverVersion = try await contentLibraryService.fetchCatalogStatus(from: serverURL)
            guard self.serverURL == serverURL, !Task.isCancelled else { return }
            updateDirtyState(serverVersion: serverVersion)
        } catch {
            AppLogger.video.error("Failed to fetch catalog status: \(error.localizedDescription)")
            // On error, don't change dirty state - just log and continue
        }
    }

    // MARK: - Refresh Action

    /// Called when the user triggers a refresh.
    /// Updates the stored version and clears the dirty state.
    /// - Parameter newVersion: The new catalog version after refresh (optional, will fetch if nil)
    func markRefreshed(newVersion: Int64? = nil) async {
        if let version = newVersion {
            updateStoredVersion(version)
        } else if let serverURL = serverURL {
            // Fetch the current version from server
            do {
                let version = try await contentLibraryService.fetchCatalogStatus(from: serverURL)
                guard self.serverURL == serverURL, !Task.isCancelled else { return }
                latestServerVersion = version
                updateStoredVersion(version)
            } catch {
                AppLogger.video.error("Failed to fetch version after refresh: \(error.localizedDescription)")
                return
            }
        } else {
            return
        }

        catalogIsDirty = latestServerVersion.map { $0 != storedVersion } ?? false
        AppLogger.video.info("Catalog marked as refreshed, dirty state cleared")
    }

    // MARK: - Private Methods

    private func loadStoredVersion() {
        storedVersion = Int64(UserDefaults.standard.integer(forKey: versionKey))
        AppLogger.video.debug("Loaded stored catalog version: \(self.storedVersion)")
    }

    private func updateStoredVersion(_ version: Int64) {
        storedVersion = version
        UserDefaults.standard.set(Int(version), forKey: versionKey)
        AppLogger.video.debug("Updated stored catalog version to: \(version)")
    }

    private func updateDirtyState(serverVersion: Int64) {
        latestServerVersion = serverVersion
        let wasDirty = catalogIsDirty
        catalogIsDirty = serverVersion != storedVersion

        if catalogIsDirty && !wasDirty {
            AppLogger.video.info("Catalog is dirty: server version \(serverVersion) differs from stored \(self.storedVersion)")
        } else if !catalogIsDirty && wasDirty {
            AppLogger.video.info("Catalog is no longer dirty")
        }
    }
}

// MARK: - Logger Extension

extension AppLogger {
    static let catalog = OSLog(subsystem: "com.gridstream.ipad", category: "Catalog")
}

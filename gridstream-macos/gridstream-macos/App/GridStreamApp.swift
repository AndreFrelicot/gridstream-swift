//
//  GridStreamApp.swift
//  gridstream-macos
//
//  Menu bar application entry point using MenuBarExtra.
//  Coordinates all services: ServerManager, ConfigurationService, VideoScanner.
//
//  Startup sequence:
//  1. Initialize database
//  2. Load cached videos immediately (before any scan)
//  3. Update videoCatalog and serverManager with cached data
//  4. Start background incremental scan using Task { }
//  5. Scan runs without blocking UI or video browsing
//

import AppKit
import GRDB
import GridStreamAPI
import OSLog
import SwiftUI

/// App delegate to handle launch events and open settings window on startup
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Open settings window on launch with a small delay for SwiftUI to initialize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for window in NSApp.windows {
                if window.identifier?.rawValue.hasPrefix("settings") == true {
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    return
                }
            }
        }
    }
}

@main
struct GridStreamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var serverManager = ServerManager(databaseManager: .shared)
    @State private var configurationService = ConfigurationService(databaseManager: .shared)
    @State private var videoScanner = VideoScanner(databaseManager: .shared)
    @State private var videoCatalog: [VideoItem] = []
    @State private var isScanning = false
    @State private var scanProgress: ScanProgress?
    @State private var currentScanID: UUID?
    @State private var hasPendingScan = false
    @State private var pendingScanIsFull = false
    @State private var hasPerformedStartup = false

    private let logger = Logger(subsystem: "com.gridstream.macos", category: "GridStreamApp")

    init() {
        // Ensure app appears in Dock (not just menu bar)
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                serverManager: serverManager,
                configurationService: configurationService,
                videoCatalog: $videoCatalog,
                isScanning: $isScanning,
                scanProgress: $scanProgress,
                onScanForNew: performIncrementalScan,
                onRescanAll: performFullRescan,
                onClearAllData: performClearAllData,
                onSourceDirectoryDisabled: handleSourceDirectoryDisabled
            )
        } label: {
            MenuBarIconView(
                activity: serverManager.activity,
                hasPerformedStartup: $hasPerformedStartup,
                performStartupSequence: performStartupSequence
            )
        }

        Window("GridStream Settings", id: "settings") {
            SettingsView(
                serverManager: serverManager,
                configurationService: configurationService,
                databaseManager: .shared,
                videoCount: videoCatalog.count,
                isScanning: $isScanning,
                scanProgress: $scanProgress,
                onRescan: performIncrementalScan,
                onSourceDirectoryToggled: handleSourceDirectoryToggle,
                onSourceDirectoryRemoved: handleSourceDirectoryRemoved
            )
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 820, height: 600)
        .commands {
            GridStreamCommands()
        }

        Window("GridStream Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 860, height: 600)
    }

    /// Performs the startup sequence:
    /// 1. Initialize database
    /// 2. Load source directories from database
    /// 3. Load cached videos immediately
    /// 4. Load scrub queue
    /// 5. Initialize background scrub preloader (starts if enabled)
    /// 6. Start background incremental scan
    /// 7. Auto-start server after scan completes
    private func performStartupSequence() async {
        // Step 1: Initialize database
        await initializeDatabaseIfNeeded()

        // Step 2: Load source directories from database (migrates from UserDefaults if needed)
        await configurationService.loadFromDatabase()

        // Step 3: Load cached videos immediately (before any scan)
        await loadCachedVideosOnStartup()

        // Step 3: Initialize background scrub preloader (starts monitoring if enabled)
        _ = BackgroundScrubPreloader.shared

        // Step 5: Start background incremental scan, then auto-start server
        // Use Task { } to ensure scan runs in background without blocking UI
        if !configurationService.sourceDirectories.isEmpty {
            Task {
                await performBackgroundScan(fullRescan: false)
                // Step 6: Auto-start server after scan completes
                await autoStartServer()
                // Scrub queue can be started manually from Settings if needed
                // With client-side frame caching, on-demand generation is preferred
            }
        } else {
            // No source directories, still auto-start server
            await autoStartServer()
        }
    }

    /// Auto-starts the server after startup scan completes.
    private func autoStartServer() async {
        guard !serverManager.isRunning else { return }

        do {
            try await serverManager.start(port: configurationService.serverPort)
            logger.info("Server auto-started on port \(configurationService.serverPort)")
        } catch {
            logger.error("Failed to auto-start server: \(error.localizedDescription)")
        }
    }

    private func initializeDatabaseIfNeeded() async {
        do {
            try await DatabaseManager.shared.initialize()
            logger.info("Database initialized successfully")
        } catch {
            logger.error("Failed to initialize database: \(error.localizedDescription)")
        }
    }

    /// Loads cached videos from the database and updates the videoCatalog immediately.
    /// This enables instant startup - users can browse videos before the scan completes.
    private func loadCachedVideosOnStartup() async {
        let directories = configurationService.sourceDirectories

        guard !directories.isEmpty else {
            logger.info("No source directories configured, skipping cached video load")
            return
        }

        do {
            let cachedVideos = try await videoScanner.loadCachedVideos(sourceDirectories: directories)

            // Update catalog with cached data immediately
            videoCatalog = cachedVideos
            serverManager.updateCatalog(videos: cachedVideos, sourceDirectories: directories)

            logger.info("Loaded \(cachedVideos.count) cached videos on startup")
            AppStateLogger.logCatalogUpdate(count: cachedVideos.count)
        } catch {
            logger.error("Failed to load cached videos: \(error.localizedDescription)")
        }
    }

    /// Performs a background scan without blocking the UI.
    /// - Parameter fullRescan: If true, regenerates all thumbnails
    private func performBackgroundScan(fullRescan: Bool) async {
        let scanID = UUID()
        // Scans are mutually exclusive: a request arriving while one runs is
        // coalesced into a single follow-up scan.
        let shouldStart = await MainActor.run { () -> Bool in
            if isScanning {
                hasPendingScan = true
                pendingScanIsFull = pendingScanIsFull || fullRescan
                return false
            }
            currentScanID = scanID
            isScanning = true
            return true
        }
        guard shouldStart else {
            logger.info("Scan already running; request coalesced into a follow-up scan")
            return
        }

        let scanStartTime = CFAbsoluteTimeGetCurrent()

        // Start access to security-scoped bookmarks. This may refresh stale
        // bookmarks and update folder paths, so read the directories afterwards.
        await MainActor.run {
            configurationService.startAccessingSecurityScopedResources()
        }

        let directories = configurationService.sourceDirectories
        let enabledDirectories = directories.filter { $0.isEnabled }

        AppStateLogger.logRescanStarted(directoryCount: enabledDirectories.count)

        var totalFilesScanned = 0
        var scannedVideos: [VideoItem] = []

        do {
            if fullRescan {
                logger.info("Starting full rescan with thumbnail regeneration")
                scannedVideos = try await videoScanner.fullRescan(
                    directories: directories,
                    progressHandler: { progress in
                        Task { @MainActor in
                            guard self.currentScanID == scanID else { return }
                            self.scanProgress = progress
                            totalFilesScanned = progress.totalFiles
                        }
                    }
                )
            } else {
                scannedVideos = try await videoScanner.scan(
                    directories: directories,
                    progressHandler: { progress in
                        Task { @MainActor in
                            guard self.currentScanID == scanID else { return }
                            self.scanProgress = progress
                            totalFilesScanned = progress.totalFiles
                        }
                    }
                )
            }
        } catch {
            logger.error("Background scan failed: \(error.localizedDescription)")
        }

        let unavailableDirectoryIds = await videoScanner.unavailableDirectoryIds

        // Stop access to security-scoped bookmarks
        await MainActor.run {
            configurationService.stopAccessingSecurityScopedResources()
        }

        let scanDuration = CFAbsoluteTimeGetCurrent() - scanStartTime

        // Log scan completion statistics
        AppStateLogger.logScanCompletion(
            videosFound: scannedVideos.count,
            totalFilesScanned: totalFilesScanned,
            directoryCount: enabledDirectories.count,
            duration: scanDuration
        )

        await MainActor.run {
            guard currentScanID == scanID else {
                logger.info("Ignoring stale scan result")
                return
            }

            videoCatalog = scannedVideos
            serverManager.updateCatalog(videos: scannedVideos, sourceDirectories: directories)
            configurationService.unavailableDirectoryIds = unavailableDirectoryIds

            AppStateLogger.logCatalogUpdate(count: scannedVideos.count)

            // Update last scanned dates (only for folders that could actually be read)
            for directory in directories where directory.isEnabled && !unavailableDirectoryIds.contains(directory.id) {
                configurationService.updateLastScanned(id: directory.id, date: Date())
            }

            isScanning = false
            currentScanID = nil
            scanProgress = nil
        }

        let followUp = await MainActor.run { () -> Bool? in
            guard hasPendingScan else { return nil }
            let isFull = pendingScanIsFull
            hasPendingScan = false
            pendingScanIsFull = false
            return isFull
        }
        if let followUpIsFull = followUp {
            await performBackgroundScan(fullRescan: followUpIsFull)
        }
    }

    /// Incremental scan - only processes new or modified files.
    private func performIncrementalScan() {
        Task {
            await performBackgroundScan(fullRescan: false)
        }
    }

    /// Full rescan - regenerates all thumbnails.
    private func performFullRescan() {
        Task {
            await performBackgroundScan(fullRescan: true)
        }
    }

    /// Clears all data from the database.
    private func performClearAllData() {
        Task {
            do {
                let result = try await DatabaseManager.shared.clearAllData()
                logger.info("Cleared all data: \(result.totalDeleted) records deleted")

                await MainActor.run {
                    videoCatalog = []
                    serverManager.updateCatalog(videos: [], sourceDirectories: configurationService.sourceDirectories)
                    AppStateLogger.logCatalogUpdate(count: 0)
                }
            } catch {
                logger.error("Failed to clear all data: \(error.localizedDescription)")
            }
        }
    }

    /// Handles when a source directory checkbox is toggled.
    /// Disabling only hides the folder's videos from the catalog; their records,
    /// tags, ratings, annotations and captures are kept for when it is re-enabled.
    private func handleSourceDirectoryToggle(directoryId: UUID, isEnabled: Bool) {
        if !isEnabled {
            handleSourceDirectoryDisabled(directoryId: directoryId)
        } else {
            Task {
                await persistEnabledState(directoryId: directoryId, isEnabled: true)
                // When enabled, trigger a rescan to pick up videos from this directory
                await performBackgroundScan(fullRescan: false)
            }
        }
    }

    /// Handles when a source directory is disabled (unchecked): its videos leave
    /// the catalog, but nothing is deleted.
    private func handleSourceDirectoryDisabled(directoryId: UUID) {
        Task {
            await persistEnabledState(directoryId: directoryId, isEnabled: false)

            await MainActor.run {
                videoCatalog.removeAll { $0.sourceDirectoryId == directoryId }
                serverManager.updateCatalog(videos: videoCatalog, sourceDirectories: configurationService.sourceDirectories)

                AppStateLogger.logCatalogUpdate(count: videoCatalog.count)
            }
        }
    }

    /// Stores the folder's enabled flag and bumps the catalog version in one
    /// transaction, so clients refetching after the bump see the new visibility.
    private func persistEnabledState(directoryId: UUID, isEnabled: Bool) async {
        do {
            try await DatabaseManager.shared.writeCatalog { db in
                try db.execute(
                    sql: "UPDATE source_directories SET is_enabled = ?, updated_at = ? WHERE id = ?",
                    arguments: [isEnabled, Date().timeIntervalSince1970, directoryId]
                )
                return .changed
            }
        } catch {
            logger.error("Failed to update source directory state: \(error.localizedDescription)")
        }
    }

    /// Handles the confirmed removal of a source directory: permanently deletes
    /// its videos with all their associated data, then forgets the folder.
    private func handleSourceDirectoryRemoved(directoryId: UUID) {
        Task {
            do {
                let deletedCount = try await DatabaseManager.shared.writeCatalog { db in
                    .changed(try VideoFileRecord.deleteBySourceDirectoryId(directoryId, in: db))
                }

                logger.info("Removed \(deletedCount) videos of removed source directory")
            } catch {
                logger.error("Failed to remove videos of source directory: \(error.localizedDescription)")
            }

            await MainActor.run {
                configurationService.removeDirectory(id: directoryId)
                videoCatalog.removeAll { $0.sourceDirectoryId == directoryId }
                serverManager.updateCatalog(videos: videoCatalog, sourceDirectories: configurationService.sourceDirectories)

                AppStateLogger.logCatalogUpdate(count: videoCatalog.count)
            }
        }
    }
}

/// Main menu additions: Settings… opens the settings window and the Help
/// menu opens the Help window.
private struct GridStreamCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                openWindow(id: "settings")
            }
            .keyboardShortcut(",")
        }

        CommandGroup(replacing: .help) {
            Button("GridStream Help") {
                openWindow(id: "help")
            }
            .keyboardShortcut("?")
        }
    }
}

/// Helper view for the menu bar icon that can access SwiftUI environment
private struct MenuBarIconView: View {
    @Environment(\.openWindow) private var openWindow
    /// Read here rather than in the scene, so its updates redraw only the icon.
    let activity: ConnectionActivity
    @Binding var hasPerformedStartup: Bool
    let performStartupSequence: () async -> Void

    var body: some View {
        // Shows when a device is playing a video
        Image(systemName: activity.streamCount > 0 ? "dot.radiowaves.left.and.right" : "server.rack")
            .task {
                guard !hasPerformedStartup else { return }
                hasPerformedStartup = true
                guard !ProcessInfo.processInfo.isRunningXCTest else { return }
                // Open settings window first
                openWindow(id: "settings")
                // Then run startup sequence (initializes DB, loads cache, starts server)
                await performStartupSequence()
            }
    }
}

private extension ProcessInfo {
    var isRunningXCTest: Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}

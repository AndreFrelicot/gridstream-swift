//
//  MenuBarView.swift
//  gridstream-macos
//
//  Menu bar dropdown content showing server status and controls.
//

import AppKit
import GridStreamAPI
import SwiftUI

struct MenuBarView: View {
    var serverManager: ServerManager
    var configurationService: ConfigurationService
    @Binding var videoCatalog: [VideoItem]
    @Binding var isScanning: Bool
    @Binding var scanProgress: ScanProgress?
    var onScanForNew: () -> Void
    var onRescanAll: () -> Void
    var onClearAllData: () -> Void
    var onSourceDirectoryDisabled: ((UUID) -> Void)?

    @Environment(\.openWindow) private var openWindow

    @State private var showClearConfirmation = false
    @AppStorage(SettingsView.SettingsTab.storageKey) private var settingsPane: SettingsView.SettingsTab = .server

    var body: some View {
        Group {
            statusSection

            Divider()

            controlsSection

            Divider()

            actionsSection

            Divider()

            Button {
                openWindow(id: "help")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("GridStream Help", systemImage: "questionmark.circle")
            }

            Button("Quit GridStream") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .alert("Clear All Data?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All Data", role: .destructive) {
                onClearAllData()
            }
        } message: {
            Text("This will permanently delete all videos, thumbnails, tags, and ratings from the database. This action cannot be undone.")
        }
    }

    private var port: Int {
        serverManager.currentPort ?? configurationService.serverPort
    }

    @ViewBuilder
    private var statusSection: some View {
        Label(
            serverManager.isRunning ? "Server Running on Port \(String(port))" : "Server Stopped",
            systemImage: serverManager.isRunning ? "checkmark.circle.fill" : "stop.circle"
        )

        Text("\(videoCatalog.count) videos in catalog")

        if serverManager.isRunning {
            Button {
                settingsPane = .activity
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label(activitySummary, systemImage: serverManager.activity.streamCount > 0 ? "play.circle.fill" : "ipad.landscape")
            }
        }

        if !configurationService.authEnabled {
            Label("PIN protection off", systemImage: "exclamationmark.triangle.fill")
        } else if let generatedPIN = configurationService.generatedPIN {
            Label("PIN \(generatedPIN)", systemImage: "lock.fill")
        }

        if isScanning {
            scanProgressIndicator
        }
    }

    @ViewBuilder
    private var controlsSection: some View {
        if serverManager.isRunning {
            Button {
                toggleServer()
            } label: {
                Label("Stop Server", systemImage: "stop.fill")
            }
            .disabled(isScanning)
        } else {
            Button {
                toggleServer()
            } label: {
                Label("Start Server", systemImage: "play.fill")
            }
            .disabled(isScanning)
        }

        if serverManager.isRunning && ServerManager.isWebUIBundled && configurationService.webUIEnabled {
            Button {
                NSWorkspace.shared.open(Brand.localNetworkURL(port: port))
            } label: {
                Label("Open Web Interface", systemImage: "globe")
            }
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        Button {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label("Settings…", systemImage: "gearshape")
        }
        .keyboardShortcut(",")

        Divider()

        Button {
            onScanForNew()
        } label: {
            Label("Scan for New Videos", systemImage: "arrow.clockwise")
        }
        .disabled(isScanning || configurationService.sourceDirectories.isEmpty)

        Button {
            onRescanAll()
        } label: {
            Label("Rescan All Videos", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(isScanning || configurationService.sourceDirectories.isEmpty)

        Divider()

        Button {
            showClearConfirmation = true
        } label: {
            Label("Clear All Data…", systemImage: "trash")
        }
        .disabled(isScanning)
    }

    /// "2 devices connected · 3 videos playing · 12 MB/s", or that none is.
    private var activitySummary: String {
        let activity = serverManager.activity
        guard !activity.clients.isEmpty else {
            return String(localized: "No device connected")
        }
        var parts = [String(localized: "\(activity.clients.count) devices connected")]
        if activity.streamCount > 0 {
            parts.append(String(localized: "\(activity.streamCount) videos playing"))
            parts.append(ActivityFormat.rate(activity.bytesPerSecond))
        }
        return parts.joined(separator: " · ")
    }

    private var scanProgressIndicator: some View {
        Group {
            if let progress = scanProgress, progress.totalFiles > 0 {
                Label("Scanning… \(progress.filesScanned)/\(progress.totalFiles)", systemImage: "hourglass")
            } else {
                Label("Scanning…", systemImage: "hourglass")
            }
        }
        .accessibilityIdentifier("scanProgressIndicator")
    }

    private func toggleServer() {
        Task {
            if serverManager.isRunning {
                do {
                    try await serverManager.stop()
                } catch {
                    // Server stop errors are logged by ServerManager
                }
            } else {
                do {
                    try await serverManager.start(port: configurationService.serverPort)
                } catch {
                    // Server start errors are logged by ServerManager
                }
            }
        }
    }
}

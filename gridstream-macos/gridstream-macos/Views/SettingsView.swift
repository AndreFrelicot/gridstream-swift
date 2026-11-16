//
//  SettingsView.swift
//  gridstream-macos
//
//  Settings window: a sidebar of panes (server, folders, storage, web,
//  security) laid out like System Settings.
//

import AppKit
import OSLog
import SwiftUI

struct SettingsView: View {
    var serverManager: ServerManager
    var configurationService: ConfigurationService
    let databaseManager: DatabaseManager
    var videoCount: Int
    @Binding var isScanning: Bool
    @Binding var scanProgress: ScanProgress?
    var onRescan: () -> Void
    var onSourceDirectoryToggled: ((UUID, Bool) -> Void)?
    var onSourceDirectoryRemoved: ((UUID) -> Void)?

    @State private var portText: String = ""
    @State private var pinText: String = ""
    @State private var confirmPINText: String = ""
    @State private var ttlText: String = ""
    @State private var showingPortError = false
    @State private var showingPinError = false
    @State private var pinMessage: String?
    /// Remembered, and set by the menu bar menu to open a pane.
    @AppStorage(SettingsTab.storageKey) private var selectedTab: SettingsTab = .server
    @State private var missingVideoCount = 0
    @State private var showPurgeMissingConfirmation = false
    @State private var directoryPendingRemoval: SourceDirectory?
    @State private var addDirectoryError: String?

    @Environment(\.openWindow) private var openWindow

    enum SettingsTab: String, CaseIterable, Identifiable {
        case server
        case activity
        case directories
        case storage
        case web
        case security

        var id: Self { self }

        static let storageKey = "settingsPane"

        var title: LocalizedStringKey {
            switch self {
            case .server: "Server"
            case .activity: "Activity"
            case .directories: "Folders"
            case .storage: "Storage"
            case .web: "Web"
            case .security: "Security"
            }
        }

        /// The Help topic that explains this pane.
        var helpTopicID: HelpTopic.ID {
            switch self {
            case .server: HelpTopic.server.id
            case .activity: HelpTopic.activity.id
            case .directories: HelpTopic.folders.id
            case .storage: HelpTopic.storage.id
            case .web: HelpTopic.web.id
            case .security: HelpTopic.security.id
            }
        }

        var systemImage: String {
            switch self {
            case .server: "server.rack"
            case .activity: "dot.radiowaves.left.and.right"
            case .directories: "folder.fill"
            case .storage: "internaldrive.fill"
            case .web: "globe"
            case .security: "lock.fill"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 760, minHeight: 540)
        .onAppear {
            portText = String(configurationService.serverPort)
            ttlText = String(configurationService.sessionTTLDays)
            refreshMissingVideoCount()
        }
        .onChange(of: isScanning) { _, scanning in
            if !scanning {
                refreshMissingVideoCount()
            }
        }
        .alert("Purge Missing Videos?", isPresented: $showPurgeMissingConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Purge \(missingVideoCount) Videos", role: .destructive) {
                purgeMissingVideos()
            }
        } message: {
            Text("\(missingVideoCount) videos are no longer found on disk. Purging permanently deletes their tags, ratings, play statistics, annotations, time ranges, list memberships and frame captures. If a file comes back later it will be added as a new video. This cannot be undone.")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: Binding<SettingsTab?>(
            get: { selectedTab },
            set: { if let tab = $0 { selectedTab = tab } }
        )) {
            HStack(spacing: 10) {
                AppIconImage(size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("GridStream Server")
                        .font(.headline)
                    ServerStatusBadge(isRunning: serverManager.isRunning)
                }
            }
            .padding(.vertical, 6)
            .selectionDisabled()

            Section {
                ForEach(SettingsTab.allCases) { tab in
                    NavigationLink(value: tab) {
                        Label {
                            Text(tab.title)
                        } icon: {
                            BrandSymbol(systemImage: tab.systemImage, size: 22)
                        }
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
    }

    @ViewBuilder
    private var detail: some View {
        let tab = selectedTab
        Group {
            switch tab {
            case .server:
                serverContent
            case .activity:
                ActivityView(serverManager: serverManager)
            case .directories:
                directoriesContent
            case .storage:
                StorageSettingsView(databaseManager: databaseManager)
                    .environment(configurationService)
            case .web:
                WebUISettingsView(
                    serverManager: serverManager,
                    configurationService: configurationService,
                    onStartServer: toggleServer
                )
            case .security:
                securityContent
            }
        }
        .navigationTitle(Text(tab.title))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HelpLink {
                    HelpRouter.shared.show(topicID: tab.helpTopicID)
                    openWindow(id: "help")
                }
                .help("Help about \(Text(tab.title))")
            }
        }
    }

    // MARK: - Server

    private var serverAddress: URL {
        Brand.localNetworkURL(port: serverManager.currentPort ?? configurationService.serverPort)
    }

    private var serverContent: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    AppIconImage(size: 64)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("GridStream Server")
                            .font(.title2.weight(.semibold))
                        if serverManager.isRunning, let port = serverManager.currentPort {
                            Text("Streaming your library on port \(String(port))")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("The server is stopped. iPads and browsers cannot connect.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if serverManager.isRunning {
                        Button("Stop Server") { toggleServer() }
                            .controlSize(.large)
                            .disabled(isScanning)
                    } else {
                        Button("Start Server") { toggleServer() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(isScanning)
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                HStack(spacing: 24) {
                    StatTile(title: "Videos", value: "\(videoCount)", systemImage: "film.stack")
                    StatTile(
                        title: "Folders",
                        value: "\(configurationService.sourceDirectories.filter(\.isEnabled).count)",
                        systemImage: "folder"
                    )
                    StatTile(
                        title: "PIN",
                        value: configurationService.authEnabled ? String(localized: "On") : String(localized: "Off"),
                        systemImage: configurationService.authEnabled ? "lock.fill" : "lock.open"
                    )
                }
                .padding(.vertical, 4)
            }

            Section {
                LabeledContent("Address") {
                    HStack(spacing: 6) {
                        Text(serverAddress.absoluteString)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        CopyButton(text: serverAddress.absoluteString)
                    }
                }

                LabeledContent("PIN") {
                    if !configurationService.authEnabled {
                        Label("Off — anyone on your network can connect", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else if let generatedPIN = configurationService.generatedPIN {
                        Text(generatedPIN)
                            .font(.system(.title3, design: .monospaced).weight(.semibold))
                            .textSelection(.enabled)
                    } else {
                        Text("Your own PIN")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Connect an iPad or a Browser")
            } footer: {
                Text("On the iPad, GridStream finds this Mac automatically on the local network. Enter the PIN when asked.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Port") {
                    HStack(spacing: 6) {
                        if showingPortError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                                .help("Port must be between 1024 and 65535")
                        }
                        TextField("Port", text: $portText)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .onSubmit {
                                updatePort()
                            }
                            .onChange(of: portText) { _, newValue in
                                let filtered = newValue.filter { $0.isNumber }
                                if filtered != newValue {
                                    portText = filtered
                                }
                            }
                            .disabled(serverManager.isRunning)
                    }
                }
            } header: {
                Text("Network")
            } footer: {
                Text(serverManager.isRunning ? "Stop the server to change its port." : "Press Return to save. Use a port between 1024 and 65535.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Folders

    private func refreshMissingVideoCount() {
        Task {
            let count = (try? await databaseManager.read { db in
                try VideoFileRecord.countMissing(in: db)
            }) ?? 0
            missingVideoCount = count
        }
    }

    private func purgeMissingVideos() {
        Task {
            do {
                try await databaseManager.writeCatalog { db in
                    try VideoFileRecord.purgeMissing(in: db) > 0 ? .changed : .unchanged
                }
            } catch {
                Logger(subsystem: "com.gridstream.macos", category: "SettingsView")
                    .error("Failed to purge missing videos: \(error.localizedDescription)")
            }
            refreshMissingVideoCount()
        }
    }

    private var directoriesContent: some View {
        Form {
            Section {
                if configurationService.sourceDirectories.isEmpty {
                    emptyStateView
                } else {
                    ForEach(configurationService.sourceDirectories) { directory in
                        SourceDirectoryRow(
                            directory: directory,
                            isUnavailable: configurationService.unavailableDirectoryIds.contains(directory.id),
                            onToggle: {
                                let wasEnabled = directory.isEnabled
                                configurationService.toggleDirectory(id: directory.id)
                                // Notify parent about the toggle with the new state (inverted)
                                onSourceDirectoryToggled?(directory.id, !wasEnabled)
                            },
                            onRemove: {
                                directoryPendingRemoval = directory
                            }
                        )
                    }
                }

                HStack {
                    Button {
                        addDirectory()
                    } label: {
                        Label("Add Folder…", systemImage: "plus")
                    }

                    Spacer()

                    if isScanning {
                        scanProgressIndicator
                    } else {
                        Button {
                            onRescan()
                        } label: {
                            Label("Scan for Changes", systemImage: "arrow.clockwise")
                        }
                        .disabled(configurationService.sourceDirectories.isEmpty)
                    }
                }
            } header: {
                Text("Source Folders")
            } footer: {
                Text("GridStream serves the .mp4, .m4v and .mov files in these folders and their subfolders. Right-click a folder to show it in Finder.")
                    .foregroundStyle(.secondary)
            }

            if missingVideoCount > 0 {
                Section {
                    HStack {
                        Label(
                            "\(missingVideoCount) videos are no longer found on disk",
                            systemImage: "questionmark.folder"
                        )
                        Spacer()
                        Button("Purge…", role: .destructive) {
                            showPurgeMissingConfirmation = true
                        }
                        .disabled(isScanning)
                        .help("Permanently delete videos that are no longer found on disk")
                    }
                } header: {
                    Text("Missing Videos")
                }
            }
        }
        .formStyle(.grouped)
        .alert(
            "Cannot Add Folder",
            isPresented: Binding(
                get: { addDirectoryError != nil },
                set: { if !$0 { addDirectoryError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(addDirectoryError ?? "")
        }
        .alert(
            "Remove Source Folder?",
            isPresented: Binding(
                get: { directoryPendingRemoval != nil },
                set: { if !$0 { directoryPendingRemoval = nil } }
            ),
            presenting: directoryPendingRemoval
        ) { directory in
            Button("Cancel", role: .cancel) {}
            Button("Remove and Delete Data", role: .destructive) {
                onSourceDirectoryRemoved?(directory.id)
            }
        } message: { directory in
            Text("Removing “\((directory.path as NSString).lastPathComponent)” permanently deletes all of its videos from the GridStream library, together with their tags, ratings, play statistics, annotations, time ranges, list memberships and frame captures. The video files on disk are not touched. To keep this data, turn the folder off instead.")
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            BrandSymbol(systemImage: "folder.badge.plus", size: 48)

            Text("No source folders yet")
                .font(.headline)

            Text("Add a folder that contains your videos. They stay where they are; nothing is copied.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var scanProgressIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            if let progress = scanProgress, progress.totalFiles > 0 {
                Text("Scanning for changes... \(progress.filesScanned)/\(progress.totalFiles)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text("Scanning for changes...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("scanProgressIndicator")
    }

    // MARK: - Security

    private var securityContent: some View {
        Form {
            Section {
                Toggle(
                    "Require a PIN",
                    isOn: Binding(
                        get: { configurationService.authEnabled },
                        set: { newValue in
                            if !configurationService.setAuthEnabled(newValue) {
                                showingPinError = true
                                pinMessage = String(localized: "Set a 6 to 12 digit PIN before enabling protection.")
                            } else {
                                showingPinError = false
                                pinMessage = nil
                            }
                        }
                    )
                )

                if !configurationService.authEnabled {
                    Label(
                        "PIN protection is off. Anyone on your network can browse, stream and change your library.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
            } header: {
                Text("PIN Protection")
            } footer: {
                Text("Use a single PIN to unlock web and iPad clients. Changing the PIN revokes existing sessions.")
                    .foregroundStyle(.secondary)
            }

            if let generatedPIN = configurationService.generatedPIN {
                Section {
                    LabeledContent("Generated PIN") {
                        Text(generatedPIN)
                            .font(.system(.title2, design: .monospaced).weight(.semibold))
                            .textSelection(.enabled)
                    }
                } footer: {
                    Text("Enter this PIN on the iPad or in the web app. Set your own PIN below to replace it.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                SecureField("PIN", text: $pinText)
                SecureField("Confirm PIN", text: $confirmPINText)

                HStack {
                    if let pinMessage {
                        Label(pinMessage, systemImage: showingPinError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(showingPinError ? .red : .green)
                    }
                    Spacer()
                    Button(configurationService.pinConfigured ? "Update PIN" : "Save PIN") {
                        savePIN()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pinText.isEmpty)
                }
            } header: {
                Text(configurationService.pinConfigured ? "Change PIN" : "Set PIN")
            }

            Section {
                LabeledContent("Stay signed in for") {
                    HStack(spacing: 6) {
                        TextField("Days", text: $ttlText)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .onSubmit {
                                saveTTL()
                            }
                            .onChange(of: ttlText) { _, newValue in
                                let filtered = newValue.filter { $0.isNumber }
                                if filtered != newValue {
                                    ttlText = filtered
                                }
                            }
                        Text("days")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("Sign out every iPad and browser")
                    Spacer()
                    Button("Revoke All Sessions") {
                        configurationService.revokeAllSessions()
                        pinMessage = String(localized: "All sessions revoked.")
                        showingPinError = false
                    }
                    .disabled(!configurationService.pinConfigured)
                }
            } header: {
                Text("Sessions")
            } footer: {
                Text("Press Return to save the duration.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Actions

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

    private func addDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = String(localized: "Select a folder containing video files")
        panel.prompt = String(localized: "Add Folder")

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try configurationService.addDirectoryWithBookmark(url: url)
            } catch {
                addDirectoryError = error.localizedDescription
            }
        }
    }

    private func updatePort() {
        guard let port = Int(portText),
              port >= 1024,
              port <= 65535 else {
            showingPortError = true
            portText = String(configurationService.serverPort)
            return
        }

        showingPortError = false
        configurationService.serverPort = port
    }

    private func savePIN() {
        let normalizedPIN = ServerPINSecurity.normalize(pin: pinText)
        let normalizedConfirmation = ServerPINSecurity.normalize(pin: confirmPINText)

        guard normalizedPIN == pinText, normalizedConfirmation == confirmPINText else {
            showingPinError = true
            pinMessage = String(localized: "PIN must contain digits only.")
            return
        }

        guard normalizedPIN == normalizedConfirmation else {
            showingPinError = true
            pinMessage = String(localized: "PIN confirmation does not match.")
            return
        }

        do {
            try configurationService.setPIN(normalizedPIN)
            pinText = ""
            confirmPINText = ""
            ttlText = String(configurationService.sessionTTLDays)
            showingPinError = false
            pinMessage = String(localized: "PIN saved. Existing sessions were revoked.")
        } catch {
            showingPinError = true
            pinMessage = error.localizedDescription
        }
    }

    private func saveTTL() {
        guard let days = Int(ttlText), days > 0 else {
            showingPinError = true
            pinMessage = String(localized: "Session TTL must be a positive number of days.")
            ttlText = String(configurationService.sessionTTLDays)
            return
        }

        configurationService.updateSessionTTLDays(days)
        ttlText = String(configurationService.sessionTTLDays)
        showingPinError = false
        pinMessage = String(localized: "Session duration updated.")
    }
}

/// A borderless button that copies a string to the clipboard and briefly
/// shows a checkmark.
struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .help("Copy")
    }
}

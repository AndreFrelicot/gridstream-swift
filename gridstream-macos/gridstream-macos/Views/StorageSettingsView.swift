//
//  StorageSettingsView.swift
//  gridstream-macos
//

import AppKit
import Combine
import Foundation
import GRDB
import OSLog
import SwiftUI

struct StorageSettingsView: View {
    let databaseManager: DatabaseManager
    @Environment(ConfigurationService.self) private var configurationService
    @State private var frameCount: Int = 0
    @State private var videoCount: Int = 0
    @State private var totalVideoCount: Int = 0
    @State private var databaseSize: String = "–"
    @State private var isLoading: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var deleteResult: String? = nil
    @State private var deleteFailed = false
    @State private var preloader = BackgroundScrubPreloader.shared
    @State private var isVisible: Bool = false
    @State private var showRestartNotice: Bool = false
    @State private var pendingDataDirectory: URL? = nil

    private let logger = Logger(subsystem: "com.gridstream.macos", category: "StorageSettingsView")
    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            dataDirectorySection
            statisticsSection
            backgroundGenerationSection
            actionSection
        }
        .formStyle(.grouped)
        .onAppear {
            isVisible = true
            loadDatabaseSize()
            loadCounts()
        }
        .onDisappear {
            isVisible = false
        }
        .onReceive(refreshTimer) { _ in
            guard isVisible else { return }
            loadDatabaseSize()
            if !isLoading {
                loadCounts()
            }
        }
        .alert(
            "Move the Database?",
            isPresented: Binding(
                get: { pendingDataDirectory != nil },
                set: { if !$0 { pendingDataDirectory = nil } }
            ),
            presenting: pendingDataDirectory
        ) { url in
            Button("Move Database") {
                configurationService.changeDataDirectory(to: url, moveDatabase: true)
                showRestartNotice = true
            }
            Button("Start Empty") {
                configurationService.changeDataDirectory(to: url, moveDatabase: false)
                showRestartNotice = true
            }
            Button("Cancel", role: .cancel) {}
        } message: { url in
            Text("On the next launch GridStream can move its database (videos, tags, ratings, annotations, lists and captures) to \(url.path). If that folder already contains a GridStream database, it is used as is and nothing is moved. \"Start Empty\" leaves the current database where it is.")
        }
        .alert("Delete All Scrub Data?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                performDelete()
            }
        } message: {
            Text("This will permanently delete all \(frameCount) cached scrub frames. This action cannot be undone.")
        }
    }

    private var dataDirectorySection: some View {
        Section {
            LabeledContent("Location") {
                Text((configurationService.dataDirectory.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(configurationService.dataDirectory.path)
            }

            HStack {
                if showRestartNotice {
                    Label("Restart the app for the new data directory to take effect.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                Spacer()

                Button("Show in Finder") {
                    openDatabaseInFinder()
                }

                if configurationService.dataDirectory != ConfigurationService.defaultDataDirectory {
                    Button("Reset") {
                        pendingDataDirectory = ConfigurationService.defaultDataDirectory
                    }
                }

                Button("Change…") {
                    chooseDataDirectory()
                }
            }
        } header: {
            Text("Data Directory")
        } footer: {
            Text("Where GridStream keeps its database: tags, ratings, lists, annotations, captures and scrub previews. Your video files are never moved.")
                .foregroundStyle(.secondary)
        }
    }

    private func chooseDataDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = String(localized: "Select a directory for GridStream data (database and scrub files)")
        panel.prompt = String(localized: "Select")
        panel.directoryURL = configurationService.dataDirectory

        if panel.runModal() == .OK, let url = panel.url,
           url.standardizedFileURL != configurationService.dataDirectory.standardizedFileURL {
            pendingDataDirectory = url
        }
    }

    private var statisticsSection: some View {
        Section {
            HStack(spacing: 24) {
                StatTile(title: "Database Size", value: databaseSize, systemImage: "cylinder.split.1x2")
                StatTile(title: "Scrub Frames", value: frameCount.formatted(), systemImage: "photo.stack")
                StatTile(title: "Videos Processed", value: videoCount.formatted(), systemImage: "checkmark.circle")
            }
            .padding(.vertical, 4)

            if totalVideoCount > 0 {
                let progress = Double(videoCount) / Double(totalVideoCount)
                let remaining = totalVideoCount - videoCount

                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)

                    HStack {
                        Text("\(videoCount) / \(totalVideoCount) videos processed")
                        if remaining > 0 {
                            Text("· \(remaining) remaining")
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(progress.formatted(.percent.precision(.fractionLength(0))))
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            } else {
                Text("No videos in library")
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Scrub Previews")
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    loadDatabaseSize()
                    loadCounts()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isLoading)
                .help("Refresh statistics")
            }
        } footer: {
            Text("Scrub previews are the small frames the iPad shows while you drag along a video's timeline.")
                .foregroundStyle(.secondary)
        }
    }

    private var backgroundGenerationSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { preloader.isEnabled },
                set: { preloader.isEnabled = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Generate scrub previews in the background")
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 7, height: 7)
                        Text(preloader.status.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Picker("Workers", selection: Binding(
                get: { preloader.maxConcurrentWorkers },
                set: { preloader.maxConcurrentWorkers = $0 }
            )) {
                ForEach(1...4, id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }
            .pickerStyle(.segmented)

            if preloader.status == .running, !preloader.workers.isEmpty {
                ForEach(preloader.workers) { worker in
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(worker.videoName ?? String(localized: "Waiting…"))
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            if worker.totalFrames > 0 {
                                Text("\(worker.currentFrame)/\(worker.totalFrames) frames")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }

                        Spacer()
                    }
                }
            }
        } header: {
            Text("Background Generation")
        } footer: {
            Text("Runs only while no iPad or browser is connected.")
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch preloader.status {
        case .idle:
            return .gray
        case .running:
            return .green
        case .paused:
            return .orange
        case .disabled:
            return .gray
        }
    }

    private var actionSection: some View {
        Section {
            HStack {
                if let result = deleteResult {
                    Text(result)
                        .font(.callout)
                        .foregroundStyle(deleteFailed ? .red : .green)
                } else {
                    Text("Previews are generated again when needed.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Delete All Scrub Data…", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .disabled(isLoading || (frameCount == 0 && videoCount == 0))
            }
        }
    }

    /// Reads only the database file size (a filesystem stat) and updates it independently
    /// of the slow counts, so Database Size appears immediately.
    private func loadDatabaseSize() {
        Task {
            let dbPath = await databaseManager.databasePath
            let size = getFormattedFileSize(at: dbPath)
            await MainActor.run {
                self.databaseSize = size
            }
        }
    }

    /// Loads the scrub-frame / video counts. After denormalizing `scrub_frame_count` onto
    /// `video_files`, these are O(#videos) index reads instead of full scans of `scrub_frames`.
    private func loadCounts() {
        isLoading = true
        deleteResult = nil

        Task {
            do {
                logger.info("Loading storage statistics...")

                let result: (Int, Int, Int) = try await databaseManager.read { db in
                    let frameCount = try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(scrub_frame_count), 0) FROM video_files") ?? 0
                    let processedVideoCount = try Int.fetchOne(db, sql: """
                        SELECT COUNT(*) FROM video_files
                        WHERE scrub_frame_count >= CAST(duration / 2.0 AS INTEGER) AND duration > 0
                        """) ?? 0
                    let totalVideoCount = try VideoFileRecord.fetchCount(db)
                    return (frameCount, processedVideoCount, totalVideoCount)
                }

                logger.info("Statistics loaded: \(result.0) frames, \(result.1) processed videos, \(result.2) total videos")

                await MainActor.run {
                    self.frameCount = result.0
                    self.videoCount = result.1
                    self.totalVideoCount = result.2
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.logger.error("Failed to load storage statistics: \(error.localizedDescription)")
                    self.isLoading = false
                }
            }
        }
    }

    private func getFormattedFileSize(at url: URL) -> String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            }
        } catch {
            logger.error("Failed to get database file size: \(error.localizedDescription)")
        }
        return "–"
    }

    private func openDatabaseInFinder() {
        Task {
            let dbPath = await databaseManager.databasePath
            NSWorkspace.shared.selectFile(dbPath.path, inFileViewerRootedAtPath: dbPath.deletingLastPathComponent().path)
        }
    }

    private func performDelete() {
        isLoading = true
        deleteResult = nil

        Task {
            do {
                let result = try await ScrubFrameCache.shared.clearAllScrubData()

                await MainActor.run {
                    self.frameCount = 0
                    self.videoCount = 0
                    self.deleteResult = String(localized: "Deleted \(result.framesDeleted) cached scrub frames")
                    self.deleteFailed = false
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.logger.error("Failed to delete scrub data: \(error.localizedDescription)")
                    self.deleteResult = String(localized: "Error: \(error.localizedDescription)")
                    self.deleteFailed = true
                    self.isLoading = false
                }
            }
        }
    }
}

#Preview {
    StorageSettingsView(databaseManager: .shared)
        .environment(ConfigurationService(databaseManager: .shared))
        .frame(width: 500, height: 400)
}

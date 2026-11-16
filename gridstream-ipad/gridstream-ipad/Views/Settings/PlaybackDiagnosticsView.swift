//
//  PlaybackDiagnosticsView.swift
//  gridstream-ipad
//

import SwiftUI
import UIKit

struct PlaybackDiagnosticsView: View {
    private enum Filter: String, CaseIterable {
        case incidents = "Incidents"
        case all = "All Events"

        var title: LocalizedStringResource {
            switch self {
            case .incidents: return "Incidents"
            case .all: return "All Events"
            }
        }
    }

    @State private var events: [PlaybackDiagnosticEvent] = []
    @State private var metadata = PlaybackDiagnosticsMetadata(
        eventCount: 0,
        fileSize: 0,
        oldestEventDate: nil,
        newestEventDate: nil
    )
    @State private var selectedFilter: Filter = .incidents
    @State private var exportURL: URL?
    @State private var isLoading = true
    @State private var showingClearConfirmation = false
    @State private var copiedToClipboard = false

    private let store = PlaybackDiagnosticsStore.shared

    private var filteredEvents: [PlaybackDiagnosticEvent] {
        switch selectedFilter {
        case .incidents:
            return events.filter(\.isIncident)
        case .all:
            return events
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader
                .padding()

            Divider()

            Picker("Diagnostic filter", selection: $selectedFilter) {
                ForEach(Filter.allCases, id: \.self) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            if isLoading {
                Spacer()
                ProgressView("Loading diagnostics...")
                Spacer()
            } else if filteredEvents.isEmpty {
                Spacer()
                ContentUnavailableView(
                    selectedFilter == .incidents ? "No Playback Incidents" : "No Playback Events",
                    systemImage: "waveform.path.ecg",
                    description: Text("Playback diagnostics are retained for 7 days, up to 5 MB.")
                )
                Spacer()
            } else {
                List(filteredEvents) { event in
                    PlaybackDiagnosticEventRow(event: event)
                }
                .listStyle(.plain)
            }
        }
        .task {
            await reload()
        }
        .confirmationDialog(
            "Clear playback diagnostics?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Diagnostics", role: .destructive) {
                Task {
                    await store.clear()
                    await reload()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the diagnostic log stored on this iPad.")
        }
        .overlay(alignment: .bottom) {
            if copiedToClipboard {
                Label("Diagnostics copied", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Playback Diagnostics")
                        .font(.headline)
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await reload() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                Button {
                    copyDiagnostics()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(metadata.eventCount == 0)

                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer()

                Button(role: .destructive) {
                    showingClearConfirmation = true
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(metadata.eventCount == 0)
            }
        }
    }

    private var summaryText: String {
        let size = ByteCountFormatter.string(fromByteCount: metadata.fileSize, countStyle: .file)
        guard let oldestDate = metadata.oldestEventDate else {
            return String(localized: "No stored events · \(size)")
        }
        return String(localized: "\(metadata.eventCount) events since \(oldestDate.formatted(date: .abbreviated, time: .shortened)) · \(size)")
    }

    private func reload() async {
        isLoading = true
        async let loadedEvents = store.events()
        async let loadedMetadata = store.metadata()
        async let loadedExportURL = store.exportURL()
        events = await loadedEvents
        metadata = await loadedMetadata
        exportURL = await loadedExportURL
        isLoading = false
    }

    private func copyDiagnostics() {
        Task {
            let text = await store.exportText()
            UIPasteboard.general.string = text
            withAnimation {
                copiedToClipboard = true
            }
            try? await Task.sleep(for: .seconds(2))
            withAnimation {
                copiedToClipboard = false
            }
        }
    }
}

private struct PlaybackDiagnosticEventRow: View {
    let event: PlaybackDiagnosticEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(eventTitle, systemImage: iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tintColor)

                Spacer()

                Text(event.timestamp.formatted(date: .abbreviated, time: .standard))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let message = event.message, !message.isEmpty {
                Text(message)
                    .font(.caption)
            }

            Text(contextLine)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Text(stateLine)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)

            if let networkLine {
                Text(networkLine)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var eventTitle: String {
        event.name
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private var iconName: String {
        switch event.level {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }

    private var tintColor: Color {
        switch event.level {
        case .info: return .secondary
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var contextLine: String {
        let fileID = event.snapshot.videoFileID ?? "unknown video"
        let tile = event.snapshot.tileIndex.map { "tile \($0 + 1)" } ?? "no tile"
        return "\(fileID) · \(tile) · \(event.snapshot.displayContext) · \(formatTime(event.snapshot.playbackTime)) / \(formatTime(event.snapshot.duration))"
    }

    private var stateLine: String {
        var parts = [
            "state=\(event.snapshot.timeControlStatus)",
            "rate=\(String(format: "%.2f", event.snapshot.rate))",
            "intent=\(event.snapshot.wantsToPlay ? "play" : "pause")",
            "buffer=\(String(format: "%.2fs", event.snapshot.bufferedAhead))",
            "players=\(event.snapshot.activePlayerCount)",
            "thermal=\(event.snapshot.thermalState)"
        ]
        if let waitingReason = event.snapshot.waitingReason {
            parts.append("wait=\(waitingReason)")
        }
        return parts.joined(separator: " · ")
    }

    private var networkLine: String? {
        var parts: [String] = []
        if let bitrate = event.snapshot.observedBitrate, bitrate >= 0 {
            parts.append("observed=\(formatBitrate(bitrate))")
        }
        if let average = event.snapshot.averageVideoBitrate, average >= 0 {
            parts.append("video=\(formatBitrate(average))")
        }
        if let stalls = event.snapshot.numberOfStalls, stalls >= 0 {
            parts.append("stalls=\(stalls)")
        }
        if let droppedFrames = event.snapshot.droppedVideoFrames, droppedFrames >= 0 {
            parts.append("dropped=\(droppedFrames)")
        }
        if let errorDescription = event.snapshot.errorDescription {
            parts.append("error=\(errorDescription)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let totalSeconds = Int(seconds)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func formatBitrate(_ bitsPerSecond: Double) -> String {
        String(format: "%.1fMbps", bitsPerSecond / 1_000_000)
    }
}

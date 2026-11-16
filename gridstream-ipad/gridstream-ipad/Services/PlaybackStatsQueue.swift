//
//  PlaybackStatsQueue.swift
//  gridstream-ipad
//
//  App-wide owner of playback statistics reports. Every player hands its
//  reports here instead of sending them itself, so a report is stored once,
//  sent once, and only removed once the server has accepted it.
//

import Foundation
import OSLog
import UIKit

/// Single app-wide queue for play-count / view-time reports.
///
/// The queue is the only owner of pending reports: they live in one list that
/// is mirrored to disk after every change, so a report is never held both in
/// memory and on disk under two different owners and is never merged with a
/// copy of itself. Main-actor isolated, so all state changes are serialized;
/// network sends suspend without blocking the main thread.
final class PlaybackStatsQueue {
    typealias Reporter = VideoPlayerState.PlaybackStatsReporter

    struct Report: Codable, Equatable {
        let id: UUID
        let fileId: String
        let incrementPlayCount: Bool
        let addViewTime: Int
    }

    static let shared = PlaybackStatsQueue()

    private static let legacyStorageKey = "GridStreamDeferredPlaybackStatsReports"

    private let defaults: UserDefaults
    private let storageKey: String
    private var pending: [Report]
    private var reporter: Reporter?
    private var isFlushing = false
    private var backgroundTask: PlaybackStatsBackgroundTask?

    init(defaults: UserDefaults = .standard, storageKey: String = "GridStreamPlaybackStatsQueue") {
        self.defaults = defaults
        self.storageKey = storageKey
        self.pending = Self.load(from: defaults, key: storageKey)
        migrateLegacyReports()
    }

    /// Reports not yet accepted by the server, oldest first.
    var pendingReports: [Report] { pending }

    /// Adds a report and tries to send everything pending with `reporter`.
    func enqueue(
        fileId: String,
        incrementPlayCount: Bool,
        addViewTime: Int,
        reporter: Reporter?,
        requireBackgroundTask: Bool = false
    ) async {
        guard incrementPlayCount || addViewTime > 0 else { return }
        pending.append(Report(
            id: UUID(),
            fileId: fileId,
            incrementPlayCount: incrementPlayCount,
            addViewTime: addViewTime
        ))
        save()
        if let reporter {
            self.reporter = reporter
        }
        await flush(requireBackgroundTask: requireBackgroundTask)
    }

    /// Sets the reporter used for reports (e.g. ones restored from disk) and
    /// sends whatever is pending.
    func setReporter(_ reporter: @escaping Reporter) async {
        self.reporter = reporter
        await flush()
    }

    /// Sends every pending report once. A report that fails stays queued for
    /// the next flush; a report that succeeds is removed before anything else
    /// can see it again, so it is never sent twice.
    func flush(requireBackgroundTask: Bool = false) async {
        if backgroundTask == nil {
            backgroundTask = PlaybackStatsBackgroundTask.beginIfNeeded(force: requireBackgroundTask)
        }
        // A flush already in progress picks up reports added meanwhile.
        guard !isFlushing else { return }
        isFlushing = true
        defer {
            isFlushing = false
            backgroundTask?.end()
            backgroundTask = nil
        }

        var attempted = Set<UUID>()
        while let reporter, let report = pending.first(where: { !attempted.contains($0.id) }) {
            attempted.insert(report.id)
            do {
                try await reporter(report.fileId, report.incrementPlayCount, report.addViewTime)
                pending.removeAll { $0.id == report.id }
                save()
            } catch {
                AppLogger.playback.error("Failed to report playback stats for \(report.fileId): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Persistence

    private static func load(from defaults: UserDefaults, key: String) -> [Report] {
        guard let data = defaults.data(forKey: key),
              let reports = try? JSONDecoder().decode([Report].self, from: data) else {
            return []
        }
        return reports
    }

    private func save() {
        guard !pending.isEmpty else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        if let data = try? JSONEncoder().encode(pending) {
            defaults.set(data, forKey: storageKey)
        }
    }

    /// Imports reports left by the previous per-player store, once.
    private func migrateLegacyReports() {
        struct LegacyReport: Decodable {
            var incrementPlayCount: Bool
            var addViewTime: Int
        }
        guard let data = defaults.data(forKey: Self.legacyStorageKey) else { return }
        defaults.removeObject(forKey: Self.legacyStorageKey)
        guard let legacy = try? JSONDecoder().decode([String: LegacyReport].self, from: data) else { return }
        for (fileId, report) in legacy.sorted(by: { $0.key < $1.key })
        where report.incrementPlayCount || report.addViewTime > 0 {
            pending.append(Report(
                id: UUID(),
                fileId: fileId,
                incrementPlayCount: report.incrementPlayCount,
                addViewTime: report.addViewTime
            ))
        }
        save()
    }
}

/// Keeps the app alive long enough to deliver stats when it leaves the
/// foreground.
final class PlaybackStatsBackgroundTask {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private var isEnded = false

    static func beginIfNeeded(force: Bool = false) -> PlaybackStatsBackgroundTask? {
        guard force || UIApplication.shared.applicationState != .active else { return nil }

        let task = PlaybackStatsBackgroundTask()
        task.identifier = UIApplication.shared.beginBackgroundTask(withName: "GridStreamPlaybackStats") { [weak task] in
            Task { @MainActor in
                task?.end()
            }
        }

        return task.identifier == .invalid ? nil : task
    }

    func end() {
        guard !isEnded, identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
        isEnded = true
    }
}

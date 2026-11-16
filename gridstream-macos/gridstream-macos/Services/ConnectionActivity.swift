//
//  ConnectionActivity.swift
//  gridstream-macos
//
//  The connection monitor as the windows see it: samples it once a second
//  while the server runs and keeps the most recent log entries.
//

import Foundation
import Observation

@MainActor
@Observable
final class ConnectionActivity {
    private(set) var clients: [ConnectedClient] = []
    /// Newest first.
    private(set) var events: [ActivityEvent] = []
    /// Videos started since the server started.
    private(set) var videosServed = 0
    /// Bytes sent since the server started.
    private(set) var bytesSent: Int64 = 0

    @ObservationIgnored let monitor: ConnectionMonitor
    @ObservationIgnored private var samplingTask: Task<Void, Never>?

    static let maxEvents = 500

    init(monitor: ConnectionMonitor = ConnectionMonitor()) {
        self.monitor = monitor
    }

    // Nonisolated: the main-actor deinit the compiler would otherwise emit
    // aborts in the back-deployed runtime. The sampling loop ends by itself.
    nonisolated deinit {}

    var streamCount: Int {
        clients.reduce(0) { $0 + $1.streams.count }
    }

    var bytesPerSecond: Double {
        clients.reduce(0) { $0 + $1.bytesPerSecond }
    }

    func serverDidStart(port: Int) {
        monitor.reset()
        append([ActivityEvent(date: Date(), client: nil, kind: .serverStarted(port: port))])
        samplingTask?.cancel()
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { break }
                self.update()
            }
        }
    }

    func serverDidStop() {
        samplingTask?.cancel()
        samplingTask = nil
        update()
        monitor.reset()
        clients = []
        videosServed = 0
        bytesSent = 0
        append([ActivityEvent(date: Date(), client: nil, kind: .serverStopped)])
    }

    func clearLog() {
        events = []
    }

    func update(at now: Date = Date()) {
        let sample = monitor.sample(at: now)
        if clients != sample.clients { clients = sample.clients }
        if videosServed != sample.videosServed { videosServed = sample.videosServed }
        if bytesSent != sample.bytesSent { bytesSent = sample.bytesSent }
        append(sample.events)
    }

    private func append(_ newEvents: [ActivityEvent]) {
        guard !newEvents.isEmpty else { return }
        events.insert(contentsOf: newEvents.reversed(), at: 0)
        if events.count > Self.maxEvents {
            events.removeLast(events.count - Self.maxEvents)
        }
    }
}

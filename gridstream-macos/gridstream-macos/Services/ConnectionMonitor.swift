//
//  ConnectionMonitor.swift
//  gridstream-macos
//
//  Who is using the server: the devices making authenticated requests, the
//  videos they stream and how fast, and a log of sign-ins, connections and
//  streams. Request handlers report to it from any thread; the settings
//  window reads it once a second through `ConnectionActivity`.
//
//  HTTP has no connections to watch, so a device counts as connected from its
//  first authenticated request until it has been quiet for `idleTimeout`, and
//  a stream lasts while a response body for that video is being written, plus
//  `streamLinger` to bridge AVPlayer's back-to-back range requests.
//

import Foundation
import Vapor

/// What a client is, guessed from its User-Agent.
nonisolated enum ClientKind: Sendable, Equatable {
    /// The GridStream iPad app (its URLSession and AVPlayer requests).
    case iPad
    /// A web browser, with its name when recognised.
    case browser(String?)
    case unknown

    /// The kind a User-Agent points to, and whether it is certain: AVPlayer's
    /// `AppleCoreMedia` agent is also used by Safari for video, so it only
    /// counts until a clearer request arrives.
    static func guess(fromUserAgent userAgent: String?) -> (kind: ClientKind, isCertain: Bool) {
        guard let userAgent, !userAgent.isEmpty else { return (.unknown, false) }

        if userAgent.contains("Mozilla/") {
            let name: String? =
                if userAgent.contains("Edg/") { "Edge" }
                else if userAgent.contains("Firefox/") { "Firefox" }
                else if userAgent.contains("Chrome/") { "Chrome" }
                else if userAgent.contains("Safari/") { "Safari" }
                else { nil }
            return (.browser(name), true)
        }
        if userAgent.contains("CFNetwork/") {
            return (.iPad, true)
        }
        if userAgent.contains("AppleCoreMedia/") {
            return (.iPad, false)
        }
        return (.unknown, false)
    }
}

/// A device as the log and the list show it.
nonisolated struct ClientIdentity: Sendable, Equatable {
    /// Peer address, without the IPv4-mapped IPv6 prefix.
    let address: String
    let kind: ClientKind

    var isThisMac: Bool {
        address == "127.0.0.1" || address == "::1"
    }

    static func displayAddress(_ address: String) -> String {
        address.hasPrefix("::ffff:") ? String(address.dropFirst(7)) : address
    }
}

nonisolated struct ActiveStream: Identifiable, Sendable, Equatable {
    let fileId: String
    let filename: String
    let startedAt: Date
    let bytesSent: Int64
    let bytesPerSecond: Double

    var id: String { fileId }
}

nonisolated struct ConnectedClient: Identifiable, Sendable, Equatable {
    let identity: ClientIdentity
    let connectedAt: Date
    let bytesSent: Int64
    let bytesPerSecond: Double
    let streams: [ActiveStream]

    var id: String { identity.address }
}

nonisolated struct ActivityEvent: Identifiable, Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case serverStarted(port: Int)
        case serverStopped
        case connected
        case wentIdle(bytesSent: Int64)
        case signedIn
        case wrongPIN
        case signInBlocked
        case signedOut
        case streamStarted(filename: String)
        case streamEnded(filename: String, bytesSent: Int64, duration: TimeInterval)
    }

    let id = UUID()
    let date: Date
    let client: ClientIdentity?
    let kind: Kind
}

/// What changed since the previous sample.
nonisolated struct ActivitySample: Sendable {
    let clients: [ConnectedClient]
    let events: [ActivityEvent]
    let videosServed: Int
    let bytesSent: Int64
}

nonisolated enum SignInOutcome: Sendable {
    case succeeded
    case wrongPIN
    case blocked
}

/// Counts the bytes of one video response body as they are written.
nonisolated struct StreamMeter: Sendable {
    fileprivate let monitor: ConnectionMonitor
    fileprivate let key: ConnectionMonitor.StreamKey

    func add(_ byteCount: Int) {
        monitor.streamDidSend(key, byteCount: byteCount)
    }

    func close() {
        monitor.streamDidClose(key)
    }
}

// `@unchecked Sendable`: all mutable state is guarded by `lock`.
nonisolated final class ConnectionMonitor: @unchecked Sendable {
    fileprivate struct StreamKey: Hashable, Sendable {
        let address: String
        let fileId: String
    }

    private struct Client {
        var kind: ClientKind
        var kindIsCertain: Bool
        let connectedAt: Date
        var lastSeen: Date
        var bytesSent: Int64 = 0
        var sampledBytes: Int64 = 0
        var bytesPerSecond: Double = 0
    }

    private struct Stream {
        let filename: String
        let startedAt: Date
        var lastActivity: Date
        var openBodies = 0
        var bytesSent: Int64 = 0
        var sampledBytes: Int64 = 0
        var bytesPerSecond: Double = 0
    }

    /// Quiet time after which a device no longer counts as connected.
    let idleTimeout: TimeInterval
    /// Time a finished response keeps its stream alive, waiting for the next range.
    let streamLinger: TimeInterval

    private static let maxPendingEvents = 1_000

    private let lock = NSLock()
    private var clients: [String: Client] = [:]
    private var streams: [StreamKey: Stream] = [:]
    private var pendingEvents: [ActivityEvent] = []
    private var videosServed = 0
    private var bytesSent: Int64 = 0
    private var lastSample: Date?

    init(idleTimeout: TimeInterval = 120, streamLinger: TimeInterval = 8) {
        self.idleTimeout = idleTimeout
        self.streamLinger = streamLinger
    }

    // MARK: - Reporting (any thread)

    /// An authenticated request, with the size of a response not metered by a `StreamMeter`.
    func recordRequest(from address: String, userAgent: String?, bytesSent byteCount: Int = 0, at now: Date = Date()) {
        lock.withLock {
            let address = ClientIdentity.displayAddress(address)
            touchClient(address, userAgent: userAgent, at: now)
            if byteCount > 0 {
                clients[address]?.bytesSent += Int64(byteCount)
                bytesSent += Int64(byteCount)
            }
        }
    }

    func recordSignIn(from address: String, userAgent: String?, outcome: SignInOutcome, at now: Date = Date()) {
        lock.withLock {
            let address = ClientIdentity.displayAddress(address)
            switch outcome {
            case .succeeded:
                touchClient(address, userAgent: userAgent, at: now)
                log(.signedIn, client: identity(of: address, userAgent: userAgent), at: now)
            case .wrongPIN:
                log(.wrongPIN, client: identity(of: address, userAgent: userAgent), at: now)
            case .blocked:
                log(.signInBlocked, client: identity(of: address, userAgent: userAgent), at: now)
            }
        }
    }

    func recordSignOut(from address: String, userAgent: String?, at now: Date = Date()) {
        lock.withLock {
            let address = ClientIdentity.displayAddress(address)
            log(.signedOut, client: identity(of: address, userAgent: userAgent), at: now)
        }
    }

    /// Starts metering a video response body; close the meter when it ends.
    func openStream(
        from address: String,
        userAgent: String?,
        fileId: String,
        filename: String,
        at now: Date = Date()
    ) -> StreamMeter {
        lock.withLock {
            let address = ClientIdentity.displayAddress(address)
            touchClient(address, userAgent: userAgent, at: now)
            let key = StreamKey(address: address, fileId: fileId)
            if streams[key] == nil {
                streams[key] = Stream(filename: filename, startedAt: now, lastActivity: now)
                videosServed += 1
                log(.streamStarted(filename: filename), client: identity(of: address), at: now)
            }
            streams[key]?.openBodies += 1
            streams[key]?.lastActivity = now
            return StreamMeter(monitor: self, key: key)
        }
    }

    fileprivate func streamDidSend(_ key: StreamKey, byteCount: Int, at now: Date = Date()) {
        lock.withLock {
            guard streams[key] != nil else { return }
            streams[key]?.bytesSent += Int64(byteCount)
            streams[key]?.lastActivity = now
            clients[key.address]?.bytesSent += Int64(byteCount)
            clients[key.address]?.lastSeen = now
            bytesSent += Int64(byteCount)
        }
    }

    fileprivate func streamDidClose(_ key: StreamKey, at now: Date = Date()) {
        lock.withLock {
            guard streams[key] != nil else { return }
            streams[key]?.openBodies -= 1
            streams[key]?.lastActivity = now
        }
    }

    // MARK: - Sampling (one reader)

    /// Ends quiet streams and devices, updates the rates and hands over the
    /// events logged since the previous sample.
    func sample(at now: Date = Date()) -> ActivitySample {
        lock.withLock {
            let elapsed = lastSample.map { now.timeIntervalSince($0) } ?? 0
            lastSample = now

            for (key, stream) in streams.sorted(by: { $0.value.startedAt < $1.value.startedAt }) {
                if stream.openBodies <= 0, now.timeIntervalSince(stream.lastActivity) >= streamLinger {
                    streams[key] = nil
                    log(
                        .streamEnded(
                            filename: stream.filename,
                            bytesSent: stream.bytesSent,
                            duration: stream.lastActivity.timeIntervalSince(stream.startedAt)
                        ),
                        client: identity(of: key.address),
                        at: now
                    )
                } else {
                    streams[key]?.bytesPerSecond = Self.rate(stream.bytesSent - stream.sampledBytes, over: elapsed, previous: stream.bytesPerSecond)
                    streams[key]?.sampledBytes = stream.bytesSent
                }
            }

            let streamingAddresses = Set(streams.keys.map(\.address))
            for (address, client) in clients.sorted(by: { $0.value.connectedAt < $1.value.connectedAt }) {
                if !streamingAddresses.contains(address), now.timeIntervalSince(client.lastSeen) >= idleTimeout {
                    clients[address] = nil
                    log(.wentIdle(bytesSent: client.bytesSent), client: ClientIdentity(address: address, kind: client.kind), at: now)
                } else {
                    clients[address]?.bytesPerSecond = Self.rate(client.bytesSent - client.sampledBytes, over: elapsed, previous: client.bytesPerSecond)
                    clients[address]?.sampledBytes = client.bytesSent
                }
            }

            let connected = clients
                .map { address, client in
                    ConnectedClient(
                        identity: ClientIdentity(address: address, kind: client.kind),
                        connectedAt: client.connectedAt,
                        bytesSent: client.bytesSent,
                        bytesPerSecond: client.bytesPerSecond,
                        streams: streams
                            .filter { $0.key.address == address }
                            .map { key, stream in
                                ActiveStream(
                                    fileId: key.fileId,
                                    filename: stream.filename,
                                    startedAt: stream.startedAt,
                                    bytesSent: stream.bytesSent,
                                    bytesPerSecond: stream.bytesPerSecond
                                )
                            }
                            .sorted { $0.startedAt < $1.startedAt }
                    )
                }
                .sorted { $0.connectedAt < $1.connectedAt }

            let events = pendingEvents
            pendingEvents.removeAll()
            return ActivitySample(clients: connected, events: events, videosServed: videosServed, bytesSent: bytesSent)
        }
    }

    /// Forgets every device and stream, and the totals, when the server stops.
    func reset() {
        lock.withLock {
            clients.removeAll()
            streams.removeAll()
            pendingEvents.removeAll()
            videosServed = 0
            bytesSent = 0
            lastSample = nil
        }
    }

    // MARK: - Private (under lock)

    private func touchClient(_ address: String, userAgent: String?, at now: Date) {
        let guess = ClientKind.guess(fromUserAgent: userAgent)
        if var client = clients[address] {
            client.lastSeen = now
            if guess.isCertain && !client.kindIsCertain || client.kind == .unknown && guess.kind != .unknown {
                client.kind = guess.kind
                client.kindIsCertain = guess.isCertain
            }
            clients[address] = client
        } else {
            clients[address] = Client(kind: guess.kind, kindIsCertain: guess.isCertain, connectedAt: now, lastSeen: now)
            log(.connected, client: ClientIdentity(address: address, kind: guess.kind), at: now)
        }
    }

    /// The device as known, or as its User-Agent describes it.
    private func identity(of address: String, userAgent: String? = nil) -> ClientIdentity {
        ClientIdentity(address: address, kind: clients[address]?.kind ?? ClientKind.guess(fromUserAgent: userAgent).kind)
    }

    private func log(_ kind: ActivityEvent.Kind, client: ClientIdentity?, at date: Date) {
        pendingEvents.append(ActivityEvent(date: date, client: client, kind: kind))
        if pendingEvents.count > Self.maxPendingEvents {
            pendingEvents.removeFirst(pendingEvents.count - Self.maxPendingEvents)
        }
    }

    /// Bytes per second over the last interval, smoothed so a bursty client
    /// does not flicker between zero and its peak.
    private static func rate(_ byteCount: Int64, over interval: TimeInterval, previous: Double) -> Double {
        guard interval > 0 else { return previous }
        let current = Double(byteCount) / interval
        let smoothed = previous * 0.5 + current * 0.5
        return smoothed < 1 ? 0 : smoothed
    }
}

// MARK: - Application storage

nonisolated struct ConnectionMonitorStorageKey: StorageKey {
    typealias Value = ConnectionMonitor
}

extension Application {
    /// The monitor the server reports to; nil in tests that do not install one.
    nonisolated var connectionMonitor: ConnectionMonitor? {
        get { storage[ConnectionMonitorStorageKey.self] }
        set { storage[ConnectionMonitorStorageKey.self] = newValue }
    }
}

extension Request {
    /// The peer address, as used for the activity log and login throttling.
    nonisolated var clientAddress: String {
        remoteAddress?.ipAddress ?? "unknown"
    }

    nonisolated var userAgent: String? {
        headers.first(name: .userAgent)
    }
}

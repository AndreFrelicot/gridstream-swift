//
//  ServerDiscoveryService.swift
//  gridstream-ipad
//

import Foundation
import OSLog

@Observable
final class ServerDiscoveryService: NSObject {
    private(set) var discoveredServers: [DiscoveredServer] = []
    private(set) var connectionStatus: ConnectionStatus = .disconnected
    /// Stable identity of the active server (`activeServer`).
    /// Updated only when the active server's URL effectively changes (host/port);
    /// preserved across transient removal/rediscovery so SwiftUI `.task(id:)`
    /// observers do not refire on routine Bonjour resyncs.
    private(set) var targetServerIdentifier: String?
    /// Servers that have been seeded from persistence but whose reachability
    /// has not yet been confirmed by a 200 health probe in the current
    /// foreground session. UI / phase-2 restore code that depends on the
    /// server actually being there should consult `verifiedServers` instead
    /// of `discoveredServers`.
    private(set) var unverifiedServerNames: Set<String> = []

    /// Subset of `discoveredServers` that have been confirmed reachable
    /// since the service was instantiated. Observers that want to gate
    /// behavior on real reachability (e.g., cold-start restore) should
    /// watch this array, not `discoveredServers`.
    var verifiedServers: [DiscoveredServer] {
        discoveredServers.filter { !unverifiedServerNames.contains($0.name) }
    }

    /// Name of the server the app works with. Chosen once (the first server
    /// found, or the persisted last-known one) and persisted, so with
    /// several servers on the network the session, the catalog, the library
    /// and new tiles all talk to the same one.
    private(set) var activeServerName: String?

    /// The server every consumer must use. Falls back to another discovered
    /// server only while the chosen one is absent.
    var activeServer: DiscoveredServer? {
        if let activeServerName,
           let server = discoveredServers.first(where: { $0.name == activeServerName }) {
            return server
        }
        return discoveredServers.first
    }

    var activeServerURL: URL? {
        activeServer?.url
    }

    /// `activeServer`, once its reachability has been confirmed.
    var verifiedActiveServer: DiscoveredServer? {
        guard let server = activeServer, !unverifiedServerNames.contains(server.name) else {
            return nil
        }
        return server
    }

    /// Bonjour browsing triggers the system's Local Network prompt, so it
    /// stays off until the user asks to find their Mac (`DemoController`).
    var isBrowsingEnabled = true

    // Only touched on the main actor, and in deinit once nothing else holds the object.
    @ObservationIgnored nonisolated(unsafe) private var browser: NetServiceBrowser?
    // Only touched on the main actor, and in deinit once nothing else holds the object.
    @ObservationIgnored nonisolated(unsafe) private var pendingServices: [NetService] = []
    private var liveServiceIDs: Set<ObjectIdentifier> = []
    private var isSearching = false
    private var lastKnownServer: DiscoveredServer?
    // Only touched on the main actor, and in deinit once nothing else holds the object.
    @ObservationIgnored nonisolated(unsafe) private var watchdogTask: Task<Void, Never>?
    private var consecutiveProbeFailures = 0
    private let watchdogIntervals: [UInt64] = [3, 6, 12, 24, 30]
    private let watchdogMaxFailures = 3

    private let serviceType = "_gridstream._tcp."
    private let serviceDomain = "local."
    private let resolveTimeout: TimeInterval = 10.0

    /// `UserDefaults` key for the sticky last-known server (encoded
    /// `PersistedServer`). Persisting in defaults rather than SwiftData
    /// avoids coupling discovery to the model container lifecycle.
    private let lastKnownServerKey = "GridStreamLastKnownServer"

    private struct PersistedServer: Codable {
        let name: String
        let hostname: String
        let port: Int
    }

    override init() {
        super.init()
        seedLastKnownServerFromDefaults()
    }

    func startDiscovery() {
        guard isBrowsingEnabled else { return }
        guard !isSearching else {
            AppLogger.discovery.warning("Discovery already in progress")
            return
        }

        stopBrowser()

        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: serviceType, inDomain: serviceDomain)

        isSearching = true
        if discoveredServers.isEmpty {
            connectionStatus = .searching
        }
        AppLogger.discovery.info("Started Bonjour discovery for \(self.serviceType)")

        // Replace the legacy one-shot 5s retry with an exponential watchdog
        // that re-probes the last-known server AND restarts Bonjour at
        // 3/6/12/24/30(...)s. The watchdog cancels itself the moment any
        // discovered server transitions to `verified`.
        startWatchdog()
    }

    func stopDiscovery() {
        watchdogTask?.cancel()
        watchdogTask = nil
        stopBrowser()
        isSearching = false
        AppLogger.discovery.info("Stopped Bonjour discovery")
    }

    /// Restarts discovery from scratch. Call when returning from background
    /// to ensure a fresh Bonjour browse that will find servers reliably.
    func restartDiscovery() {
        guard isBrowsingEnabled else { return }
        AppLogger.discovery.info("Restarting discovery")
        let wasSearching = isSearching
        stopBrowser()
        isSearching = false
        if wasSearching || browser == nil {
            startDiscovery()
        }
    }

    /// Pings the last-known server to check if it's still reachable.
    /// On success, marks the seeded server as verified for an instant
    /// reconnect while Bonjour catches up in the background.
    func validateLastKnownServer() {
        guard let server = lastKnownServer, let baseURL = server.url else { return }

        let healthURL = baseURL.appendingPathComponent("api/v1/auth/session")
        AppLogger.discovery.info("Validating last-known server at \(healthURL.absoluteString)")

        Task { @MainActor [weak self] in
            await self?.runProbe(against: server, healthURL: healthURL)
        }
    }

    private func runProbe(against server: DiscoveredServer, healthURL: URL) async {
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 3

        do {
            let (_, response) = try await ServerSessionManager.shared.urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                handleProbeFailure(reason: "non-HTTP response")
                return
            }

            // Treat any 2xx/4xx as proof of reachability — even 401 means
            // the server *exists* and the network is intact; auth handling
            // is the session manager's job, not discovery's.
            guard (200..<500).contains(httpResponse.statusCode) else {
                handleProbeFailure(reason: "HTTP \(httpResponse.statusCode)")
                return
            }

            handleProbeSuccess(for: server)
        } catch {
            handleProbeFailure(reason: error.localizedDescription)
        }
    }

    private func handleProbeSuccess(for server: DiscoveredServer) {
        consecutiveProbeFailures = 0
        addDiscoveredServer(server)
        unverifiedServerNames.remove(server.name)
        AppLogger.discovery.info("Probe succeeded for \(server.name), marked verified")
    }

    private func handleProbeFailure(reason: String) {
        consecutiveProbeFailures += 1
        AppLogger.discovery.warning("Last-known server probe failed (#\(self.consecutiveProbeFailures)/\(self.watchdogMaxFailures)): \(reason)")

        guard consecutiveProbeFailures >= watchdogMaxFailures else { return }

        // Drop any unverified-only servers from the visible list so the UI
        // doesn't stay stuck pointing at a ghost server after a real
        // network change.
        let staleNames = unverifiedServerNames
        for name in staleNames {
            removeServer(named: name)
        }
        unverifiedServerNames.removeAll()

        // The chosen server is gone for good (not just a Bonjour blip):
        // adopt the next one, if any, as the new active server.
        if let activeServerName, staleNames.contains(activeServerName) {
            self.activeServerName = nil
            lastKnownServer = nil
            if let next = discoveredServers.first {
                adoptAsActive(next)
            }
            refreshTargetIdentifier()
        }
        AppLogger.discovery.warning("Dropped unverified servers after \(self.watchdogMaxFailures) consecutive probe failures")
    }

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var step = 0
            while !Task.isCancelled {
                let waitSeconds = self.watchdogIntervals[min(step, self.watchdogIntervals.count - 1)]
                step += 1
                try? await Task.sleep(nanoseconds: waitSeconds * 1_000_000_000)
                guard !Task.isCancelled else { return }
                guard self.isSearching else { return }

                if !self.verifiedServers.isEmpty {
                    AppLogger.discovery.debug("Watchdog exiting: verified server present")
                    return
                }

                AppLogger.discovery.warning("Watchdog tick (\(waitSeconds)s): re-probing and restarting Bonjour")
                self.validateLastKnownServer()

                // Kick Bonjour again — some networks drop the browser's
                // first results after a wake-up.
                self.stopBrowser()
                guard !Task.isCancelled else { return }
                self.browser = NetServiceBrowser()
                self.browser?.delegate = self
                self.browser?.searchForServices(ofType: self.serviceType, inDomain: self.serviceDomain)
            }
        }
    }

    private func stopBrowser() {
        // Null the delegate before stop() so callbacks queued on the Bonjour thread
        // for this browser are dropped before they can reach the new browser.
        browser?.delegate = nil
        browser?.stop()
        browser = nil

        for service in pendingServices {
            service.delegate = nil
            service.stop()
        }
        pendingServices.removeAll()
        // Invalidate any in-flight resolve callbacks: stale services will fail
        // the liveServiceIDs membership check in NetServiceDelegate callbacks.
        liveServiceIDs.removeAll()
    }

    private func resolveService(_ service: NetService) {
        service.delegate = self
        service.resolve(withTimeout: resolveTimeout)
        pendingServices.append(service)
        liveServiceIDs.insert(ObjectIdentifier(service))
        AppLogger.discovery.debug("Resolving service: \(service.name)")
    }

    private func addDiscoveredServer(_ server: DiscoveredServer) {
        if let existingIndex = discoveredServers.firstIndex(where: { $0.name == server.name }) {
            // Re-resolving the same service yields an equal value: don't
            // touch the array, so observers aren't woken for nothing.
            if discoveredServers[existingIndex] != server {
                discoveredServers[existingIndex] = server
            }
            if activeServerName == nil || activeServerName == server.name {
                adoptAsActive(server)
            }
            refreshTargetIdentifier()
            AppLogger.discovery.info("Updated discovered server: \(server.name) at \(server.hostname):\(server.port)")
            return
        }

        discoveredServers.append(server)
        // Only the active server is remembered: another GridStream server
        // on the network must not silently take over.
        if activeServerName == nil || activeServerName == server.name {
            adoptAsActive(server)
        }
        refreshTargetIdentifier()

        if case .searching = connectionStatus {
            connectionStatus = .found(serverName: server.name)
        } else if case .disconnected = connectionStatus {
            connectionStatus = .found(serverName: server.name)
        }

        AppLogger.discovery.info("Discovered server: \(server.name) at \(server.hostname):\(server.port)")
    }

    private func removeServer(named name: String) {
        discoveredServers.removeAll { $0.name == name }
        unverifiedServerNames.remove(name)

        if discoveredServers.isEmpty {
            connectionStatus = .searching
        } else if let server = activeServer {
            connectionStatus = .found(serverName: server.name)
        }

        // Only update the identifier if the new first-server URL really differs.
        // If the list briefly empties, keep the prior identifier so transient
        // disappearance does not retrigger session checks on rediscovery.
        refreshTargetIdentifier()

        AppLogger.discovery.info("Removed server: \(name)")
    }

    // MARK: - Demo

    /// True while the app works with the demo server.
    var isDemoActive: Bool {
        DemoMode.isDemo(activeServer)
    }

    /// Makes the demo the active server. It is remembered like any server,
    /// so the next launch reopens the demo; Bonjour servers found meanwhile
    /// stay listed but do not take over.
    func activateDemo() {
        let server = DemoMode.server
        unverifiedServerNames.remove(server.name)
        if !discoveredServers.contains(server) {
            discoveredServers.removeAll { $0.name == server.name }
            discoveredServers.insert(server, at: 0)
        }
        adoptAsActive(server)
        connectionStatus = .found(serverName: server.name)
        refreshTargetIdentifier()
        AppLogger.discovery.info("Demo server activated")
    }

    /// Leaves the demo: the next real server found becomes the active one.
    func deactivateDemo() {
        let wasActive = isDemoActive
        discoveredServers.removeAll { DemoMode.isDemo($0) }
        unverifiedServerNames.remove(DemoMode.server.name)
        guard wasActive else { return }

        activeServerName = nil
        lastKnownServer = nil
        UserDefaults.standard.removeObject(forKey: lastKnownServerKey)
        if let next = verifiedServers.first {
            adoptAsActive(next)
            connectionStatus = .found(serverName: next.name)
        } else {
            connectionStatus = isSearching ? .searching : .disconnected
        }
        refreshTargetIdentifier()
        AppLogger.discovery.info("Demo server deactivated")
    }

    private func adoptAsActive(_ server: DiscoveredServer) {
        activeServerName = server.name
        lastKnownServer = server
        persistLastKnownServer(server)
    }

    private func refreshTargetIdentifier() {
        guard let candidate = activeServer?.url?.absoluteString else { return }
        if candidate != targetServerIdentifier {
            targetServerIdentifier = candidate
        }
    }

    // MARK: - Sticky last-known persistence

    private func seedLastKnownServerFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: lastKnownServerKey),
              let persisted = try? JSONDecoder().decode(PersistedServer.self, from: data) else {
            return
        }

        let server = DiscoveredServer(
            name: persisted.name,
            hostname: persisted.hostname,
            port: persisted.port
        )
        lastKnownServer = server
        activeServerName = server.name
        discoveredServers = [server]
        unverifiedServerNames.insert(server.name)
        connectionStatus = .found(serverName: server.name)
        refreshTargetIdentifier()
        AppLogger.discovery.info("Seeded last-known server \(server.name) at \(server.hostname):\(server.port) (unverified)")
    }

    private func persistLastKnownServer(_ server: DiscoveredServer) {
        let persisted = PersistedServer(name: server.name, hostname: server.hostname, port: server.port)
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        UserDefaults.standard.set(data, forKey: lastKnownServerKey)
    }

    @objc private func resolveServiceFromDelegate(_ service: NetService) {
        resolveService(service)
    }

    deinit {
        watchdogTask?.cancel()
        // As in stopBrowser(): the delegates are not retained, so they are
        // cleared before this object goes away.
        browser?.delegate = nil
        browser?.stop()
        for service in pendingServices {
            service.delegate = nil
            service.stop()
        }
    }
}

extension ServerDiscoveryService: NetServiceBrowserDelegate {
    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        // The service type is dedicated to GridStream, so no name filtering.
        // Handed over to the main actor; not touched here afterwards.
        nonisolated(unsafe) let browser = browser
        nonisolated(unsafe) let service = service
        Task { @MainActor [weak self] in
            guard let self, self.browser === browser else { return }
            self.resolveService(service)
        }
        AppLogger.discovery.debug("Found GridStream service: \(service.name)")
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let serviceName = service.name
        // Handed over to the main actor; not touched here afterwards.
        nonisolated(unsafe) let browser = browser
        Task { @MainActor [weak self, serviceName] in
            guard let self, self.browser === browser else { return }
            self.removeServer(named: serviceName)
            self.pendingServices.removeAll { $0.name == serviceName }
        }
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        let errorCode = errorDict[NetService.errorCode] ?? -1
        let errorDomain = errorDict[NetService.errorDomain] ?? -1
        // Handed over to the main actor; not touched here afterwards.
        nonisolated(unsafe) let browser = browser
        Task { @MainActor [weak self] in
            guard let self, self.browser === browser else { return }
            if self.verifiedServers.isEmpty {
                self.connectionStatus = .disconnected
            }
            self.isSearching = false
        }
        AppLogger.discovery.error("Discovery failed - code: \(errorCode), domain: \(errorDomain)")
    }

    nonisolated func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        // Handed over to the main actor; not touched here afterwards.
        nonisolated(unsafe) let browser = browser
        Task { @MainActor [weak self] in
            guard let self, self.browser === browser else { return }
            self.isSearching = false
        }
        AppLogger.discovery.info("Discovery search stopped")
    }
}

extension ServerDiscoveryService: NetServiceDelegate {
    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        guard let hostname = sender.hostName else {
            AppLogger.discovery.warning("Service resolved but no hostname: \(sender.name)")
            return
        }

        let server = DiscoveredServer(
            name: sender.name,
            hostname: hostname,
            port: sender.port
        )
        let serviceID = ObjectIdentifier(sender)
        sender.delegate = nil

        Task { @MainActor [weak self, server] in
            guard let self else { return }
            // Drop the callback if it belongs to a prior discovery cycle.
            guard self.liveServiceIDs.remove(serviceID) != nil else { return }
            // A Bonjour resolution proves reachability — treat as verified
            // and drop any stale unverified flag from the sticky seed.
            self.unverifiedServerNames.remove(server.name)
            self.addDiscoveredServer(server)
            self.pendingServices.removeAll { ObjectIdentifier($0) == serviceID }
        }
    }

    nonisolated func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        let errorCode = errorDict[NetService.errorCode] ?? -1
        let serviceName = sender.name
        let serviceID = ObjectIdentifier(sender)
        sender.delegate = nil
        AppLogger.discovery.warning("Failed to resolve service \(serviceName) - code: \(errorCode)")

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.liveServiceIDs.remove(serviceID)
            self.pendingServices.removeAll { ObjectIdentifier($0) == serviceID }
        }
    }
}

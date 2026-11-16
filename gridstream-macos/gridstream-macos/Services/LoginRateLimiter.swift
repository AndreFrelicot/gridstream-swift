import Foundation
import Vapor

/// Throttles PIN login attempts (contract §7):
/// - per client IP, exponential backoff after 3 failures (1 s doubling, capped at 15 min);
/// - globally, 20 or more failures within a minute lock every login for 60 s.
///
/// Sendable: all mutable state is guarded by `lock`.
nonisolated final class LoginRateLimiter: @unchecked Sendable {
    static let freeFailures = 3
    static let baseDelay: TimeInterval = 1
    static let maxDelay: TimeInterval = 15 * 60
    static let globalWindow: TimeInterval = 60
    static let globalFailureLimit = 20
    static let globalLockout: TimeInterval = 60

    private struct ClientState {
        var failures = 0
        var inFlight = 0
        var blockedUntil: Date = .distantPast
    }

    private let lock = NSLock()
    private var clients: [String: ClientState] = [:]
    private var recentFailures: [Date] = []
    private var inFlight = 0
    private var globalBlockedUntil: Date = .distantPast

    /// Seconds the client must wait before trying again, nil when allowed now.
    func retryAfter(for client: String, now: Date = Date()) -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        return retryAfterLocked(for: client, now: now)
    }

    /// Admission and reservation share the lock: bcrypt work already in flight
    /// counts against both quotas, even before any verification has finished.
    func reserveAttempt(for client: String, now: Date = Date()) -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        if let wait = retryAfterLocked(for: client, now: now) { return wait }
        clients[client, default: ClientState()].inFlight += 1
        inFlight += 1
        return nil
    }

    func finishAttempt(for client: String, succeeded: Bool, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        guard var state = clients[client], state.inFlight > 0 else { return }
        state.inFlight -= 1
        inFlight -= 1
        if succeeded {
            state.failures = 0
            state.blockedUntil = .distantPast
        }
        clients[client] = state
        if !succeeded { recordFailureLocked(for: client, now: now) }
    }

    private func retryAfterLocked(for client: String, now: Date) -> TimeInterval? {
        recentFailures.removeAll { now.timeIntervalSince($0) > Self.globalWindow }
        let state = clients[client] ?? ClientState()
        let blockedUntil = max(globalBlockedUntil, state.blockedUntil)
        let wait = blockedUntil.timeIntervalSince(now)
        if wait > 0 { return wait }
        if state.inFlight > 0 && state.failures + state.inFlight >= Self.freeFailures
            || recentFailures.count + inFlight >= Self.globalFailureLimit {
            return Self.baseDelay
        }
        return nil
    }

    func recordFailure(for client: String, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }

        recordFailureLocked(for: client, now: now)
    }

    private func recordFailureLocked(for client: String, now: Date) {
        var state = clients[client] ?? ClientState()
        state.failures += 1
        if state.failures >= Self.freeFailures {
            let exponent = min(state.failures - Self.freeFailures, 20)
            let delay = min(Self.baseDelay * pow(2, Double(exponent)), Self.maxDelay)
            state.blockedUntil = now.addingTimeInterval(delay)
        }
        clients[client] = state

        recentFailures.append(now)
        recentFailures.removeAll { now.timeIntervalSince($0) > Self.globalWindow }
        if recentFailures.count >= Self.globalFailureLimit {
            globalBlockedUntil = now.addingTimeInterval(Self.globalLockout)
            recentFailures.removeAll()
        }

        // Bound memory: forget clients whose block expired long ago
        if clients.count > 10_000 {
            clients = clients.filter { $0.value.inFlight > 0 || $0.value.blockedUntil > now }
        }
    }

    func recordSuccess(for client: String) {
        lock.lock()
        defer { lock.unlock() }
        guard var state = clients[client] else { return }
        state.failures = 0
        state.blockedUntil = .distantPast
        clients[client] = state.inFlight == 0 ? nil : state
    }
}

private nonisolated struct LoginRateLimiterStorageKey: StorageKey {
    typealias Value = LoginRateLimiter
}

nonisolated extension Application {
    nonisolated var loginRateLimiter: LoginRateLimiter {
        get {
            if let limiter = storage[LoginRateLimiterStorageKey.self] {
                return limiter
            }
            let limiter = LoginRateLimiter()
            storage[LoginRateLimiterStorageKey.self] = limiter
            return limiter
        }
        set {
            storage[LoginRateLimiterStorageKey.self] = newValue
        }
    }
}

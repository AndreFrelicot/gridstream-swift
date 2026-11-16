import Foundation
import Vapor

/// DNS-rebinding guard (contract §7): while auth is disabled, only requests
/// whose `Host` is an IP literal, `localhost`, a `*.local` name or one of this
/// machine's host names are served. With auth enabled every request needs a
/// session anyway, so the guard steps aside.
nonisolated struct HostGuardMiddleware: AsyncMiddleware {
    private let ownHostNames: Set<String>

    init(ownHostNames: Set<String> = HostGuardMiddleware.currentHostNames()) {
        self.ownHostNames = Set(ownHostNames.map { $0.lowercased() })
    }

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        if !request.application.serverAuthManager.requiresAuthentication(),
           let host = request.headers.first(name: .host),
           !isAllowed(host: host) {
            throw Abort(.forbidden, reason: "Host not allowed")
        }
        return try await next.respond(to: request)
    }

    func isAllowed(host rawHost: String) -> Bool {
        let host = Self.hostName(fromHostHeader: rawHost).lowercased()
        if host.isEmpty { return false }
        if Self.isIPLiteral(host) { return true }
        if host == "localhost" || host.hasSuffix(".localhost") { return true }
        if host.hasSuffix(".local") || host.hasSuffix(".local.") { return true }
        return ownHostNames.contains(host)
    }

    /// Strips the port and IPv6 brackets from a Host header value.
    static func hostName(fromHostHeader value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[") {
            guard let end = trimmed.firstIndex(of: "]") else { return trimmed }
            return String(trimmed[trimmed.index(after: trimmed.startIndex)..<end])
        }
        if trimmed.filter({ $0 == ":" }).count == 1, let colon = trimmed.firstIndex(of: ":") {
            return String(trimmed[..<colon])
        }
        return trimmed
    }

    static func isIPLiteral(_ host: String) -> Bool {
        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        return inet_pton(AF_INET, host, &ipv4) == 1 || inet_pton(AF_INET6, host, &ipv6) == 1
    }

    static func currentHostNames() -> Set<String> {
        let hostName = ProcessInfo.processInfo.hostName.lowercased()
        var names: Set<String> = [hostName]
        if let firstLabel = hostName.split(separator: ".").first {
            names.insert(String(firstLabel))
        }
        return names
    }
}

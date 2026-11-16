//
//  DiscoveredServer.swift
//  gridstream-ipad
//

import Foundation

/// A GridStream server found by Bonjour (or seeded from the last-known
/// server). Identity and equality are `name + hostname + port` (contract §8):
/// re-resolving the same service must produce an equal value, otherwise every
/// Bonjour resync looks like a new server to SwiftUI `onChange` observers.
struct DiscoveredServer: Identifiable, Hashable, Sendable {
    let name: String
    let hostname: String
    let port: Int

    nonisolated init(name: String, hostname: String, port: Int) {
        self.name = name
        self.hostname = hostname
        self.port = port
    }

    nonisolated var id: String {
        "\(name)|\(hostname)|\(port)"
    }

    nonisolated var url: URL? {
        URL(string: "http://\(hostname):\(port)")
    }
}

//
//  DemoMode.swift
//  gridstream-ipad
//
//  The demo is a server that lives inside the app: requests to the reserved
//  host `demo.gridstream.invalid` are answered by `DemoServer` through
//  `DemoURLProtocol`, and streams play the pack's local files.
//

import Foundation

nonisolated enum DemoMode {
    /// `.invalid` is a reserved TLD: this host never resolves on a network.
    static let host = "demo.gridstream.invalid"

    /// The demo's entry in the server list.
    static let server = DiscoveredServer(name: "GridStream Demo", hostname: host, port: 80)

    static var serverURL: URL {
        // Built from a constant host and port, never nil.
        server.url!
    }

    static func isDemo(_ url: URL?) -> Bool {
        url?.host == host
    }

    static func isDemo(_ server: DiscoveredServer?) -> Bool {
        server?.hostname == host
    }

    /// The URL AVFoundation should open for `url`: the pack's local clip for
    /// a demo stream URL (`/api/v1/videos/:fileId/stream`), `url` otherwise.
    /// AVPlayer does not go through `URLProtocol`, so demo streams need files.
    static func playableURL(for url: URL) -> URL {
        guard isDemo(url) else { return url }
        let components = url.pathComponents
        guard let index = components.firstIndex(of: "videos"),
              components.count > index + 2,
              components[index + 2] == "stream",
              let clip = DemoPack.clipURL(forFileId: components[index + 1]) else {
            return url
        }
        return clip
    }
}

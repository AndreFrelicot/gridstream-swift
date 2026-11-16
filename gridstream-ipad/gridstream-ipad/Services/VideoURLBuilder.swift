//
//  VideoURLBuilder.swift
//  gridstream-ipad
//
//  Builds media URLs (stream, thumbnail, scrub frame, cached-times, capture
//  image). When auth is enabled these routes require a session; AVPlayer and
//  image loaders can't send the Bearer header, so the session token travels
//  as a `token` query item (contract §7). Only media URLs get it — the server
//  rejects `token` on metadata routes, which use the Bearer header.
//

import Foundation
import GridStreamAPI
import OSLog

struct VideoURLBuilder {
    /// Name of the query item carrying the session token on media URLs.
    static let tokenQueryItemName = "token"

    /// Resolves the session token for a server base URL. Replaceable in tests.
    static var tokenProvider: (URL) -> String? = { serverURL in
        ServerSessionManager.shared.sessionToken(for: serverURL)
    }

    private let server: DiscoveredServer

    init(server: DiscoveredServer) {
        self.server = server
    }

    // MARK: - Stream

    func buildStreamURL(for videoId: String) -> URL? {
        guard let baseURL = server.url else {
            AppLogger.video.warning("Cannot build stream URL: server URL is nil")
            return nil
        }

        return Self.buildStreamURL(from: baseURL, videoId: videoId)
    }

    static func buildStreamURL(from serverURL: URL, videoId: String) -> URL? {
        let path = "/api/v1/videos/\(videoId)/stream"
        guard let url = mediaURL(path: path, serverURL: serverURL, queryItems: [
            URLQueryItem(name: "stats", value: "client")
        ]) else {
            AppLogger.video.warning("Cannot build stream URL for videoId: \(videoId)")
            return nil
        }

        AppLogger.video.debug("Built stream URL for \(videoId)")
        return url
    }

    // MARK: - Thumbnail

    func buildThumbnailURL(for videoId: String) -> URL? {
        guard let baseURL = server.url else {
            AppLogger.video.warning("Cannot build thumbnail URL: server URL is nil")
            return nil
        }

        return Self.buildThumbnailURL(from: baseURL, videoId: videoId)
    }

    /// Authorized thumbnail URL built from the file ID. Prefer
    /// `thumbnailURL(for:serverURL:)` when a `VideoItem` is at hand: the
    /// server-provided `thumbnailUrl` is versioned and refreshes when the
    /// thumbnail changes.
    static func buildThumbnailURL(from serverURL: URL, videoId: String) -> URL? {
        guard let url = unauthorizedThumbnailURL(from: serverURL, videoId: videoId) else {
            AppLogger.video.warning("Cannot build thumbnail URL for videoId: \(videoId)")
            return nil
        }
        return authorize(url, serverURL: serverURL)
    }

    /// The thumbnail URL for a video, *without* the token: the server's
    /// versioned `thumbnailUrl` (`?v=`) resolved against `serverURL`, or the
    /// unversioned route as a fallback. Use it as a cache key (contract §6)
    /// and pass it through `authorize(_:serverURL:)` before loading.
    static func thumbnailURL(for video: VideoItem, serverURL: URL) -> URL? {
        if let thumbnailUrl = video.thumbnailUrl, !thumbnailUrl.isEmpty,
           let resolved = URL(string: thumbnailUrl, relativeTo: serverURL)?.absoluteURL {
            return resolved
        }
        return unauthorizedThumbnailURL(from: serverURL, videoId: video.fileId)
    }

    /// Ready-to-load (authorized) thumbnail URL for a video.
    static func authorizedThumbnailURL(for video: VideoItem, serverURL: URL) -> URL? {
        thumbnailURL(for: video, serverURL: serverURL).map { authorize($0, serverURL: serverURL) }
    }

    private static func unauthorizedThumbnailURL(from serverURL: URL, videoId: String) -> URL? {
        URL(string: "/api/v1/videos/\(videoId)/thumbnail", relativeTo: serverURL)?.absoluteURL
    }

    // MARK: - Scrub

    /// Authorized `GET /videos/:id/scrub/frame` URL.
    static func buildScrubFrameURL(
        from serverURL: URL,
        videoId: String,
        time: Double,
        additionalQueryItems: [URLQueryItem] = []
    ) -> URL? {
        mediaURL(
            path: "/api/v1/videos/\(videoId)/scrub/frame",
            serverURL: serverURL,
            queryItems: [URLQueryItem(name: "time", value: String(time))] + additionalQueryItems
        )
    }

    /// Authorized `GET /videos/:id/scrub/cached-times` URL.
    static func buildScrubCachedTimesURL(from serverURL: URL, videoId: String) -> URL? {
        mediaURL(path: "/api/v1/videos/\(videoId)/scrub/cached-times", serverURL: serverURL)
    }

    // MARK: - Captures

    /// Authorized `GET /captures/:captureId/image` URL.
    static func buildCaptureImageURL(from serverURL: URL, captureId: String) -> URL? {
        mediaURL(path: "/api/v1/captures/\(captureId)/image", serverURL: serverURL)
    }

    // MARK: - Authorization

    /// Appends the session token for `serverURL` (when one exists) to a media
    /// URL. Any existing `token` item is replaced. Never use it for metadata
    /// routes: the server rejects `token` there.
    static func authorize(_ url: URL, serverURL: URL) -> URL {
        guard let token = tokenProvider(serverURL), !token.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return url
        }
        var items = (components.queryItems ?? []).filter { $0.name != tokenQueryItemName }
        items.append(URLQueryItem(name: tokenQueryItemName, value: token))
        components.setQueryItemsEncodingPlus(items)
        return components.url ?? url
    }

    /// Same as `authorize(_:serverURL:)`, deriving the server from the URL.
    static func authorize(_ url: URL) -> URL {
        guard let serverURL = serverBaseURL(of: url) else { return url }
        return authorize(url, serverURL: serverURL)
    }

    /// `url` without its `token` query item — for cache keys and logs.
    static func removingToken(from url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let items = components.queryItems,
              items.contains(where: { $0.name == tokenQueryItemName }) else {
            return url
        }
        components.setQueryItemsEncodingPlus(items.filter { $0.name != tokenQueryItemName })
        return components.url ?? url
    }

    /// `scheme://host:port` of a URL.
    static func serverBaseURL(of url: URL) -> URL? {
        URL(string: ServerSessionManager.serverKey(for: url))
    }

    private static func mediaURL(path: String, serverURL: URL, queryItems: [URLQueryItem] = []) -> URL? {
        guard let base = URL(string: path, relativeTo: serverURL),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: true) else {
            return nil
        }
        var items = queryItems
        if let token = tokenProvider(serverURL), !token.isEmpty {
            items.append(URLQueryItem(name: tokenQueryItemName, value: token))
        }
        components.setQueryItemsEncodingPlus(items)
        return components.url
    }
}

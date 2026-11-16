//
//  DemoServer.swift
//  gridstream-ipad
//
//  The server of the demo mode. It answers the `/api/v1` routes the iPad
//  uses with the same wire types, status codes and error reasons as the
//  macOS routes (`gridstream-macos/.../Server/Routes`), from a `DemoStore`
//  persisted in `state.json`. Frames (scrub, captures) are extracted from
//  the pack's clips with `AVAssetImageGenerator`.
//

import Foundation
import GridStreamAPI
import OSLog

/// A response of the demo server.
nonisolated struct DemoResponse: Sendable {
    let status: Int
    let contentType: String?
    let body: Data

    static func json(_ value: some Encodable, status: Int = 200) -> DemoResponse {
        do {
            return DemoResponse(status: status, contentType: "application/json", body: try JSONEncoder.gridStream().encode(value))
        } catch {
            return .error(500, "Failed to encode the response")
        }
    }

    static func jpeg(_ data: Data) -> DemoResponse {
        DemoResponse(status: 200, contentType: "image/jpeg", body: data)
    }

    static func empty(_ status: Int) -> DemoResponse {
        DemoResponse(status: status, contentType: nil, body: Data())
    }

    /// Vapor's error body: `{"error": true, "reason": "…"}`.
    static func error(_ status: Int, _ reason: String) -> DemoResponse {
        let body = (try? JSONSerialization.data(withJSONObject: ["error": true, "reason": reason])) ?? Data()
        return DemoResponse(status: status, contentType: "application/json", body: body)
    }
}

/// A failed route: the status and the reason the macOS route returns.
nonisolated struct DemoHTTPError: Error {
    let status: Int
    let reason: String

    static func notFound(_ reason: String) -> DemoHTTPError { DemoHTTPError(status: 404, reason: reason) }
    static func badRequest(_ reason: String) -> DemoHTTPError { DemoHTTPError(status: 400, reason: reason) }
}

actor DemoServer {
    static let shared = DemoServer()

    private static let logger = Logger(subsystem: "com.gridstream.ipad", category: "DemoServer")
    /// Scrub frames are generated on request; the server caches them at 2 s.
    static let scrubFrameInterval = 2.0
    static let maxCachedFrames = 600

    private let packDirectory: URL
    private let stateURL: URL?
    let capturesDirectory: URL
    var store: DemoStore?
    var frameCache: [String: Data] = [:]
    var frameCacheOrder: [String] = []

    /// `stateURL` nil keeps the store in memory only (tests).
    init(
        packDirectory: URL = DemoPack.packDirectory,
        stateURL: URL? = DemoPack.stateURL,
        capturesDirectory: URL = DemoPack.capturesDirectory,
        store: DemoStore? = nil
    ) {
        self.packDirectory = packDirectory
        self.stateURL = stateURL
        self.capturesDirectory = capturesDirectory
        self.store = store
    }

    // MARK: - Lifecycle

    /// Forgets the loaded state; the next request reloads it from disk.
    func unload() {
        store = nil
        frameCache.removeAll()
        frameCacheOrder.removeAll()
    }

    /// Restores the pack's seed: user changes and captures are deleted. The
    /// catalog version keeps increasing, so clients notice the change.
    func reset() throws {
        let previousVersion = store?.catalogVersion ?? 0
        if let stateURL, FileManager.default.fileExists(atPath: stateURL.path) {
            try FileManager.default.removeItem(at: stateURL)
        }
        if FileManager.default.fileExists(atPath: capturesDirectory.path) {
            try FileManager.default.removeItem(at: capturesDirectory)
        }
        var seed = try loadSeed()
        seed.catalogVersion = max(seed.catalogVersion, previousVersion + 1)
        store = seed
        try persist()
    }

    private func loadSeed() throws -> DemoStore {
        let seedURL = packDirectory.appendingPathComponent("seed.json")
        guard let data = try? Data(contentsOf: seedURL) else {
            throw DemoHTTPError(status: 503, reason: "The demo is not installed.")
        }
        return try DemoStore.decode(from: data)
    }

    func loadedStore() throws -> DemoStore {
        if let store {
            return store
        }
        if let stateURL, let data = try? Data(contentsOf: stateURL),
           let saved = try? DemoStore.decode(from: data) {
            store = saved
            return saved
        }
        let seed = try loadSeed()
        store = seed
        return seed
    }

    func persist() throws {
        guard let stateURL, let store else { return }
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try store.encoded().write(to: stateURL, options: .atomic)
    }

    /// Applies a write to the store, bumps the catalog version (as
    /// `DatabaseManager.writeCatalog` does) and saves.
    func write<T>(_ change: (inout DemoStore) throws -> T) throws -> T {
        var updated = try loadedStore()
        let result = try change(&updated)
        updated.catalogVersion += 1
        store = updated
        do {
            try persist()
        } catch {
            Self.logger.error("Failed to save the demo state: \(error.localizedDescription)")
        }
        return result
    }

    // MARK: - Requests

    func handle(method: String, url: URL, body: Data?) async -> DemoResponse {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }

        let path = url.pathComponents.filter { $0 != "/" }
        guard path.count >= 2, path[0] == "api", path[1] == "v1" else {
            return .error(404, "Not Found")
        }

        do {
            return try await route(method: method.uppercased(), path: Array(path.dropFirst(2)), query: query, body: body ?? Data())
        } catch let error as DemoHTTPError {
            return .error(error.status, error.reason)
        } catch is DecodingError {
            return .error(400, "Invalid request body")
        } catch {
            return .error(500, error.localizedDescription)
        }
    }

    private func route(method: String, path: [String], query: [String: String], body: Data) async throws -> DemoResponse {
        let request = DemoRequest(method: method, path: path, query: query, body: body)
        if let response = try routeCatalog(request) { return response }
        if let response = try routeVideos(request) { return response }
        if let response = try routeTags(request) { return response }
        if let response = try routeSmartLists(request) { return response }
        if let response = try routeSimpleLists(request) { return response }
        if let response = try routeAnnotations(request) { return response }
        if let response = try routeTimeRanges(request) { return response }
        if let response = try await routeCaptures(request) { return response }
        if let response = try await routeScrub(request) { return response }
        return .error(404, "Not Found")
    }

    /// Matches `a/:b/c` against path segments; returns the `:` segments.
    static func match(_ pattern: String, _ path: [String]) -> [String]? {
        let segments = pattern.split(separator: "/").map(String.init)
        guard segments.count == path.count else { return nil }
        var params: [String] = []
        for (segment, value) in zip(segments, path) {
            if segment.hasPrefix(":") {
                params.append(value)
            } else if segment != value {
                return nil
            }
        }
        return params
    }

    // MARK: - Lookups

    func requireVideo(_ fileId: String, in store: DemoStore) throws -> DemoStore.Video {
        guard let video = store.video(fileId: fileId) else { throw DemoHTTPError.notFound("Video not found") }
        return video
    }

    func requireTag(_ id: UUID, in store: DemoStore) throws -> DemoStore.Tag {
        guard let tag = store.tag(id: id) else { throw DemoHTTPError.notFound("Tag not found") }
        return tag
    }

    func requireSimpleList(_ id: UUID, in store: DemoStore) throws -> DemoStore.SimpleList {
        guard let list = store.simpleLists.first(where: { $0.id == id }) else {
            throw DemoHTTPError.notFound("Simple list not found")
        }
        return list
    }

    /// Pack files resolved against this server's pack folder (tests use
    /// their own folder; the app's matches `DemoPack`).
    func clipFile(_ fileId: String) -> URL? {
        existing(packDirectory.appendingPathComponent("clips/\(fileId).mp4"))
    }

    func thumbnailFile(_ fileId: String) -> URL? {
        existing(packDirectory.appendingPathComponent("thumbnails/\(fileId).jpg"))
    }

    private func existing(_ url: URL) -> URL? {
        FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Parsing and validation

    func decode<T: Decodable>(_ type: T.Type, _ body: Data) throws -> T {
        try JSONDecoder.gridStream().decode(type, from: body)
    }

    static func uuid(_ value: String, label: String) throws -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            throw DemoHTTPError.badRequest("Invalid \(label) ID format")
        }
        return uuid
    }

    static func uuidList(_ value: String?) -> [UUID] {
        value?.split(separator: ",").compactMap { UUID(uuidString: String($0)) } ?? []
    }

    static func int(_ value: String?) -> Int? {
        value.flatMap { Int($0) }
    }

    static func bool(_ value: String?) -> Bool? {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }

    /// `uuid:min-max,uuid:min-max`, either bound may be empty.
    static func tagRatings(_ value: String?) -> [(tagId: UUID, minRating: Int?, maxRating: Int?)] {
        guard let value, !value.isEmpty else { return [] }
        return value.split(separator: ",").compactMap { component in
            let parts = component.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let tagId = UUID(uuidString: String(parts[0])) else { return nil }
            let bounds = parts[1].split(separator: "-", omittingEmptySubsequences: false)
            let minRating = bounds.first.flatMap { Int($0) }
            let maxRating = bounds.count >= 2 ? Int(bounds[1]) : nil
            return (tagId, minRating, maxRating)
        }
    }

    static func validateRating(_ rating: Int) throws {
        guard (0...10).contains(rating) else { throw DemoHTTPError.badRequest("Rating must be between 0 and 10") }
    }

    static func validateColor(_ color: String) throws {
        guard TagColorPalette.isValidColor(color) else {
            throw DemoHTTPError.badRequest("Invalid color. Must be one of: \(TagColorPalette.allColors.joined(separator: ", "))")
        }
    }

    static func normalizedName(_ name: String, kind: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DemoHTTPError.badRequest("\(kind) name cannot be empty.") }
        return trimmed.lowercased()
    }

    static func canonicalCriteria(_ json: String) throws -> String {
        do {
            return try SmartListCriteria.parseValidated(json: json).canonicalJSON()
        } catch let error as CriteriaValidationError {
            throw DemoHTTPError.badRequest(error.reason)
        }
    }

    static func canonicalSortOrder(_ value: String) throws -> String {
        guard let canonical = SimpleListSortOrder.canonical(value) else {
            throw DemoHTTPError.badRequest(
                "Invalid sortOrder '\(value)'. Must be one of: \(SimpleListSortOrder.canonicalValues.joined(separator: ", "))"
            )
        }
        return canonical
    }
}

nonisolated struct DemoRequest: Sendable {
    let method: String
    let path: [String]
    let query: [String: String]
    let body: Data

    func on(_ expectedMethod: String, _ pattern: String) -> [String]? {
        guard method == expectedMethod else { return nil }
        return DemoServer.match(pattern, path)
    }
}

//
//  VideoStreamRoutes.swift
//  gridstream-macos
//
//  Streaming endpoint. Registered behind SessionAuthMiddleware(allowQueryToken: true):
//  AVPlayer passes the session as the `token` query item.
//

import Foundation
import GridStreamAPI
import Vapor

nonisolated struct VideoStreamRoutes: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let api = routes.grouped("api", "v1")
        let videos = api.grouped("videos")

        videos.get(":id", "stream", use: streamVideo)
    }

    @Sendable
    private func streamVideo(req: Request) async throws -> Response {
        let fileId = try req.requireParameter("id", reason: "Missing video ID")

        let catalog = try req.catalogProvider()
        let snapshot = catalog.getSnapshot()

        guard let video = snapshot.videos.first(where: { $0.fileId == fileId }) else {
            throw Abort(.notFound, reason: "Video not found")
        }

        guard isSafeRelativePath(video.relativePath) else {
            throw Abort(.forbidden, reason: "Invalid file path")
        }

        guard let sourceDirectory = snapshot.sourceDirectories.first(where: { $0.id == video.sourceDirectoryId }) else {
            throw Abort(.internalServerError, reason: "Source directory not found")
        }

        let sourceURL = URL(fileURLWithPath: sourceDirectory.path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let fileURL = sourceURL
            .appendingPathComponent(video.relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()

        guard isFileURL(fileURL, containedIn: sourceURL) else {
            throw Abort(.forbidden, reason: "Video file is outside the source directory")
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw Abort(.notFound, reason: "Video file not found on disk")
        }

        if req.query[String.self, at: "stats"] != "client" {
            let clientIP = req.remoteAddress?.ipAddress ?? "unknown"
            await StreamSessionTracker.shared.recordStreamActivity(fileId: fileId, clientIP: clientIP)
        }

        // Vapor rejects a Range past the end of the file with 400: clamp it,
        // or answer 416 when nothing of it can be satisfied
        if let range = req.headers.range,
           let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.intValue {
            switch Self.normalizedRange(range, fileSize: size) {
            case .unchanged:
                break
            case .replaced(let normalized):
                req.headers.range = normalized
            case .unsatisfiable:
                var headers = HTTPHeaders()
                headers.replaceOrAdd(name: .contentRange, value: "bytes */\(size)")
                return Response(status: .rangeNotSatisfiable, headers: headers)
            }
        }

        let contentType = Self.contentTypeForExtension(video.filename)
        let response = try await req.fileio.asyncStreamFile(at: fileURL.path, mediaType: contentType)
        if let monitor = req.application.connectionMonitor {
            Self.meterBody(of: response, path: fileURL.path, video: video, monitor: monitor, req: req)
        }
        return response
    }

    /// Rewrites the body Vapor built as the same read of the file, counting
    /// the bytes as the client takes them so the activity pane shows the real
    /// throughput (AVPlayer often asks for the rest of the file, then cancels).
    private static func meterBody(
        of response: Response,
        path: String,
        video: VideoItem,
        monitor: ConnectionMonitor,
        req: Request
    ) {
        let byteCount = response.body.count
        guard byteCount > 0 else { return }

        let offset: Int
        switch (response.status, response.headers.contentRange?.range) {
        case (.ok, _):
            offset = 0
        case (.partialContent, .within(let start, _)?), (.partialContent, .withinWithLimit(let start, _, _)?):
            offset = start
        default:
            return
        }

        let fileio = req.fileio
        let address = req.clientAddress
        let userAgent = req.userAgent
        let fileId = video.fileId
        let filename = video.filename
        response.body = .init(asyncStream: { writer in
            let meter = monitor.openStream(from: address, userAgent: userAgent, fileId: fileId, filename: filename)
            defer { meter.close() }
            do {
                let chunks = try await fileio.readFile(at: path, offset: Int64(offset), byteCount: byteCount)
                do {
                    for try await chunk in chunks {
                        let size = chunk.readableBytes
                        try await writer.writeBuffer(chunk)
                        meter.add(size)
                    }
                    try? await chunks.closeHandle()
                } catch {
                    try? await chunks.closeHandle()
                    throw error
                }
                try await writer.write(.end)
            } catch {
                try? await writer.write(.error(error))
            }
        }, count: byteCount, byteBufferAllocator: req.byteBufferAllocator)
        req.storage[MeteredStreamStorageKey.self] = true
    }

    enum RangeNormalization: Equatable {
        case unchanged
        case replaced(HTTPHeaders.Range)
        case unsatisfiable
    }

    /// Clamps a single byte range to the file (RFC 9110 §14.1.2): an end past
    /// the last byte is truncated, a start past it is unsatisfiable. Multi-range
    /// and non-byte requests are left to Vapor (it serves the whole file).
    nonisolated static func normalizedRange(_ range: HTTPHeaders.Range, fileSize size: Int) -> RangeNormalization {
        guard range.unit == .bytes, range.ranges.count == 1, let value = range.ranges.first else {
            return .unchanged
        }

        let normalized: HTTPHeaders.Range.Value
        switch value {
        case .start(let start):
            guard start >= 0, start < size else { return .unsatisfiable }
            normalized = .start(value: start)
        case .tail(let length):
            guard length > 0, size > 0 else { return .unsatisfiable }
            normalized = .tail(value: min(length, size))
        case .within(let start, let end):
            guard start >= 0, start <= end, start < size else { return .unsatisfiable }
            normalized = .within(start: start, end: min(end, size - 1))
        }

        return normalized == value ? .unchanged : .replaced(HTTPHeaders.Range(unit: .bytes, ranges: [normalized]))
    }

    private func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else {
            return false
        }

        let components = path.components(separatedBy: "/")
        return !components.contains("..")
    }

    private func isFileURL(_ fileURL: URL, containedIn sourceURL: URL) -> Bool {
        let sourcePath = sourceURL.path.hasSuffix("/") ? sourceURL.path : sourceURL.path + "/"
        return fileURL.path == sourceURL.path || fileURL.path.hasPrefix(sourcePath)
    }

    nonisolated static func contentTypeForExtension(_ filename: String) -> HTTPMediaType {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "m4v":
            return HTTPMediaType(type: "video", subType: "mp4")
        case "mov":
            return HTTPMediaType(type: "video", subType: "quicktime")
        case "webm":
            return HTTPMediaType(type: "video", subType: "webm")
        default:
            return HTTPMediaType(type: "application", subType: "octet-stream")
        }
    }
}

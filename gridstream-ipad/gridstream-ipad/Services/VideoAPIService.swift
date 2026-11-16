//
//  VideoAPIService.swift
//  gridstream-ipad
//

import Foundation
import GridStreamAPI
import os

/// Service for fetching video catalog from the server
@MainActor
final class VideoAPIService {
    private let sessionManager: ServerSessionManager

    init(sessionManager: ServerSessionManager? = nil) {
        self.sessionManager = sessionManager ?? .shared
    }

    // Explicit teardown avoids the isolated-deinit back-deploy shim when
    // SwiftUI releases this service outside a Swift task.
    deinit {}

    private func api(_ serverURL: URL) -> APIClient {
        APIClient(serverURL: serverURL, session: sessionManager)
    }

    /// Fetch all videos from the server
    func fetchVideos(from serverURL: URL) async throws -> [VideoItem] {
        AppLogger.video.debug("Fetching videos from \(serverURL.absoluteString)")
        let videosResponse = try await api(serverURL).fetch(PaginatedVideosResponse.self, "videos")
        AppLogger.video.info("Fetched \(videosResponse.videos.count) videos from server")
        return videosResponse.videos
    }

    /// Captures a frame from a video at the specified timestamp
    func captureFrame(fileId: String, timestamp: Double, serverURL: URL) async throws -> FrameCaptureDTO {
        AppLogger.video.debug("Capturing frame for \(fileId) at \(timestamp)s")
        let captureResponse = try await api(serverURL).fetch(
            FrameCaptureDTO.self, .post, "videos/\(fileId)/captures",
            body: CreateFrameCaptureRequest(timestamp: timestamp), expecting: [201]
        )
        AppLogger.video.info("Captured frame \(captureResponse.id) at \(timestamp)s: \(captureResponse.width)x\(captureResponse.height)")
        return captureResponse
    }

    /// Fetches all captures for a video
    func fetchCaptures(fileId: String, serverURL: URL) async throws -> [FrameCaptureDTO] {
        AppLogger.video.debug("Fetching captures for \(fileId)")
        let listResponse = try await api(serverURL).fetch(FrameCaptureListResponse.self, "videos/\(fileId)/captures")
        AppLogger.video.info("Fetched \(listResponse.captures.count) captures for \(fileId)")
        return listResponse.captures
    }

    /// Deletes a capture by ID
    func deleteCapture(captureId: String, serverURL: URL) async throws {
        AppLogger.video.debug("Deleting capture \(captureId)")
        try await api(serverURL).send(.delete, "captures/\(captureId)", expecting: [204])
        AppLogger.video.info("Deleted capture \(captureId)")
    }

    /// Probes whether the server still recognizes the given file ID.
    /// Used by the cold-start restore to detect videos that have been
    /// removed from the catalog while the app was killed.
    ///
    /// Uses `GET /videos/by-file-id/:fileId` (contract §5): 200 = present,
    /// 404 = absent. Anything else (401, 5xx, network failure) is treated
    /// as "still valid" so we don't drop a tile binding because of a
    /// transient outage. (`HEAD /videos/:fileId` hit a UUID route and its
    /// 400 was read as "present".)
    func checkVideoExists(fileId: String, serverURL: URL) async -> Bool {
        let client = api(serverURL)
        do {
            let request = try client.request(.get, "videos/by-file-id/\(fileId)", timeout: 4)
            let (_, response) = try await client.response(for: request)
            return response.statusCode != 404
        } catch {
            AppLogger.video.warning("checkVideoExists transient failure for \(fileId): \(error.localizedDescription)")
            return true
        }
    }
}

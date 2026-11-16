//
//  ThumbnailPrefetcher.swift
//  gridstream-ipad
//
//  Handles progressive batched loading of video thumbnails with prioritization.
//

import UIKit
import OSLog

/// Manages progressive thumbnail loading with batched requests and prioritization.
/// Thumbnails are loaded in small batches to provide smooth progressive loading.
@MainActor
@Observable
final class ThumbnailPrefetcher {

    /// Shared singleton instance
    static let shared = ThumbnailPrefetcher()

    /// Number of concurrent thumbnail downloads (matches URLSession connection pool)
    private static let batchSize = 8

    /// Cache reference
    private let cache = ThumbnailCache.shared

    /// Queue of pending thumbnail requests
    private var pendingQueue: [ThumbnailRequest] = []

    /// Cache keys currently being loaded
    private var loadingSet: Set<String> = []

    /// Callbacks waiting for specific thumbnails, keyed by cache key
    private var callbacks: [String: [(UIImage?) -> Void]] = [:]

    /// Whether the prefetcher is currently processing
    private var isProcessing = false

    /// Published state for tracking loading progress
    private(set) var loadedCount: Int = 0
    private(set) var totalRequested: Int = 0

    private init() {}

    // MARK: - Keys

    /// Cache key for a thumbnail URL: the URL without its auth token, so a
    /// new session doesn't invalidate the cache, while the server's `?v=`
    /// version still does (contract §6).
    static func cacheKey(for url: URL) -> String {
        VideoURLBuilder.removingToken(from: url).absoluteString
    }

    // MARK: - Public API

    /// Requests a thumbnail, using the cache if available.
    /// - Parameters:
    ///   - url: The thumbnail URL from `VideoURLBuilder.thumbnailURL(for:serverURL:)`
    ///   - priority: Whether this is a high-priority (visible) request
    ///   - completion: Called with the loaded image or nil
    func requestThumbnail(
        for url: URL,
        priority: RequestPriority = .normal,
        completion: @escaping (UIImage?) -> Void
    ) {
        let key = Self.cacheKey(for: url)

        // Check cache first
        if let cached = cache.thumbnail(for: key) {
            completion(cached)
            return
        }

        // Already loading - add to callbacks
        if loadingSet.contains(key) {
            callbacks[key, default: []].append(completion)
            return
        }

        // Check if already queued
        if let existingIndex = pendingQueue.firstIndex(where: { $0.key == key }) {
            // Update priority if higher
            if priority == .high && pendingQueue[existingIndex].priority != .high {
                let existing = pendingQueue.remove(at: existingIndex)
                pendingQueue.insert(ThumbnailRequest(key: key, url: existing.url, priority: .high), at: 0)
            }
            callbacks[key, default: []].append(completion)
            return
        }

        // Add to queue
        let request = ThumbnailRequest(key: key, url: url, priority: priority)
        if priority == .high {
            pendingQueue.insert(request, at: 0)
        } else {
            pendingQueue.append(request)
        }
        callbacks[key, default: []].append(completion)
        totalRequested += 1

        // Start processing if not already
        processNextBatch()
    }

    /// Cancels a pending thumbnail request.
    func cancel(url: URL) {
        let key = Self.cacheKey(for: url)
        pendingQueue.removeAll { $0.key == key }
        callbacks.removeValue(forKey: key)
    }

    // MARK: - Private Processing

    private func processNextBatch() {
        guard !isProcessing else { return }
        guard !pendingQueue.isEmpty else { return }

        isProcessing = true

        // Take next batch
        let batchSize = min(Self.batchSize, pendingQueue.count)
        let batch = Array(pendingQueue.prefix(batchSize))
        pendingQueue.removeFirst(batchSize)

        // Mark as loading; authorize with the current session token.
        let jobs = batch.map { request -> (key: String, url: URL) in
            loadingSet.insert(request.key)
            return (request.key, VideoURLBuilder.authorize(request.url))
        }
        let session = ServerSessionManager.shared.urlSession

        // Load batch concurrently
        Task {
            await withTaskGroup(of: (String, UIImage?).self) { group in
                for job in jobs {
                    group.addTask {
                        let image = await Self.loadThumbnail(from: job.url, session: session)
                        return (job.key, image)
                    }
                }

                for await (key, image) in group {
                    self.handleLoadComplete(key: key, image: image)
                }
            }

            self.isProcessing = false
            self.processNextBatch()
        }
    }

    private nonisolated static func loadThumbnail(from url: URL, session: URLSession) async -> UIImage? {
        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    private func handleLoadComplete(key: String, image: UIImage?) {
        loadingSet.remove(key)
        loadedCount += 1

        // Cache the image
        if let image = image {
            cache.setThumbnail(image, for: key)
        }

        // Notify callbacks
        if let waitingCallbacks = callbacks.removeValue(forKey: key) {
            for callback in waitingCallbacks {
                callback(image)
            }
        }
    }

    // MARK: - Types

    /// Priority level for thumbnail requests
    enum RequestPriority {
        case high   // Visible cells - load first
        case normal // Prefetch - load when bandwidth available
    }

    /// Internal request representation
    private struct ThumbnailRequest {
        /// Cache key (URL without the auth token)
        let key: String
        /// Unauthorized thumbnail URL
        let url: URL
        let priority: RequestPriority
    }
}

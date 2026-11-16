//
//  ThumbnailCache.swift
//  gridstream-ipad
//
//  In-memory cache for video thumbnails with automatic eviction under memory pressure.
//

import UIKit
import OSLog

/// Thread-safe in-memory cache for video thumbnails.
/// Uses NSCache for automatic memory management and eviction.
// Sendable: NSCache is internally thread-safe. No additional mutable state.
final class ThumbnailCache: @unchecked Sendable {

    /// Shared singleton instance
    static let shared = ThumbnailCache()

    /// The underlying cache storage
    private let cache = NSCache<NSString, UIImage>()

    /// Logger for cache operations
    private let logger = Logger(subsystem: "com.gridstream.ipad", category: "ThumbnailCache")

    /// Approximate memory limit for cached thumbnails (30MB)
    /// At ~20KB per thumbnail, this allows ~1500 cached thumbnails
    private static let memoryCostLimit = 30 * 1024 * 1024

    /// Maximum number of cached items
    private static let countLimit = 2000

    private init() {
        cache.totalCostLimit = Self.memoryCostLimit
        cache.countLimit = Self.countLimit
        cache.name = "ThumbnailCache"

        // Listen for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        logger.info("ThumbnailCache initialized with \(Self.memoryCostLimit / 1024 / 1024)MB limit")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API

    /// Retrieves a cached thumbnail for the given key.
    /// - Parameter key: The cache key (thumbnail URL without the auth token)
    /// - Returns: The cached UIImage, or nil if not cached
    func thumbnail(for key: String) -> UIImage? {
        let key = key as NSString
        return cache.object(forKey: key)
    }

    /// Stores a thumbnail in the cache.
    /// - Parameters:
    ///   - image: The thumbnail image to cache
    ///   - key: The cache key (thumbnail URL without the auth token)
    func setThumbnail(_ image: UIImage, for key: String) {
        let key = key as NSString
        // Estimate cost based on image dimensions (RGBA bytes)
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key, cost: cost)
    }

    /// Clears all cached thumbnails.
    func clearAll() {
        cache.removeAllObjects()
        logger.info("ThumbnailCache cleared")
    }

    // MARK: - Memory Management

    @objc private func handleMemoryWarning() {
        logger.warning("Memory warning received, clearing thumbnail cache")
        clearAll()
    }
}

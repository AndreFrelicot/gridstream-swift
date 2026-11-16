//
//  AppState.swift
//  gridstream-macos
//
//  Central state coordinator for the GridStream application.
//  Note: The actual state coordination is implemented in GridStreamApp.swift using
//  @StateObject and @State properties. This file provides the AppState type
//  as a facade for accessing the coordinated state from views and other components.
//

import Foundation
import OSLog

/// Provides centralized logging for app-wide state operations.
enum AppStateLogger {
    private static let logger = Logger(subsystem: "com.gridstream.macos", category: "AppState")

    /// Logs the completion of a video scan with statistics.
    /// - Parameters:
    ///   - videosFound: Number of videos successfully extracted
    ///   - totalFilesScanned: Total number of video files that were scanned
    ///   - directoryCount: Number of directories that were scanned
    ///   - duration: Time taken for the scan in seconds
    static func logScanCompletion(
        videosFound: Int,
        totalFilesScanned: Int,
        directoryCount: Int,
        duration: TimeInterval
    ) {
        logger.info("Scan completed: \(videosFound) videos from \(totalFilesScanned) files in \(directoryCount) directories (\(String(format: "%.2f", duration))s)")
    }

    /// Logs when the video catalog is updated.
    /// - Parameter count: Number of videos in the updated catalog
    static func logCatalogUpdate(count: Int) {
        logger.info("Video catalog updated: \(count) videos")
    }

    /// Logs when a rescan is initiated.
    /// - Parameter directoryCount: Number of enabled directories to scan
    static func logRescanStarted(directoryCount: Int) {
        logger.info("Rescan started: \(directoryCount) enabled directories")
    }
}

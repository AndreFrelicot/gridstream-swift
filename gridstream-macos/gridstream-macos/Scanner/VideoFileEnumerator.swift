import Foundation
import OSLog

/// Filesystem enumeration only. Catalog reconciliation belongs to VideoScanner.
nonisolated enum VideoFileEnumerator {
    typealias FileEntry = (url: URL, sourceDirectory: SourceDirectory)
    private static let supportedExtensions: Set<String> = ["mp4", "m4v", "mov"]
    private static let logger = Logger(subsystem: "com.gridstream.macos", category: "VideoScanner")

    /// With nested source folders a file is listed once per enclosing folder.
    /// Keep a single entry per file, owned by the deepest (most specific)
    /// folder, so its record and relativePath are computed against one folder.
    static func assigningFilesToDeepestDirectory(_ files: [FileEntry]) -> [FileEntry] {
        var ownerByPath: [String: FileEntry] = [:]
        var order: [String] = []
        for entry in files {
            let key = canonicalPath(for: entry.url)
            if let current = ownerByPath[key] {
                if entry.sourceDirectory.path.count > current.sourceDirectory.path.count {
                    ownerByPath[key] = entry
                }
            } else {
                ownerByPath[key] = entry
                order.append(key)
            }
        }
        return order.compactMap { ownerByPath[$0] }
    }

    /// True when `path` exists, is a directory and can be listed.
    static func isReadableDirectory(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: path) else {
            return false
        }
        // A TCC denial or an unmounted volume surfaces here even when the
        // checks above succeed.
        return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
    }

    struct DirectoryListing {
        var files: [FileEntry] = []
        var hadErrors = false
    }

    static func findVideoFiles(
        in directoryURL: URL,
        sourceDirectory: SourceDirectory
    ) -> DirectoryListing {
        var listing = DirectoryListing()

        let fileManager = FileManager.default
        let errorFlag = EnumerationErrorFlag()

        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: { url, error in
                errorFlag.set()
                Logger(subsystem: "com.gridstream.macos", category: "VideoScanner")
                    .warning("Enumeration error at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return true
            }
        ) else {
            logger.warning("Failed to create enumerator for directory: \(directoryURL.path)")
            listing.hadErrors = true
            return listing
        }

        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])

                guard resourceValues.isRegularFile == true else {
                    continue
                }

                let fileExtension = fileURL.pathExtension.lowercased()

                guard Self.supportedExtensions.contains(fileExtension) else {
                    continue
                }

                // Skip scrub video files (they are stored alongside source videos)
                let filename = fileURL.lastPathComponent
                if filename.hasPrefix("scrub-") {
                    continue
                }

                // Skip files below minimum size threshold for hashing (192KB)
                if let fileSize = resourceValues.fileSize, Int64(fileSize) < FileHasher.minimumFileSize {
                    continue
                }

                listing.files.append((url: fileURL, sourceDirectory: sourceDirectory))
            } catch {
                logger.warning("Failed to get resource values for \(fileURL.path): \(error.localizedDescription)")
                listing.hadErrors = true
            }
        }

        if errorFlag.isSet {
            listing.hadErrors = true
        }

        return listing
    }

    static func canonicalPath(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}

/// Thread-safe flag set from `FileManager.enumerator`'s error handler.
private nonisolated final class EnumerationErrorFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

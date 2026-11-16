import Foundation
import GRDB
import GridStreamAPI
import OSLog

nonisolated struct ScanProgress {
    let currentFile: String
    let filesScanned: Int
    let totalFiles: Int
}

actor VideoScanner {
    private let logger = Logger(subsystem: "com.gridstream.macos", category: "VideoScanner")
    private let metadataExtractor = MetadataExtractor()
    private let fileHasher = FileHasher()
    private let thumbnailGenerator = ThumbnailGenerator()
    private let databaseManager: DatabaseManager

    /// Source folders that the last scan could not read (missing, unreadable,
    /// or empty while the database still holds videos for them). Their records
    /// are left untouched until the folder becomes available again.
    private(set) var unavailableDirectoryIds: Set<UUID> = []

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    // MARK: - Cached Videos Loading

    /// Fetches all VideoFileRecords from the database and converts them to VideoItems.
    /// Used for instant startup to display cached videos before any scan.
    /// Returns cached videos immediately (before any scan).
    /// Handles empty database case gracefully.
    func loadCachedVideos(sourceDirectories: [SourceDirectory]) async throws -> [VideoItem] {
        let enabledDirectoryIds = Set(sourceDirectories.filter { $0.isEnabled }.map { $0.id })
        let directoryPathById = Dictionary(
            sourceDirectories.map { ($0.id, $0.path) },
            uniquingKeysWith: { first, _ in first }
        )

        let records = try await databaseManager.read { db in
            try VideoFileRecord.fetchAllRecords(in: db)
        }

        // Only present files from enabled source directories are in the catalog
        let filteredRecords = records.filter {
            enabledDirectoryIds.contains($0.sourceDirectoryId) && $0.missingSince == nil
        }

        logger.info("Loaded \(filteredRecords.count) cached videos from database")

        return filteredRecords.compactMap { record in
            guard let sourceDirectoryPath = directoryPathById[record.sourceDirectoryId] else {
                logger.warning("Skipping cached video with missing source directory: \(record.fileId)")
                return nil
            }

            return videoItem(
                from: record,
                relativePath: Self.relativePath(for: URL(fileURLWithPath: record.path), sourceDirectoryPath: sourceDirectoryPath)
            )
        }
    }

    // MARK: - Directory Enumeration

    private typealias FileEntry = VideoFileEnumerator.FileEntry

    /// Outcome of enumerating the enabled source folders.
    private struct EnumerationResult {
        /// Video files found in available folders.
        var files: [FileEntry] = []
        /// Canonical paths of every video file found on disk, whether or not it
        /// can be analysed. A path in this set is never soft-deleted.
        var presentPaths: Set<String> = []
        /// Folders whose records can be reconciled against the files found
        /// (readable, enumerated without error, not suspiciously empty).
        var reconcilableDirectoryIds: Set<UUID> = []
        /// Folders skipped entirely; their records are kept as they are.
        var unavailableDirectories: [SourceDirectory] = []
    }

    private func enumerateSourceDirectories(_ directories: [SourceDirectory]) async throws -> EnumerationResult {
        var result = EnumerationResult()

        for directory in directories {
            guard Self.isReadableDirectory(atPath: directory.path) else {
                logger.warning("Source folder unavailable (missing or unreadable), keeping its records: \(directory.path, privacy: .public)")
                result.unavailableDirectories.append(directory)
                continue
            }

            let enumeration = VideoFileEnumerator.findVideoFiles(in: URL(fileURLWithPath: directory.path), sourceDirectory: directory)

            if enumeration.files.isEmpty {
                let knownCount = try await databaseManager.read { db in
                    try VideoFileRecord
                        .filter(Column("source_directory_id") == directory.id)
                        .filter(Column("missing_since") == nil)
                        .fetchCount(db)
                }
                if knownCount > 0 {
                    logger.warning("Source folder \(directory.path, privacy: .public) lists no videos but the database has \(knownCount) for it; treating it as unavailable")
                    result.unavailableDirectories.append(directory)
                    continue
                }
            }

            result.files.append(contentsOf: enumeration.files)
            for file in enumeration.files {
                result.presentPaths.insert(Self.canonicalPath(for: file.url))
            }

            if enumeration.hadErrors {
                logger.warning("Errors while listing \(directory.path, privacy: .public); missing files in it will not be soft-deleted this scan")
            } else {
                result.reconcilableDirectoryIds.insert(directory.id)
            }
        }

        result.files = VideoFileEnumerator.assigningFilesToDeepestDirectory(result.files)
        unavailableDirectoryIds = Set(result.unavailableDirectories.map(\.id))
        return result
    }

    nonisolated static func isReadableDirectory(atPath path: String) -> Bool {
        VideoFileEnumerator.isReadableDirectory(atPath: path)
    }

    /// Converts the live records of skipped folders into catalog items so the
    /// catalog keeps showing them while the folder is unavailable.
    private func itemsForUnavailableDirectories(_ directories: [SourceDirectory]) async throws -> [VideoItem] {
        guard !directories.isEmpty else { return [] }
        var items: [VideoItem] = []
        for directory in directories {
            let records = try await databaseManager.read { db in
                try VideoFileRecord
                    .filter(Column("source_directory_id") == directory.id)
                    .filter(Column("missing_since") == nil)
                    .fetchAll(db)
            }
            items.append(contentsOf: records.map { record in
                videoItem(
                    from: record,
                    relativePath: Self.relativePath(for: URL(fileURLWithPath: record.path), sourceDirectoryPath: directory.path)
                )
            })
        }
        return items
    }

    // MARK: - Scan Serialization

    /// Tail of the chain of scans. Scans never interleave: the actor is
    /// reentrant across `await`, so two concurrent scans would otherwise race on
    /// UNIQUE(file_id) and reconcile against each other's half-finished state.
    private var scanChain: Task<Void, Never>?

    /// Runs `operation` after every previously requested scan has finished.
    /// Cancelling the caller cancels its own scan only.
    private func serialized(
        _ operation: @escaping @Sendable () async throws -> [VideoItem]
    ) async throws -> [VideoItem] {
        let previous = scanChain
        let task = Task<[VideoItem], Error> {
            await previous?.value
            try Task.checkCancellation()
            return try await operation()
        }
        scanChain = Task { _ = await task.result }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: - Incremental Scanning

    func scan(
        directories: [SourceDirectory],
        progressHandler: (@Sendable (ScanProgress) -> Void)? = nil
    ) async throws -> [VideoItem] {
        try await serialized {
            try await self.performIncrementalScan(directories: directories, progressHandler: progressHandler)
        }
    }

    private func performIncrementalScan(
        directories: [SourceDirectory],
        progressHandler: (@Sendable (ScanProgress) -> Void)?
    ) async throws -> [VideoItem] {
        let enabledDirectories = directories.filter { $0.isEnabled }

        guard !enabledDirectories.isEmpty else {
            logger.info("No enabled directories to scan")
            unavailableDirectoryIds = []
            return []
        }

        // Build a cache of existing records from the database for incremental detection
        let existingRecordsByPath = try await buildExistingRecordsCache(
            sourceDirectoryIds: Set(enabledDirectories.map { $0.id })
        )

        let enumeration = try await enumerateSourceDirectories(enabledDirectories)
        let allVideoFiles = enumeration.files

        logger.info("Found \(allVideoFiles.count) video files to scan")

        var videoItems: [VideoItem] = []
        let totalFiles = allVideoFiles.count
        var changesDetected = false

        for (index, fileInfo) in allVideoFiles.enumerated() {
            try Task.checkCancellation()

            let filename = fileInfo.url.lastPathComponent

            progressHandler?(ScanProgress(
                currentFile: filename,
                filesScanned: index,
                totalFiles: totalFiles
            ))

            let result = try await processVideoFileIncremental(
                url: fileInfo.url,
                sourceDirectory: fileInfo.sourceDirectory,
                existingRecordsByPath: existingRecordsByPath
            )

            if let videoItem = result.videoItem {
                videoItems.append(videoItem)
            }

            if result.wasChanged {
                changesDetected = true
            }
        }

        progressHandler?(ScanProgress(
            currentFile: "",
            filesScanned: totalFiles,
            totalFiles: totalFiles
        ))

        videoItems.append(contentsOf: try await itemsForUnavailableDirectories(enumeration.unavailableDirectories))

        let missingCount = try await markMissingRecords(
            presentPaths: enumeration.presentPaths,
            sourceDirectoryIds: enumeration.reconcilableDirectoryIds
        )

        if missingCount > 0 {
            logger.info("Marked \(missingCount) videos as missing")
            changesDetected = true
        }

        // Update catalog version if any changes were detected
        if changesDetected {
            try await databaseManager.updateCatalogVersion()
            logger.info("Catalog version updated due to detected changes")
        }

        logger.info("Scan complete: \(videoItems.count) videos extracted from \(totalFiles) files")

        return videoItems
    }

    /// Builds a cache of existing records (soft-deleted ones included, so a file
    /// that reappears at the same path is restored) indexed by path.
    private func buildExistingRecordsCache(
        sourceDirectoryIds: Set<UUID>
    ) async throws -> [String: VideoFileRecord] {
        let allRecords = try await databaseManager.read { db in
            var records: [VideoFileRecord] = []
            for sourceDirectoryId in sourceDirectoryIds {
                let sourceRecords = try VideoFileRecord.findBySourceDirectoryId(sourceDirectoryId, in: db)
                records.append(contentsOf: sourceRecords)
            }
            return records
        }

        return Dictionary(allRecords.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Result of processing a video file incrementally.
    private struct ProcessResult {
        let videoItem: VideoItem?
        let wasChanged: Bool
    }

    /// Processes a video file with incremental change detection.
    /// - Before computing fileId/metadata, checks if file exists in database by path.
    /// - Compares file's current lastModified with stored lastModified.
    /// - If timestamps match, skips metadata extraction and thumbnail generation.
    /// - If timestamps differ, re-extracts metadata and updates record. When the
    ///   analysis fails the existing record is kept unchanged.
    /// - Only computes fileId for truly new files.
    private func processVideoFileIncremental(
        url: URL,
        sourceDirectory: SourceDirectory,
        existingRecordsByPath: [String: VideoFileRecord]
    ) async throws -> ProcessResult {
        let filePath = url.path

        guard let existingRecord = existingRecordsByPath[filePath] else {
            // New file - compute fileId and extract metadata
            do {
                return try await processNewVideoFile(url: url, sourceDirectory: sourceDirectory)
            } catch {
                logger.warning("Failed to process \(url.lastPathComponent): \(error.localizedDescription)")
                return ProcessResult(videoItem: nil, wasChanged: false)
            }
        }

        let relativePath = Self.relativePath(for: url, sourceDirectoryPath: sourceDirectory.path)
        let restored = try await restoreIfNeeded(existingRecord, sourceDirectory: sourceDirectory)

        // Get the file's current modification date
        let currentLastModified: Double
        do {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: filePath)
            let currentModificationDate = (fileAttributes[.modificationDate] as? Date) ?? Date()
            currentLastModified = currentModificationDate.timeIntervalSince1970
        } catch {
            logger.warning("Failed to read attributes of \(url.lastPathComponent), keeping its record: \(error.localizedDescription)")
            return ProcessResult(videoItem: videoItem(from: restored, relativePath: relativePath), wasChanged: restored.missingSince != existingRecord.missingSince)
        }

        let wasRestored = existingRecord.missingSince != nil || existingRecord.sourceDirectoryId != sourceDirectory.id

        // Compare lastModified timestamps
        if abs(existingRecord.lastModified - currentLastModified) < 1.0 {
            // File is unchanged - skip metadata extraction and thumbnail generation
            logger.debug("Skipping unchanged file: \(url.lastPathComponent)")
            return ProcessResult(videoItem: videoItem(from: restored, relativePath: relativePath), wasChanged: wasRestored)
        }

        // File was modified - re-extract metadata and update record
        logger.info("File modified, re-processing: \(url.lastPathComponent)")

        let metadata: VideoMetadata
        do {
            metadata = try await metadataExtractor.extract(from: url)
        } catch {
            // Never drop or rewrite a record because AVFoundation could not read the file
            logger.warning("Failed to analyse modified file \(url.lastPathComponent), keeping its record unchanged: \(error.localizedDescription)")
            return ProcessResult(videoItem: videoItem(from: restored, relativePath: relativePath), wasChanged: wasRestored)
        }

        let now = Date().timeIntervalSince1970
        let recordId = existingRecord.id
        let fileId = existingRecord.fileId
        let sourceDirectoryId = sourceDirectory.id
        let filename = url.lastPathComponent
        // Re-encoded in place: the fileId is kept, but scrub frames of the old content are stale
        let contentChanged = metadata.fileSize != existingRecord.fileSize
            || abs(metadata.duration - existingRecord.duration) > 0.01
        let updatedRecord = try await databaseManager.write { db -> VideoFileRecord? in
            try VideoFileRecord.updateScannedMetadata(
                id: recordId,
                path: filePath,
                sourceDirectoryId: sourceDirectoryId,
                filename: filename,
                metadata: metadata,
                now: now,
                in: db
            )
            if contentChanged {
                try VideoFileRecord.purgeScrubFrames(fileId: fileId, in: db)
            }
            return try VideoFileRecord.fetchOne(db, key: recordId)
        }

        // Regenerate thumbnail for modified file
        await regenerateThumbnail(for: existingRecord.fileId, videoURL: url)

        return ProcessResult(
            videoItem: updatedRecord.map { videoItem(from: $0, relativePath: relativePath) },
            wasChanged: true
        )
    }

    /// Clears `missing_since` (and re-homes the record) when a known path is
    /// found again on disk. Returns the record as it is now stored.
    private func restoreIfNeeded(_ record: VideoFileRecord, sourceDirectory: SourceDirectory) async throws -> VideoFileRecord {
        guard record.missingSince != nil || record.sourceDirectoryId != sourceDirectory.id else {
            return record
        }

        logger.info("Restoring \(record.filename): found again on disk")
        let now = Date().timeIntervalSince1970
        let recordId = record.id
        let sourceDirectoryId = sourceDirectory.id
        try await databaseManager.write { db in
            try VideoFileRecord.markPresent(id: recordId, sourceDirectoryId: sourceDirectoryId, now: now, in: db)
        }

        var restored = record
        restored.missingSince = nil
        restored.sourceDirectoryId = sourceDirectory.id
        restored.updatedAt = now
        return restored
    }

    /// Processes a truly new video file (not in database).
    private func processNewVideoFile(
        url: URL,
        sourceDirectory: SourceDirectory
    ) async throws -> ProcessResult {
        // Compute file ID using partial file hashing
        let fileId = try await fileHasher.computeFileId(for: url)

        let metadata = try await metadataExtractor.extract(from: url)

        let relativePath = Self.relativePath(for: url, sourceDirectoryPath: sourceDirectory.path)

        // Check if record exists in database by fileId (file may have been moved)
        let existingRecord = try await databaseManager.read { db in
            try VideoFileRecord.findByFileId(fileId, in: db)
        }

        let now = Date().timeIntervalSince1970

        if let existingRec = existingRecord {
            // Same content already known at another path that still exists: this
            // is a copy, not a move. Keep the record where it is instead of
            // flipping its path (and the catalog version) on every scan.
            if existingRec.path != url.path,
               existingRec.missingSince == nil,
               FileManager.default.fileExists(atPath: existingRec.path),
               URL(fileURLWithPath: existingRec.path).resolvingSymlinksInPath().path
                   != url.resolvingSymlinksInPath().path {
                logger.info("Duplicate of \(existingRec.filename) ignored: \(url.path, privacy: .public)")
                return ProcessResult(videoItem: nil, wasChanged: false)
            }

            // File was moved - update its location and metadata only
            logger.info("File moved, updating path: \(url.lastPathComponent)")

            let recordId = existingRec.id
            let sourceDirectoryId = sourceDirectory.id
            let filePath = url.path
            let filename = url.lastPathComponent
            let updatedRecord = try await databaseManager.write { db -> VideoFileRecord? in
                try VideoFileRecord.updateScannedMetadata(
                    id: recordId,
                    path: filePath,
                    sourceDirectoryId: sourceDirectoryId,
                    filename: filename,
                    metadata: metadata,
                    now: now,
                    in: db
                )
                return try VideoFileRecord.fetchOne(db, key: recordId)
            }

            // Generate thumbnail if it doesn't exist
            await generateThumbnailIfNeeded(for: fileId, videoURL: url)

            return ProcessResult(
                videoItem: updatedRecord.map { videoItem(from: $0, relativePath: relativePath) },
                wasChanged: true
            )
        } else {
            // Truly new file - insert new record
            logger.info("New file detected: \(url.lastPathComponent)")

            let newId = UUID()
            let record = VideoFileRecord(
                id: newId,
                fileId: fileId,
                path: url.path,
                sourceDirectoryId: sourceDirectory.id,
                filename: url.lastPathComponent,
                fileSize: metadata.fileSize,
                duration: metadata.duration,
                width: metadata.width,
                height: metadata.height,
                codec: metadata.codec,
                lastModified: metadata.lastModified.timeIntervalSince1970,
                createdAt: now,
                updatedAt: now
            )

            try await databaseManager.write { db in
                let mutableRecord = record
                try mutableRecord.insert(db)
            }

            // Generate thumbnail for new video
            await generateThumbnailIfNeeded(for: fileId, videoURL: url)

            return ProcessResult(
                videoItem: videoItem(from: record, relativePath: relativePath),
                wasChanged: true
            )
        }
    }

    private func generateThumbnailIfNeeded(for fileId: String, videoURL: URL) async {
        do {
            // Check if thumbnail already exists
            let thumbnailExists = try await databaseManager.read { db in
                try ThumbnailRecord.exists(forFileId: fileId, in: db)
            }

            if thumbnailExists {
                logger.debug("Thumbnail already exists for fileId: \(fileId)")
                return
            }

            // Generate thumbnail
            guard let imageData = await thumbnailGenerator.generateThumbnail(from: videoURL) else {
                logger.warning("Failed to generate thumbnail for \(videoURL.lastPathComponent)")
                return
            }

            // Store thumbnail in database
            let thumbnail = ThumbnailRecord(
                fileId: fileId,
                imageData: imageData
            )

            try await databaseManager.write { db in
                try thumbnail.insert(db)
            }

            logger.debug("Stored thumbnail for fileId: \(fileId)")
        } catch {
            // Log failure but don't block scan
            logger.warning("Thumbnail generation failed for \(videoURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Regenerates thumbnail for a modified file.
    private func regenerateThumbnail(for fileId: String, videoURL: URL) async {
        do {
            // Delete existing thumbnail if it exists
            try await databaseManager.write { db in
                _ = try ThumbnailRecord.deleteByFileId(fileId, in: db)
            }

            // Generate new thumbnail
            guard let imageData = await thumbnailGenerator.generateThumbnail(from: videoURL) else {
                logger.warning("Failed to regenerate thumbnail for \(videoURL.lastPathComponent)")
                return
            }

            // Store new thumbnail in database
            let thumbnail = ThumbnailRecord(
                fileId: fileId,
                imageData: imageData
            )

            try await databaseManager.write { db in
                try thumbnail.insert(db)
            }

            logger.debug("Regenerated thumbnail for fileId: \(fileId)")
        } catch {
            logger.warning("Thumbnail regeneration failed for \(videoURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Soft-deletes the records of reconcilable folders whose file was not
    /// found on disk. Nothing is ever hard-deleted here: tags, ratings,
    /// annotations and captures survive until the file reappears or the user
    /// purges missing videos explicitly.
    private func markMissingRecords(
        presentPaths: Set<String>,
        sourceDirectoryIds: Set<UUID>
    ) async throws -> Int {
        guard !sourceDirectoryIds.isEmpty else { return 0 }

        // Compare canonical paths on both sides so trailing slashes,
        // `.`/`..` segments, or path variations from different traversals
        // do not cause spurious "missing" detections.
        let candidates = try await databaseManager.read { db in
            var records: [VideoFileRecord] = []
            for sourceDirectoryId in sourceDirectoryIds {
                records.append(contentsOf: try VideoFileRecord
                    .filter(Column("source_directory_id") == sourceDirectoryId)
                    .filter(Column("missing_since") == nil)
                    .fetchAll(db))
            }
            return records
        }

        let missingIds = candidates
            .filter { record in
                !presentPaths.contains(Self.canonicalPath(for: URL(fileURLWithPath: record.path)))
                    && !FileManager.default.fileExists(atPath: record.path)
            }
            .map(\.id)

        guard !missingIds.isEmpty else { return 0 }

        let now = Date().timeIntervalSince1970
        return try await databaseManager.write { db in
            var marked = 0
            for id in missingIds where try VideoFileRecord.markMissing(id: id, at: now, in: db) {
                marked += 1
            }
            return marked
        }
    }

    /// Returns a canonical string form of a file URL by standardizing it
    /// (resolves `.`/`..` segments and trailing slashes). Symlinks are not
    /// resolved here so that the canonical form remains consistent with
    /// whatever the database originally recorded for each file.
    nonisolated private static func canonicalPath(for url: URL) -> String {
        VideoFileEnumerator.canonicalPath(for: url)
    }

    // MARK: - Full Rescan (Regenerate All Thumbnails)

    /// Performs a full rescan that regenerates all thumbnails.
    /// This forces re-generation of thumbnails even for unchanged files.
    /// Preserves ratings and tags (linked to fileId).
    func fullRescan(
        directories: [SourceDirectory],
        progressHandler: (@Sendable (ScanProgress) -> Void)? = nil
    ) async throws -> [VideoItem] {
        try await serialized {
            try await self.performFullRescan(directories: directories, progressHandler: progressHandler)
        }
    }

    private func performFullRescan(
        directories: [SourceDirectory],
        progressHandler: (@Sendable (ScanProgress) -> Void)?
    ) async throws -> [VideoItem] {
        let enabledDirectories = directories.filter { $0.isEnabled }

        guard !enabledDirectories.isEmpty else {
            logger.info("No enabled directories for full rescan")
            unavailableDirectoryIds = []
            return []
        }

        logger.info("Starting full rescan - will regenerate all thumbnails")

        let enumeration = try await enumerateSourceDirectories(enabledDirectories)
        let availableDirectoryIds = Set(enabledDirectories.map(\.id))
            .subtracting(enumeration.unavailableDirectories.map(\.id))

        // Delete thumbnails only for available directories so disabled or
        // unreachable sources keep their cache.
        let deletedThumbnails = try await databaseManager.write { db in
            var deletedCount = 0
            for directoryId in availableDirectoryIds {
                try db.execute(
                    sql: """
                    DELETE FROM thumbnails
                    WHERE file_id IN (
                        SELECT file_id FROM video_files WHERE source_directory_id = ?
                    )
                    """,
                    arguments: [directoryId]
                )
                deletedCount += db.changesCount
            }
            return deletedCount
        }
        logger.info("Deleted \(deletedThumbnails) existing thumbnails")

        let allVideoFiles = enumeration.files

        logger.info("Found \(allVideoFiles.count) video files for full rescan")

        var videoItems: [VideoItem] = []
        let totalFiles = allVideoFiles.count

        for (index, fileInfo) in allVideoFiles.enumerated() {
            try Task.checkCancellation()

            let filename = fileInfo.url.lastPathComponent

            progressHandler?(ScanProgress(
                currentFile: filename,
                filesScanned: index,
                totalFiles: totalFiles
            ))

            // Process each file and force thumbnail regeneration
            let result = try await processVideoFileForFullRescan(
                url: fileInfo.url,
                sourceDirectory: fileInfo.sourceDirectory
            )

            if let videoItem = result.videoItem {
                videoItems.append(videoItem)
            }
        }

        progressHandler?(ScanProgress(
            currentFile: "",
            filesScanned: totalFiles,
            totalFiles: totalFiles
        ))

        videoItems.append(contentsOf: try await itemsForUnavailableDirectories(enumeration.unavailableDirectories))

        let missingCount = try await markMissingRecords(
            presentPaths: enumeration.presentPaths,
            sourceDirectoryIds: enumeration.reconcilableDirectoryIds
        )

        if missingCount > 0 {
            logger.info("Marked \(missingCount) videos as missing")
        }

        // Update catalog version
        try await databaseManager.updateCatalogVersion()
        logger.info("Full rescan complete: \(videoItems.count) videos, all thumbnails regenerated")

        return videoItems
    }

    /// Processes a video file during full rescan, always regenerating thumbnail.
    private func processVideoFileForFullRescan(
        url: URL,
        sourceDirectory: SourceDirectory
    ) async throws -> ProcessResult {
        do {
            let filePath = url.path

            // Check if record exists in database by path
            let existingRecord = try await databaseManager.read { db in
                try VideoFileRecord.fetchOne(db, sql: "SELECT * FROM video_files WHERE path = ?", arguments: [filePath])
            }

            if let record = existingRecord {
                let restored = try await restoreIfNeeded(record, sourceDirectory: sourceDirectory)

                // Record exists - regenerate thumbnail
                logger.debug("Regenerating thumbnail for: \(url.lastPathComponent)")

                // Generate new thumbnail (old ones already deleted in bulk)
                await generateThumbnailIfNeeded(for: record.fileId, videoURL: url)

                return ProcessResult(
                    videoItem: videoItem(
                        from: restored,
                        relativePath: Self.relativePath(for: url, sourceDirectoryPath: sourceDirectory.path)
                    ),
                    wasChanged: true
                )
            } else {
                // New file - process normally
                return try await processNewVideoFile(url: url, sourceDirectory: sourceDirectory)
            }
        } catch {
            logger.warning("Failed to process \(url.lastPathComponent): \(error.localizedDescription)")
            return ProcessResult(videoItem: nil, wasChanged: false)
        }
    }

    private func videoItem(from record: VideoFileRecord, relativePath: String) -> VideoItem {
        VideoItem.catalogEntry(record: record, relativePath: relativePath)
    }

    /// Path of `fileURL` relative to its source folder, computed by stripping the
    /// folder prefix (never by substring replacement). Falls back to the
    /// filename when the file is not inside the folder.
    nonisolated static func relativePath(for fileURL: URL, sourceDirectoryPath: String) -> String {
        let sourcePath = URL(fileURLWithPath: sourceDirectoryPath).standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        let prefix = sourcePath.hasSuffix("/") ? sourcePath : sourcePath + "/"

        guard filePath.hasPrefix(prefix) else {
            return fileURL.lastPathComponent
        }

        return String(filePath.dropFirst(prefix.count))
    }
}

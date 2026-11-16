import Foundation
import GridStreamAPI

/// The single mapping from a stored `VideoFileRecord` to the `VideoItem` the
/// API and the in-memory catalog expose.
nonisolated extension VideoItem {
    /// API representation: relative path and folder name resolved against the
    /// record's source folder (the filename when the folder is unknown), and a
    /// thumbnail URL versioned with the thumbnail's `updatedAt`.
    static func api(
        record: VideoFileRecord,
        sourceDirectory: SourceDirectory?,
        tags: [TagSummary]? = nil,
        thumbnailUpdatedAt: Double? = nil
    ) -> VideoItem {
        VideoItem(
            record: record,
            relativePath: relativePath(of: record, in: sourceDirectory),
            tags: tags,
            thumbnailUrl: thumbnailURL(fileId: record.fileId, updatedAt: thumbnailUpdatedAt),
            sourceDirectoryName: sourceDirectory.map { directoryName(of: $0.path) }
        )
    }

    /// Catalog snapshot entry built by the scanner: no tags and no thumbnail URL.
    static func catalogEntry(record: VideoFileRecord, relativePath: String) -> VideoItem {
        VideoItem(record: record, relativePath: relativePath, tags: nil, thumbnailUrl: nil, sourceDirectoryName: nil)
    }

    /// `/api/v1/videos/:fileId/thumbnail`, with `?v=<updatedAt>` when known.
    static func thumbnailURL(fileId: String, updatedAt: Double?) -> String {
        var url = "/api/v1/videos/\(fileId)/thumbnail"
        if let updatedAt {
            url += "?v=\(Int(updatedAt))"
        }
        return url
    }

    /// Path of the record relative to its source folder (prefix stripping, never
    /// substring replacement); the filename when the folder is unknown.
    static func relativePath(of record: VideoFileRecord, in sourceDirectory: SourceDirectory?) -> String {
        guard let sourceDirectory else { return record.filename }
        return VideoScanner.relativePath(
            for: URL(fileURLWithPath: record.path),
            sourceDirectoryPath: sourceDirectory.path
        )
    }

    /// Display name of a source folder: the last path component.
    static func directoryName(of path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private init(
        record: VideoFileRecord,
        relativePath: String,
        tags: [TagSummary]?,
        thumbnailUrl: String?,
        sourceDirectoryName: String?
    ) {
        self.init(
            id: record.id,
            fileId: record.fileId,
            filename: record.filename,
            relativePath: relativePath,
            sourceDirectoryId: record.sourceDirectoryId,
            duration: record.duration,
            width: record.width,
            height: record.height,
            codec: record.codec,
            fileSize: record.fileSize,
            lastModified: Date(timeIntervalSince1970: record.lastModified),
            rating: record.rating,
            playCount: record.playCount,
            totalViewTime: record.totalViewTime,
            lastPlayedAt: record.lastPlayedAt.map(Date.init(timeIntervalSince1970:)),
            annotationCount: record.annotationCount,
            tags: tags,
            thumbnailUrl: thumbnailUrl,
            sourceDirectoryName: sourceDirectoryName
        )
    }
}

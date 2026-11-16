//
//  DemoStore.swift
//  gridstream-ipad
//
//  Everything the demo server knows, as one Codable value: the pack's
//  `seed.json` and the persisted `state.json` both decode to it.
//
//  Derived `VideoItem` fields (tags, annotation count) are computed on read,
//  never stored twice.
//

import Foundation
import GridStreamAPI

nonisolated struct DemoStore: Codable, Sendable {
    struct Video: Codable, Sendable {
        let id: UUID
        let fileId: String
        let filename: String
        let duration: Double
        let width: Int
        let height: Int
        let codec: String
        let fileSize: Int64
        let lastModified: Date
        /// When the video entered the catalog (`dateAdded*` criteria).
        let createdAt: Date
        var rating: Int
        var playCount: Int
        var totalViewTime: Int
        var lastPlayedAt: Date?
    }

    struct Tag: Codable, Sendable {
        let id: UUID
        var name: String
        var color: String
        var description: String?
        var ratingEnabled: Bool
        let createdAt: Date
        var updatedAt: Date
    }

    /// A tag on a video, in assignment order, with its per-video rating.
    struct VideoTag: Codable, Sendable, Equatable {
        let fileId: String
        let tagId: UUID
        var rating: Int?
    }

    struct SmartList: Codable, Sendable {
        let id: UUID
        var name: String
        /// Canonical criteria JSON, as the server stores it.
        var criteria: String
        let createdAt: Date
        var updatedAt: Date
    }

    struct SimpleList: Codable, Sendable {
        let id: UUID
        var name: String
        var sortOrder: String
        /// fileIds, in list order.
        var videoIds: [String]
        let createdAt: Date
        var updatedAt: Date
    }

    struct Capture: Codable, Sendable {
        let id: String
        let fileId: String
        let timestamp: Double
        let width: Int
        let height: Int
        let fileSize: Int
        let createdAt: Date
    }

    var catalogVersion: Int64
    let sourceDirectoryId: UUID
    let sourceDirectoryName: String
    var videos: [Video]
    var tags: [Tag]
    var videoTags: [VideoTag]
    var smartLists: [SmartList]
    var simpleLists: [SimpleList]
    var annotations: [AnnotationDTO]
    var timeRanges: [TimeRangeDTO]
    var captures: [Capture]

    // MARK: - Lookups

    func video(fileId: String) -> Video? {
        videos.first { $0.fileId == fileId }
    }

    func tag(id: UUID) -> Tag? {
        tags.first { $0.id == id }
    }

    func annotationCount(fileId: String) -> Int {
        annotations.reduce(0) { $0 + ($1.videoFileId == fileId ? 1 : 0) }
    }

    func videoCount(tagId: UUID) -> Int {
        videoTags.reduce(0) { $0 + ($1.tagId == tagId ? 1 : 0) }
    }

    /// Tags of a video in assignment order; `withRatings` adds the per-video rating.
    func tagSummaries(fileId: String, withRatings: Bool) -> [TagSummary] {
        videoTags.compactMap { link in
            guard link.fileId == fileId, let tag = tag(id: link.tagId) else { return nil }
            return TagSummary(
                id: tag.id,
                name: tag.name,
                color: tag.color,
                ratingEnabled: tag.ratingEnabled,
                rating: withRatings ? link.rating : nil
            )
        }
    }

    // MARK: - Wire types

    func videoItem(_ video: Video) -> VideoItem {
        VideoItem(
            id: video.id,
            fileId: video.fileId,
            filename: video.filename,
            relativePath: video.filename,
            sourceDirectoryId: sourceDirectoryId,
            duration: video.duration,
            width: video.width,
            height: video.height,
            codec: video.codec,
            fileSize: video.fileSize,
            lastModified: video.lastModified,
            rating: video.rating,
            playCount: video.playCount,
            totalViewTime: video.totalViewTime,
            lastPlayedAt: video.lastPlayedAt,
            annotationCount: annotationCount(fileId: video.fileId),
            tags: tagSummaries(fileId: video.fileId, withRatings: true),
            // Demo thumbnails never change: a fixed version keeps them cached.
            thumbnailUrl: "/api/v1/videos/\(video.fileId)/thumbnail?v=1",
            sourceDirectoryName: sourceDirectoryName
        )
    }

    func tagDTO(_ tag: Tag) -> TagDTO {
        TagDTO(
            id: tag.id,
            name: tag.name,
            color: tag.color,
            description: tag.description,
            ratingEnabled: tag.ratingEnabled,
            videoCount: videoCount(tagId: tag.id),
            createdAt: tag.createdAt,
            updatedAt: tag.updatedAt
        )
    }

    func smartListDTO(_ list: SmartList) -> SmartListDTO {
        SmartListDTO(id: list.id, name: list.name, criteria: list.criteria, createdAt: list.createdAt, updatedAt: list.updatedAt)
    }

    func simpleListDTO(_ list: SimpleList) -> SimpleListDTO {
        SimpleListDTO(
            id: list.id,
            name: list.name,
            videoIds: list.videoIds,
            videoCount: list.videoIds.count,
            sortOrder: SimpleListSortOrder(lenient: list.sortOrder),
            createdAt: list.createdAt,
            updatedAt: list.updatedAt
        )
    }

    func captureDTO(_ capture: Capture) -> FrameCaptureDTO {
        FrameCaptureDTO(
            id: capture.id,
            fileId: capture.fileId,
            timestamp: capture.timestamp,
            width: capture.width,
            height: capture.height,
            fileSize: capture.fileSize,
            createdAt: capture.createdAt,
            filename: video(fileId: capture.fileId)?.filename
        )
    }

    // MARK: - Coding

    static func decode(from data: Data) throws -> DemoStore {
        try JSONDecoder.gridStream().decode(DemoStore.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder.gridStream()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

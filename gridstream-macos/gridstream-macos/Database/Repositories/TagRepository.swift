import Foundation
import GRDB
import GridStreamAPI

/// Changes to apply to a tag; nil fields are left as they are.
nonisolated struct TagChanges: Sendable {
    var name: String?
    var color: String?
    var description: String?
    var ratingEnabled: Bool?
}

/// Persistence of tags (`tags`), their assignment to videos (`video_tags`)
/// and per-tag ratings.
nonisolated struct TagRepository: Sendable {
    /// Maximum number of tags.
    static let maxCount = 30

    let database: DatabaseManager

    // MARK: - Tags

    /// Every tag with the number of videos it is assigned to.
    func allWithVideoCounts() async throws -> [(tag: TagRecord, videoCount: Int)] {
        try await database.read { db in
            TagRecord.findAll(in: db).map { tag in
                (tag, TagRecord.countVideos(for: tag.id, in: db))
            }
        }
    }

    func findWithVideoCount(id: UUID) async throws -> (tag: TagRecord, videoCount: Int) {
        try await database.read { db in
            guard let tag = TagRecord.findById(id, in: db) else {
                throw RepositoryError.notFound("Tag not found")
            }
            return (tag, TagRecord.countVideos(for: id, in: db))
        }
    }

    /// Creates a tag with an already lowercased name; `displayName` is the name
    /// as the client sent it.
    func create(
        name: String,
        displayName: String,
        color: String,
        description: String?,
        ratingEnabled: Bool
    ) async throws -> TagRecord {
        try await database.writeCatalog { db in
            if TagRecord.countAll(in: db) >= Self.maxCount {
                throw RepositoryError.invalid("Tag limit reached. Maximum of \(Self.maxCount) tags allowed.")
            }
            if TagRecord.findByName(name, in: db) != nil {
                throw RepositoryError.invalid("A tag with the name '\(displayName)' already exists.")
            }

            let tag = TagRecord(name: name, color: color, description: description, ratingEnabled: ratingEnabled)
            try tag.insert(db)
            return .changed(tag)
        }
    }

    /// Applies `changes` in one read-modify-write transaction. `changes.name`
    /// is the name as the client sent it; it is stored lowercased.
    func update(id: UUID, changes: TagChanges) async throws -> (tag: TagRecord, videoCount: Int) {
        try await database.writeCatalog { db in
            guard var tag = TagRecord.findById(id, in: db) else {
                throw RepositoryError.notFound("Tag not found")
            }

            if let newName = changes.name {
                let normalizedName = newName.lowercased()
                if normalizedName != tag.name {
                    if TagRecord.findByName(normalizedName, in: db) != nil {
                        throw RepositoryError.invalid("A tag with the name '\(newName)' already exists.")
                    }
                    tag.name = normalizedName
                }
            }

            if let color = changes.color {
                tag.color = color
            }

            if let description = changes.description {
                tag.description = description.isEmpty ? nil : description
            }

            if let ratingEnabled = changes.ratingEnabled {
                tag.ratingEnabled = ratingEnabled
            }

            tag.touch()
            try tag.update(db)
            return .changed((tag, TagRecord.countVideos(for: id, in: db)))
        }
    }

    /// Deletes a tag, its assignments and its references in smart list criteria.
    /// Returns the deleted tag and how many videos had it.
    func delete(id: UUID) async throws -> (tag: TagRecord, affectedVideoCount: Int) {
        try await database.writeCatalog { db in
            guard let tag = TagRecord.findById(id, in: db) else {
                throw RepositoryError.notFound("Tag not found")
            }

            let affectedVideoCount = TagRecord.countVideos(for: id, in: db)

            _ = try VideoTagRecord.filter(Column("tag_id") == id).deleteAll(db)
            _ = try TagRecord.filter(Column("id") == id).deleteAll(db)

            // Smart lists must not keep referencing the deleted tag
            try SmartListRecord.removeTagFromCriteria(id, in: db)

            return .changed((tag, affectedVideoCount))
        }
    }

    // MARK: - Video tags

    /// Tags of a video (any video row, live or not); 404 when the video is unknown.
    func tags(ofVideo fileId: String) async throws -> [TagSummary] {
        try await database.read { db in
            try Self.requireVideo(fileId, in: db)
            return Self.tagSummaries(forFileId: fileId, in: db)
        }
    }

    /// Replaces the video's tag set with `tagIds` (unknown tag → 400).
    func replaceTags(ofVideo fileId: String, with tagIds: [UUID]) async throws -> [TagSummary] {
        try await database.writeCatalog { db in
            try Self.requireVideo(fileId, in: db)

            for tagId in tagIds where TagRecord.findById(tagId, in: db) == nil {
                throw RepositoryError.invalid("Tag with ID '\(tagId)' not found")
            }

            let existingTagIds = Set(VideoTagRecord.findByVideoFileId(fileId, in: db).map(\.tagId))
            let requestedTagIds = Set(tagIds)

            let tagsToRemove = existingTagIds.subtracting(requestedTagIds)
            for tagId in tagsToRemove {
                try VideoTagRecord.deleteByVideoFileIdAndTagId(fileId, tagId, in: db)
            }

            let tagsToAdd = requestedTagIds.subtracting(existingTagIds)
            for tagId in tagsToAdd {
                let videoTag = VideoTagRecord(videoFileId: fileId, tagId: tagId)
                try videoTag.insert(db)
            }

            let tags = Self.tagSummaries(forFileId: fileId, in: db)
            return tagsToRemove.isEmpty && tagsToAdd.isEmpty ? .unchanged(tags) : .changed(tags)
        }
    }

    /// Idempotent single-tag attach; returns the video's tags.
    func attachTag(_ tagId: UUID, toVideo fileId: String) async throws -> [TagSummary] {
        try await database.writeCatalog { db in
            try Self.requireVideo(fileId, in: db)
            try Self.requireTag(tagId, in: db)

            var changed = false
            if VideoTagRecord.findByVideoFileIdAndTagId(fileId, tagId, in: db) == nil {
                let videoTag = VideoTagRecord(videoFileId: fileId, tagId: tagId)
                try videoTag.insert(db)
                changed = true
            }

            let tags = Self.tagSummaries(forFileId: fileId, in: db)
            return changed ? .changed(tags) : .unchanged(tags)
        }
    }

    /// Detaches a tag from a video (no-op when it is not attached).
    func detachTag(_ tagId: UUID, fromVideo fileId: String) async throws {
        try await database.writeCatalog { db in
            try Self.requireVideo(fileId, in: db)
            try Self.requireTag(tagId, in: db)

            let deletedCount = try VideoTagRecord.deleteByVideoFileIdAndTagId(fileId, tagId, in: db)
            return deletedCount > 0 ? .changed : .unchanged
        }
    }

    /// Adds and removes tags on many videos in one transaction. Unknown
    /// fileIds or tagIds → 400. Returns the number of videos whose tags changed.
    func applyInBulk(fileIds: [String], add addTagIds: Set<UUID>, remove removeTagIds: Set<UUID>) async throws -> Int {
        try await database.writeCatalog { db in
            let knownFileIds = Set(try String.fetchAll(
                db,
                VideoFileRecord.select(Column("file_id")).filter(fileIds.contains(Column("file_id")))
            ))
            if let unknown = fileIds.first(where: { !knownFileIds.contains($0) }) {
                throw RepositoryError.invalid("Unknown fileId '\(unknown)'")
            }

            for tagId in addTagIds.union(removeTagIds) where TagRecord.findById(tagId, in: db) == nil {
                throw RepositoryError.invalid("Tag with ID '\(tagId)' not found")
            }

            var updatedFileIds = Set<String>()
            for fileId in fileIds {
                for tagId in addTagIds where VideoTagRecord.findByVideoFileIdAndTagId(fileId, tagId, in: db) == nil {
                    let videoTag = VideoTagRecord(videoFileId: fileId, tagId: tagId)
                    try videoTag.insert(db)
                    updatedFileIds.insert(fileId)
                }
                for tagId in removeTagIds {
                    if try VideoTagRecord.deleteByVideoFileIdAndTagId(fileId, tagId, in: db) > 0 {
                        updatedFileIds.insert(fileId)
                    }
                }
            }

            return updatedFileIds.isEmpty ? .unchanged(0) : .changed(updatedFileIds.count)
        }
    }

    /// Adds `tagIds` to every video of a source folder. Unknown tag → 400, a
    /// folder without videos → 404. Returns (videos affected, videos in folder).
    func addTags(_ tagIds: [UUID], toSourceDirectory sourceDirectoryId: UUID) async throws -> (affected: Int, total: Int) {
        try await database.writeCatalog { db in
            for tagId in tagIds where TagRecord.findById(tagId, in: db) == nil {
                throw RepositoryError.invalid("Tag with ID '\(tagId)' not found")
            }

            let videos = try VideoFileRecord.findBySourceDirectoryId(sourceDirectoryId, in: db)
            guard !videos.isEmpty else {
                throw RepositoryError.notFound("Source directory not found or contains no videos")
            }

            var videosAffected = 0
            for video in videos {
                var videoWasAffected = false
                for tagId in tagIds where VideoTagRecord.findByVideoFileIdAndTagId(video.fileId, tagId, in: db) == nil {
                    let videoTag = VideoTagRecord(videoFileId: video.fileId, tagId: tagId)
                    try videoTag.insert(db)
                    videoWasAffected = true
                }
                if videoWasAffected {
                    videosAffected += 1
                }
            }

            let result = (affected: videosAffected, total: videos.count)
            return videosAffected > 0 ? .changed(result) : .unchanged(result)
        }
    }

    // MARK: - Per-tag ratings

    /// Rating of a tag on a video. 404 for an unknown video, tag or
    /// assignment; 400 when the tag has no rating.
    func rating(ofTag tagId: UUID, onVideo fileId: String) async throws -> Int {
        try await database.read { db in
            try Self.requireVideo(fileId, in: db)
            try Self.requireRatingEnabledTag(tagId, in: db)
            guard let videoTag = VideoTagRecord.findByVideoFileIdAndTagId(fileId, tagId, in: db) else {
                throw RepositoryError.notFound("Video does not have this tag assigned")
            }
            return videoTag.rating
        }
    }

    /// Sets the rating of a tag on a video (same errors as `rating(ofTag:onVideo:)`).
    func setRating(_ rating: Int, ofTag tagId: UUID, onVideo fileId: String) async throws {
        try await database.writeCatalog { db in
            try Self.requireVideo(fileId, in: db)
            try Self.requireRatingEnabledTag(tagId, in: db)
            try db.execute(
                sql: "UPDATE video_tags SET rating = ? WHERE video_file_id = ? AND tag_id = ?",
                arguments: [rating, fileId, tagId]
            )
            guard db.changesCount > 0 else {
                throw RepositoryError.notFound("Video does not have this tag assigned")
            }
            return .changed
        }
    }

    /// Sets the rating of a tag on every video of a source folder that has
    /// it. Returns the number of assignments updated.
    func setRating(_ rating: Int, ofTag tagId: UUID, inSourceDirectory sourceDirectoryId: UUID) async throws -> Int {
        try await database.writeCatalog { db in
            try Self.requireRatingEnabledTag(tagId, in: db)

            let videoCount = try VideoFileRecord
                .filter(Column("source_directory_id") == sourceDirectoryId)
                .fetchCount(db)
            guard videoCount > 0 else {
                throw RepositoryError.notFound("Source directory not found or contains no videos")
            }

            try db.execute(
                sql: """
                    UPDATE video_tags SET rating = ?
                    WHERE tag_id = ?
                      AND video_file_id IN (SELECT file_id FROM video_files WHERE source_directory_id = ?)
                    """,
                arguments: [rating, tagId, sourceDirectoryId]
            )
            let affected = db.changesCount
            return affected > 0 ? .changed(affected) : .unchanged(affected)
        }
    }

    // MARK: - Helpers

    /// Tags of a video with their per-video rating, in assignment order.
    static func tagSummariesWithRatings(forFileId fileId: String, in db: Database) -> [TagSummary] {
        VideoTagRecord.findByVideoFileId(fileId, in: db).compactMap { videoTag in
            TagRecord.findById(videoTag.tagId, in: db).map { TagSummary(from: $0, rating: videoTag.rating) }
        }
    }

    /// Tags of many videos with their per-video rating; every requested fileId
    /// has an entry (possibly empty).
    static func tagSummariesWithRatings(forFileIds fileIds: [String], in db: Database) throws -> [String: [TagSummary]] {
        let videoTags = try VideoTagRecord.filter(fileIds.contains(Column("video_file_id"))).fetchAll(db)
        let tagIds = Set(videoTags.map(\.tagId))
        let tags = try TagRecord.filter(tagIds.contains(Column("id"))).fetchAll(db)
        let tagsById = Dictionary(tags.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var result: [String: [TagSummary]] = [:]
        for fileId in fileIds {
            result[fileId] = []
        }
        for videoTag in videoTags {
            if let tag = tagsById[videoTag.tagId] {
                result[videoTag.videoFileId, default: []].append(TagSummary(from: tag, rating: videoTag.rating))
            }
        }
        return result
    }

    private static func tagSummaries(forFileId fileId: String, in db: Database) -> [TagSummary] {
        VideoTagRecord.findByVideoFileId(fileId, in: db).compactMap { videoTag in
            TagRecord.findById(videoTag.tagId, in: db).map { TagSummary(from: $0) }
        }
    }

    private static func requireVideo(_ fileId: String, in db: Database) throws {
        guard try VideoFileRecord.findByFileId(fileId, in: db) != nil else {
            throw RepositoryError.notFound("Video not found")
        }
    }

    private static func requireTag(_ tagId: UUID, in db: Database) throws {
        guard TagRecord.findById(tagId, in: db) != nil else {
            throw RepositoryError.notFound("Tag not found")
        }
    }

    private static func requireRatingEnabledTag(_ tagId: UUID, in db: Database) throws {
        guard let tag = TagRecord.findById(tagId, in: db) else {
            throw RepositoryError.notFound("Tag not found")
        }
        guard tag.ratingEnabled else {
            throw RepositoryError.invalid("Tag '\(tag.name)' does not have rating enabled")
        }
    }
}

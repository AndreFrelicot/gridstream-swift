import Foundation
import GridStreamAPI

extension DemoServer {
    func routeVideos(_ request: DemoRequest) throws -> DemoResponse? {
        // Videos
        if request.on("GET", "videos") != nil {
            return .json(try listVideos(query: request.query))
        }
        if let params = request.on("GET", "videos/by-file-id/:fileId") {
            let fileId = params[0]
            let store = try loadedStore()
            return .json(store.videoItem(try requireVideo(fileId, in: store)))
        }
        if let params = request.on("GET", "videos/:id") {
            let id = params[0]
            let store = try loadedStore()
            guard let uuid = UUID(uuidString: id) else { throw DemoHTTPError.badRequest("Invalid video ID format") }
            guard let video = store.videos.first(where: { $0.id == uuid }) else { throw DemoHTTPError.notFound("Video not found") }
            return .json(store.videoItem(video))
        }
        if let params = request.on("GET", "videos/:fileId/stream") ?? request.on("HEAD", "videos/:fileId/stream") {
            let fileId = params[0]
            _ = try requireVideo(fileId, in: try loadedStore())
            guard let clip = clipFile(fileId) else { throw DemoHTTPError.notFound("Video file not found") }
            if request.method == "HEAD" { return DemoResponse(status: 200, contentType: "video/mp4", body: Data()) }
            return DemoResponse(status: 200, contentType: "video/mp4", body: try Data(contentsOf: clip, options: .mappedIfSafe))
        }
        if let params = request.on("GET", "videos/:fileId/thumbnail") {
            let fileId = params[0]
            _ = try requireVideo(fileId, in: try loadedStore())
            guard let thumbnail = thumbnailFile(fileId), let data = try? Data(contentsOf: thumbnail) else {
                throw DemoHTTPError.notFound("Thumbnail not found for video")
            }
            return .jpeg(data)
        }

        // Ratings and playback statistics
        if let params = request.on("GET", "videos/:fileId/rating") {
            let fileId = params[0]
            return .json(RatingDTO(rating: try requireVideo(fileId, in: try loadedStore()).rating))
        }
        if let params = request.on("PUT", "videos/:fileId/rating") {
            let fileId = params[0]
            let request = try decode(RatingRequest.self, request.body)
            try Self.validateRating(request.rating)
            try write { store in
                guard let index = store.videos.firstIndex(where: { $0.fileId == fileId }) else {
                    throw DemoHTTPError.notFound("Video not found")
                }
                store.videos[index].rating = request.rating
            }
            return .json(RatingDTO(rating: request.rating))
        }
        if let params = request.on("POST", "videos/:fileId/playback-stats") {
            let fileId = params[0]
            return .json(try applyPlaybackStats(fileId: fileId, try decode(PlaybackStatsRequest.self, request.body)))
        }
        return nil
    }

    // MARK: - Videos

    private func listVideos(query: [String: String]) throws -> PaginatedVideosResponse {
        let store = try loadedStore()
        let evaluator = DemoCriteriaEvaluator(store: store)
        let limit = min(max(Int(query["limit"] ?? "") ?? 10_000, 1), 10_000)
        let offset = Int(query["offset"] ?? "") ?? 0
        guard offset >= 0 else { throw DemoHTTPError.badRequest("offset must not be negative") }

        var candidates = Set(store.videos.map(\.fileId))
        func restrict(to fileIds: Set<String>) {
            candidates.formIntersection(fileIds)
        }

        if let json = query["criteria"] {
            let criteria: SmartListCriteria
            do {
                criteria = try SmartListCriteria.parseValidated(json: json)
            } catch let error as CriteriaValidationError {
                throw DemoHTTPError.badRequest(error.reason)
            }
            restrict(to: evaluator.fileIds(matching: criteria))
        }
        for smartListId in Self.uuidList(query["smartListIds"]) {
            restrict(to: evaluator.fileIds(matching: .smartListInclude(smartListId: smartListId)))
        }

        let tagIds = Self.uuidList(query["tags"])
        if !tagIds.isEmpty {
            restrict(to: evaluator.fileIdsWithAllTags(tagIds, ratings: Self.tagRatings(query["tagRatings"])))
        }
        let excludedTagIds = Self.uuidList(query["excludeTags"])
        if !excludedTagIds.isEmpty {
            candidates.subtract(store.videoTags.filter { excludedTagIds.contains($0.tagId) }.map(\.fileId))
        }
        for listId in Self.uuidList(query["simpleListIds"]) {
            restrict(to: Set(store.simpleLists.first { $0.id == listId }?.videoIds ?? []))
        }
        if let legacyTagId = query["tag_id"].flatMap(UUID.init(uuidString:)) {
            let minRating = query["tag_min_rating"].flatMap { Int($0) }
            let maxRating = query["tag_max_rating"].flatMap { Int($0) }
            if minRating != nil || maxRating != nil {
                restrict(to: evaluator.fileIdsWithAllTags([legacyTagId], ratings: [(legacyTagId, minRating, maxRating)]))
            }
        }

        if let hasText = Self.bool(query["hasTextAnnotations"]) {
            let withText = evaluator.fileIdsWithTextAnnotations()
            restrict(to: hasText ? withText : Set(store.videos.map(\.fileId)).subtracting(withText))
        }
        if let text = query["annotationTextSearch"], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            restrict(to: evaluator.fileIdsWithAnnotationText(text))
        }
        if let hasRanges = Self.bool(query["hasTimeRanges"]) ?? Self.bool(query["hasSegments"]) {
            let withRanges = evaluator.fileIdsWithPlayableTimeRanges()
            restrict(to: hasRanges ? withRanges : Set(store.videos.map(\.fileId)).subtracting(withRanges))
        }

        let videoIds = query["videoIds"]?.split(separator: ",").map(String.init) ?? []
        let videoUUIDs = Set(videoIds.compactMap(UUID.init(uuidString:)))
        if let regexPattern = query["filenameRegex"], regexPattern.count > SmartListCriteria.maxPatternLength {
            throw DemoHTTPError.badRequest("filenameRegex must be at most \(SmartListCriteria.maxPatternLength) characters")
        }
        let regex = query["filenameRegex"].map { try? NSRegularExpression(pattern: $0) }
        if case .some(.none) = regex {
            return PaginatedVideosResponse(videos: [], total: 0, limit: limit, offset: offset)
        }

        let search = query["search"] ?? ""
        let searchMatchesFolder = !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && store.sourceDirectoryName.localizedCaseInsensitiveContains(search)
        let sourceDirectoryId = query["sourceDirectoryId"].flatMap(UUID.init(uuidString:))
        let minRating = Self.int(query["minRating"]) ?? Self.int(query["min_rating"])
        let maxRating = Self.int(query["maxRating"]) ?? Self.int(query["max_rating"])
        let exactRating = Self.int(query["rating"])
        let unrated = Self.bool(query["unrated"])
        let played = Self.bool(query["played"])
        let unplayed = Self.bool(query["unplayed"])
        let minPlayCount = Self.int(query["minPlayCount"])
        let maxPlayCount = Self.int(query["maxPlayCount"])
        let minFileSize = query["minFileSize"].flatMap { Int64($0) }
        let maxFileSize = query["maxFileSize"].flatMap { Int64($0) }
        let hasAnnotations = Self.bool(query["hasAnnotations"])
        let minAnnotationCount = Self.int(query["minAnnotationCount"])
        let maxAnnotationCount = Self.int(query["maxAnnotationCount"])
        let addedAfter = query["addedAfter"].flatMap(TolerantDateDecoding.date(from:))
        let addedBefore = query["addedBefore"].flatMap(TolerantDateDecoding.date(from:))
        let modifiedAfter = query["modifiedAfter"].flatMap(TolerantDateDecoding.date(from:))
        let modifiedBefore = query["modifiedBefore"].flatMap(TolerantDateDecoding.date(from:))

        let matching = store.videos.filter { video in
            guard candidates.contains(video.fileId) else { return false }
            if let sourceDirectoryId, sourceDirectoryId != store.sourceDirectoryId { return false }
            if !search.isEmpty, !searchMatchesFolder, !DemoCriteriaEvaluator.like(video.filename, contains: search) { return false }
            if let text = query["filenameStartsWith"], !text.isEmpty, !DemoCriteriaEvaluator.like(video.filename, startsWith: text) { return false }
            if let text = query["filenameEndsWith"], !text.isEmpty, !DemoCriteriaEvaluator.like(video.filename, endsWith: text) { return false }

            if unrated == true {
                if video.rating != 0 { return false }
            } else if let exactRating {
                if video.rating != exactRating { return false }
            } else {
                if let minRating, video.rating < minRating { return false }
                if let maxRating, video.rating > maxRating { return false }
            }

            if played == true, video.lastPlayedAt == nil { return false }
            if unplayed == true {
                if video.playCount != 0 { return false }
            } else {
                if let minPlayCount, video.playCount < minPlayCount { return false }
                if let maxPlayCount, video.playCount > maxPlayCount { return false }
            }

            if let minFileSize, video.fileSize < minFileSize { return false }
            if let maxFileSize, video.fileSize > maxFileSize { return false }

            let annotationCount = store.annotationCount(fileId: video.fileId)
            if let hasAnnotations, (annotationCount > 0) != hasAnnotations { return false }
            if let minAnnotationCount, annotationCount < minAnnotationCount { return false }
            if let maxAnnotationCount, annotationCount > maxAnnotationCount { return false }

            if let addedAfter, !(video.createdAt > addedAfter) { return false }
            if let addedBefore, !(video.createdAt < addedBefore) { return false }
            if let modifiedAfter, !(video.lastModified > modifiedAfter) { return false }
            if let modifiedBefore, !(video.lastModified < modifiedBefore) { return false }

            if !videoIds.isEmpty, !videoIds.contains(video.fileId), !videoUUIDs.contains(video.id) { return false }
            if let regex = regex ?? nil, !DemoCriteriaEvaluator.matches(regex, video.filename) { return false }
            return true
        }

        let page = Self.sorted(matching, by: query["sort"]).dropFirst(offset).prefix(limit)
        return PaginatedVideosResponse(videos: page.map(store.videoItem), total: matching.count, limit: limit, offset: offset)
    }

    /// The macOS sort orders. SQLite puts NULL first in ascending order and
    /// last in descending order; ties fall back to the filename.
    static func sorted(_ videos: [DemoStore.Video], by sort: String?) -> [DemoStore.Video] {
        func byName(_ lhs: DemoStore.Video, _ rhs: DemoStore.Video) -> Bool {
            lhs.filename.localizedCaseInsensitiveCompare(rhs.filename) == .orderedAscending
        }
        func ordered<T: Comparable>(_ key: (DemoStore.Video) -> T, descending: Bool) -> [DemoStore.Video] {
            videos.sorted { lhs, rhs in
                let left = key(lhs), right = key(rhs)
                if left == right { return byName(lhs, rhs) }
                return descending ? left > right : left < right
            }
        }
        let lastPlayed: (DemoStore.Video) -> Double = { $0.lastPlayedAt?.timeIntervalSince1970 ?? -.infinity }

        switch sort {
        case "rating_asc": return ordered(\.rating, descending: false)
        case "rating_desc": return ordered(\.rating, descending: true)
        case "filename_desc": return videos.sorted { byName($1, $0) }
        case "playCount_asc", "play_count_asc": return ordered(\.playCount, descending: false)
        case "playCount_desc", "play_count_desc": return ordered(\.playCount, descending: true)
        case "lastPlayed_desc", "last_played_desc": return ordered(lastPlayed, descending: true)
        case "lastPlayed_asc", "last_played_asc": return ordered(lastPlayed, descending: false)
        default: return videos.sorted(by: byName)
        }
    }

    private func applyPlaybackStats(fileId: String, _ request: PlaybackStatsRequest) throws -> PlaybackStatsDTO {
        let addViewTime = min(max(request.addViewTime, 0), 86_400)
        let change: (inout DemoStore) throws -> PlaybackStatsDTO = { store in
            guard let index = store.videos.firstIndex(where: { $0.fileId == fileId }) else {
                throw DemoHTTPError.notFound("Video not found")
            }
            if request.incrementPlayCount {
                store.videos[index].playCount += 1
                store.videos[index].lastPlayedAt = Date()
            }
            store.videos[index].totalViewTime += addViewTime
            return PlaybackStatsDTO(playCount: store.videos[index].playCount, totalViewTime: store.videos[index].totalViewTime)
        }
        guard request.incrementPlayCount || addViewTime > 0 else {
            var unchanged = try loadedStore()
            return try change(&unchanged)
        }
        return try write(change)
    }
}

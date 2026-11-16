//
//  DemoCriteriaEvaluator.swift
//  gridstream-ipad
//
//  The smart-list criteria evaluator of the demo server. It mirrors the
//  macOS `CriteriaEvaluator` (SQL) on the in-memory `DemoStore`:
//  - conditions combine left to right, AND as intersection, OR as union;
//  - empty criteria match every video;
//  - filename LIKE matches ignore ASCII case, as SQLite's LIKE does;
//  - annotation text search matches a phrase of words, as the FTS5 index does;
//  - a smart list including itself (directly or not) contributes nothing.
//

import Foundation
import GridStreamAPI

nonisolated struct DemoCriteriaEvaluator {
    let store: DemoStore

    private var allFileIds: Set<String> {
        Set(store.videos.map(\.fileId))
    }

    func fileIds(matching criteria: SmartListCriteria, visitedSmartListIds: Set<UUID> = []) -> Set<String> {
        guard let first = criteria.conditions.first else {
            return allFileIds
        }

        var result = fileIds(matching: first.criteriaType, visitedSmartListIds: visitedSmartListIds)
        for condition in criteria.conditions.dropFirst() {
            let matches = fileIds(matching: condition.criteriaType, visitedSmartListIds: visitedSmartListIds)
            switch condition.logicOperator {
            case .and:
                result.formIntersection(matches)
            case .or:
                result.formUnion(matches)
            }
        }
        return result
    }

    func fileIds(matching type: CriteriaType, visitedSmartListIds: Set<UUID> = []) -> Set<String> {
        switch type {
        case .tagsInclude(let tagIds, let tagRatings):
            return fileIdsWithAllTags(tagIds, ratings: tagRatings.map {
                (tagId: $0.tagId, minRating: $0.minRating, maxRating: $0.maxRating)
            })
        case .tagsExclude(let tagIds):
            let excluded = Set(store.videoTags.filter { tagIds.contains($0.tagId) }.map(\.fileId))
            return allFileIds.subtracting(excluded)
        case .ratingMin(let value):
            return videos { $0.rating >= value }
        case .ratingMax(let value):
            return videos { $0.rating <= value }
        case .sourceDirectory(let id):
            guard let uuid = UUID(uuidString: id), uuid == store.sourceDirectoryId else { return [] }
            return allFileIds
        case .fileSizeMin(let megabytes):
            let bytes = Self.bytes(fromMegabytes: megabytes)
            return videos { $0.fileSize >= bytes }
        case .fileSizeMax(let megabytes):
            let bytes = Self.bytes(fromMegabytes: megabytes)
            return videos { $0.fileSize <= bytes }
        case .filenameContains(let text):
            return videos { Self.like($0.filename, contains: text) }
        case .filenameStartsWith(let text):
            return videos { Self.like($0.filename, startsWith: text) }
        case .filenameEndsWith(let text):
            return videos { Self.like($0.filename, endsWith: text) }
        case .filenameRegex(let pattern):
            guard pattern.count <= SmartListCriteria.maxPatternLength,
                  let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            return videos { Self.matches(regex, $0.filename) }
        case .dateAddedAfter(let date):
            return videos { $0.createdAt > date }
        case .dateAddedBefore(let date):
            return videos { $0.createdAt < date }
        case .dateModifiedAfter(let date):
            return videos { $0.lastModified > date }
        case .dateModifiedBefore(let date):
            return videos { $0.lastModified < date }
        case .playCountMin(let value):
            return videos { $0.playCount >= value }
        case .playCountMax(let value):
            return videos { $0.playCount <= value }
        case .unplayed:
            return videos { $0.playCount == 0 }
        case .unrated:
            return videos { $0.rating == 0 }
        case .hasAnnotations(let value):
            return videos { (store.annotationCount(fileId: $0.fileId) > 0) == value }
        case .annotationCountMin(let value):
            return videos { store.annotationCount(fileId: $0.fileId) >= value }
        case .annotationCountMax(let value):
            return videos { store.annotationCount(fileId: $0.fileId) <= value }
        case .hasTextAnnotations(let value):
            let withText = fileIdsWithTextAnnotations()
            return value ? withText : allFileIds.subtracting(withText)
        case .annotationTextSearch(let text):
            return fileIdsWithAnnotationText(text)
        case .hasTimeRanges(let value):
            let withRanges = fileIdsWithPlayableTimeRanges()
            return value ? withRanges : allFileIds.subtracting(withRanges)
        case .simpleListInclude(let simpleListId):
            return Set(store.simpleLists.first { $0.id == simpleListId }?.videoIds ?? [])
        case .smartListInclude(let smartListId):
            guard !visitedSmartListIds.contains(smartListId),
                  let list = store.smartLists.first(where: { $0.id == smartListId }),
                  let criteria = try? SmartListCriteria.decode(json: list.criteria) else {
                return []
            }
            return fileIds(matching: criteria, visitedSmartListIds: visitedSmartListIds.union([smartListId]))
        }
    }

    // MARK: - Shared predicates (also used by `GET /videos`)

    /// Videos having every tag of `tagIds`, honoring the rating bounds given
    /// for some of them (duplicate tagIds in `ratings`: last one wins).
    func fileIdsWithAllTags(
        _ tagIds: [UUID],
        ratings: [(tagId: UUID, minRating: Int?, maxRating: Int?)]
    ) -> Set<String> {
        var bounds: [UUID: (minRating: Int?, maxRating: Int?)] = [:]
        for rating in ratings {
            bounds[rating.tagId] = (rating.minRating, rating.maxRating)
        }

        var result: Set<String>?
        for tagId in tagIds {
            let links = store.videoTags.filter { link in
                guard link.tagId == tagId else { return false }
                guard let bound = bounds[tagId], bound.minRating != nil || bound.maxRating != nil else { return true }
                // SQL comparisons with a NULL rating are false.
                guard let rating = link.rating else { return false }
                if let minRating = bound.minRating, rating < minRating { return false }
                if let maxRating = bound.maxRating, rating > maxRating { return false }
                return true
            }
            let fileIds = Set(links.map(\.fileId))
            result = result.map { $0.intersection(fileIds) } ?? fileIds
            if result?.isEmpty == true { return [] }
        }
        return result ?? []
    }

    func fileIdsWithTextAnnotations() -> Set<String> {
        Set(store.annotations.filter { annotation in
            guard let text = annotation.text else { return false }
            return !text.trimmingCharacters(in: .whitespaces).isEmpty
        }.map(\.videoFileId))
    }

    /// FTS5 phrase semantics: the query's words appear in a row, ignoring
    /// case and diacritics. An empty query matches nothing.
    func fileIdsWithAnnotationText(_ text: String) -> Set<String> {
        let phrase = Self.words(text)
        guard !phrase.isEmpty else { return [] }
        return Set(store.annotations.filter { annotation in
            guard let annotationText = annotation.text else { return false }
            return Self.containsPhrase(Self.words(annotationText), phrase)
        }.map(\.videoFileId))
    }

    /// Videos with at least one time range that starts inside the video and
    /// has a positive length.
    func fileIdsWithPlayableTimeRanges() -> Set<String> {
        Set(store.timeRanges.filter { range in
            guard let video = store.video(fileId: range.videoFileId), video.duration > 0 else { return false }
            return range.startTime >= 0 && range.startTime < video.duration && range.endTime > range.startTime
        }.map(\.videoFileId))
    }

    // MARK: - Helpers

    private func videos(where predicate: (DemoStore.Video) -> Bool) -> Set<String> {
        Set(store.videos.filter(predicate).map(\.fileId))
    }

    static func bytes(fromMegabytes megabytes: Double) -> Int64 {
        guard megabytes.isFinite else { return 0 }
        let clamped = min(max(megabytes, 0), SmartListCriteria.maxFileSizeMegabytes)
        return Int64(clamped * 1024 * 1024)
    }

    static func like(_ value: String, contains text: String) -> Bool {
        text.isEmpty || value.range(of: text, options: [.caseInsensitive, .literal]) != nil
    }

    static func like(_ value: String, startsWith text: String) -> Bool {
        value.range(of: text, options: [.caseInsensitive, .literal, .anchored]) != nil || text.isEmpty
    }

    static func like(_ value: String, endsWith text: String) -> Bool {
        value.range(of: text, options: [.caseInsensitive, .literal, .anchored, .backwards]) != nil || text.isEmpty
    }

    static func matches(_ regex: NSRegularExpression, _ value: String) -> Bool {
        regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    static func containsPhrase(_ words: [String], _ phrase: [String]) -> Bool {
        guard phrase.count <= words.count else { return false }
        for start in 0...(words.count - phrase.count) where Array(words[start..<(start + phrase.count)]) == phrase {
            return true
        }
        return false
    }
}

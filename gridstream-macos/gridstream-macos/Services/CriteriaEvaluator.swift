import Foundation
import OSLog
import GRDB
import GridStreamAPI

nonisolated struct CriteriaEvaluator {
    private let logger = Logger(subsystem: "com.gridstream.macos", category: "CriteriaEvaluator")

    /// Megabytes → bytes without overflow: non-finite values count as 0 and the
    /// result is clamped to the validated range (stored criteria may predate validation).
    nonisolated static func bytes(fromMegabytes megabytes: Double) -> Int64 {
        guard megabytes.isFinite else { return 0 }
        let clamped = min(max(megabytes, 0), SmartListCriteria.maxFileSizeMegabytes)
        return Int64(clamped * 1024 * 1024)
    }

    /// Escapes `%`, `_` and the escape character itself for a LIKE pattern
    /// used with `ESCAPE '\\'`, so client text matches literally.
    nonisolated static func escapeLike(_ text: String) -> String {
        var escaped = ""
        for character in text {
            if character == "\\" || character == "%" || character == "_" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }

    static func annotationTextFTSQuery(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "\"\(trimmed.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    static func videoFileIdsWithPlayableTimeRanges(_ value: Bool, in db: Database) throws -> Set<String> {
        if value {
            return Set(try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT tr.video_file_id
                    FROM time_ranges tr
                    JOIN video_files vf ON vf.file_id = tr.video_file_id
                    WHERE vf.duration > 0
                      AND tr.start_time >= 0
                      AND tr.start_time < vf.duration
                      AND tr.end_time > tr.start_time
                    """
            ))
        }

        return Set(try String.fetchAll(
            db,
            sql: """
                SELECT vf.file_id
                FROM video_files vf
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM time_ranges tr
                    WHERE tr.video_file_id = vf.file_id
                      AND vf.duration > 0
                      AND tr.start_time >= 0
                      AND tr.start_time < vf.duration
                      AND tr.end_time > tr.start_time
                )
                """
        ))
    }

    func evaluateCriteria(_ criteria: SmartListCriteria, db: DatabaseManager, visitedSmartListIds: Set<UUID> = []) async throws -> Set<String> {
        guard !criteria.conditions.isEmpty else {
            return try await db.read { db in
                Set(try VideoFileRecord.fetchAll(db).map { $0.fileId })
            }
        }

        var result = try await evaluateCondition(criteria.conditions[0].criteriaType, db: db, visitedSmartListIds: visitedSmartListIds)

        for i in 1..<criteria.conditions.count {
            let condition = criteria.conditions[i]
            let conditionResult = try await evaluateCondition(condition.criteriaType, db: db, visitedSmartListIds: visitedSmartListIds)
            switch condition.logicOperator {
            case .and:
                result = result.intersection(conditionResult)
            case .or:
                result = result.union(conditionResult)
            }
        }

        return result
    }

    func evaluateCondition(_ criteriaType: CriteriaType, db: DatabaseManager, visitedSmartListIds: Set<UUID> = []) async throws -> Set<String> {
        switch criteriaType {
        case .tagsInclude(let tagIds, let tagRatings):
            return try await db.read { db in
                // Duplicate tagIds: last one wins, never trap
                let ratingFiltersByTagId = Dictionary(tagRatings.map { ($0.tagId, $0) }, uniquingKeysWith: { _, last in last })
                var result: Set<String>?
                for tagId in tagIds {
                    let fileIds: Set<String>
                    if let ratingFilter = ratingFiltersByTagId[tagId],
                       ratingFilter.minRating != nil || ratingFilter.maxRating != nil {
                        let videoTags = try VideoTagRecord.findByTagIdWithRating(
                            tagId, minRating: ratingFilter.minRating, maxRating: ratingFilter.maxRating, in: db
                        )
                        fileIds = Set(videoTags.map { $0.videoFileId })
                    } else {
                        let videoTags = VideoTagRecord.findByTagId(tagId, in: db)
                        fileIds = Set(videoTags.map { $0.videoFileId })
                    }
                    if let current = result {
                        result = current.intersection(fileIds)
                    } else {
                        result = fileIds
                    }
                    if result?.isEmpty == true { return [] }
                }
                return result ?? []
            }

        case .tagsExclude(let tagIds):
            return try await db.read { db in
                let allFileIds = Set(try VideoFileRecord.fetchAll(db).map { $0.fileId })
                var excludedFileIds = Set<String>()
                for tagId in tagIds {
                    let videoTags = VideoTagRecord.findByTagId(tagId, in: db)
                    excludedFileIds.formUnion(videoTags.map { $0.videoFileId })
                }
                return allFileIds.subtracting(excludedFileIds)
            }

        case .ratingMin(let value):
            return try await db.read { db in
                Set(try VideoFileRecord.filter(Column("rating") >= value).fetchAll(db).map { $0.fileId })
            }

        case .ratingMax(let value):
            return try await db.read { db in
                Set(try VideoFileRecord.filter(Column("rating") <= value).fetchAll(db).map { $0.fileId })
            }

        case .sourceDirectory(let id):
            guard let uuid = UUID(uuidString: id) else { return [] }
            return try await db.read { db in
                Set(try VideoFileRecord.filter(Column("source_directory_id") == uuid).fetchAll(db).map { $0.fileId })
            }

        case .fileSizeMin(let megabytes):
            let bytes = Self.bytes(fromMegabytes: megabytes)
            return try await db.read { db in
                Set(try VideoFileRecord.filter(Column("file_size") >= bytes).fetchAll(db).map { $0.fileId })
            }

        case .fileSizeMax(let megabytes):
            let bytes = Self.bytes(fromMegabytes: megabytes)
            return try await db.read { db in
                Set(try VideoFileRecord.filter(Column("file_size") <= bytes).fetchAll(db).map { $0.fileId })
            }

        case .filenameContains(let text):
            return try await db.read { db in
                Set(try VideoFileRecord.filter(Column("filename").like("%\(Self.escapeLike(text))%", escape: "\\")).fetchAll(db).map { $0.fileId })
            }

        case .filenameStartsWith(let text):
            return try await db.read { db in
                Set(try VideoFileRecord.filter(Column("filename").like("\(Self.escapeLike(text))%", escape: "\\")).fetchAll(db).map { $0.fileId })
            }

        case .filenameEndsWith(let text):
            return try await db.read { db in
                Set(try VideoFileRecord.filter(Column("filename").like("%\(Self.escapeLike(text))", escape: "\\")).fetchAll(db).map { $0.fileId })
            }

        case .filenameRegex(let pattern):
            return try await db.read { db in
                guard pattern.count <= SmartListCriteria.maxPatternLength,
                      let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
                let allRecords = try VideoFileRecord.fetchAll(db)
                return Set(allRecords.filter { record in
                    regex.firstMatch(in: record.filename, range: NSRange(record.filename.startIndex..., in: record.filename)) != nil
                }.map { $0.fileId })
            }

        case .dateAddedAfter(let date):
            let epoch = date.timeIntervalSince1970
            return try await db.read { db in
                Set(try VideoFileRecord.filter(Column("created_at") > epoch).fetchAll(db).map { $0.fileId })
            }

        case .dateAddedBefore(let date):
            let epoch = date.timeIntervalSince1970
            return try await db.read { db in
                Set(try VideoFileRecord.filter(Column("created_at") < epoch).fetchAll(db).map { $0.fileId })
            }

        case .dateModifiedAfter(let date):
            let epoch = date.timeIntervalSince1970
            return try await db.read { db in
                Set(try VideoFileRecord.filter(Column("last_modified") > epoch).fetchAll(db).map { $0.fileId })
            }

        case .dateModifiedBefore(let date):
            let epoch = date.timeIntervalSince1970
            return try await db.read { db in
                Set(try VideoFileRecord.filter(Column("last_modified") < epoch).fetchAll(db).map { $0.fileId })
            }

        case .playCountMin(let value):
            return try await db.read { db in
                Set(try VideoFileRecord.filter(Column("play_count") >= value).fetchAll(db).map { $0.fileId })
            }

        case .playCountMax(let value):
            return try await db.read { db in
                Set(try VideoFileRecord.filter(Column("play_count") <= value).fetchAll(db).map { $0.fileId })
            }

        case .unplayed:
            return try await db.read { db in
                Set(try VideoFileRecord.filter(Column("play_count") == 0).fetchAll(db).map { $0.fileId })
            }

        case .unrated:
            return try await db.read { db in
                Set(try VideoFileRecord.filter(Column("rating") == 0).fetchAll(db).map { $0.fileId })
            }

        case .hasAnnotations(let value):
            return try await db.read { db in
                if value {
                    return Set(try VideoFileRecord.filter(Column("annotation_count") > 0).fetchAll(db).map { $0.fileId })
                } else {
                    return Set(try VideoFileRecord.filter(Column("annotation_count") == 0).fetchAll(db).map { $0.fileId })
                }
            }

        case .annotationCountMin(let value):
            return try await db.read { db in
                Set(try VideoFileRecord.filter(Column("annotation_count") >= value).fetchAll(db).map { $0.fileId })
            }

        case .annotationCountMax(let value):
            return try await db.read { db in
                Set(try VideoFileRecord.filter(Column("annotation_count") <= value).fetchAll(db).map { $0.fileId })
            }

        case .hasTextAnnotations(let value):
            return try await db.read { db in
                if value {
                    return Set(try String.fetchAll(
                        db,
                        sql: """
                            SELECT DISTINCT video_file_id
                            FROM video_annotations
                            WHERE text IS NOT NULL AND TRIM(text) <> ''
                            """
                    ))
                } else {
                    return Set(try String.fetchAll(
                        db,
                        sql: """
                            SELECT file_id
                            FROM video_files
                            WHERE file_id NOT IN (
                                SELECT DISTINCT video_file_id
                                FROM video_annotations
                                WHERE text IS NOT NULL AND TRIM(text) <> ''
                            )
                            """
                    ))
                }
            }

        case .annotationTextSearch(let text):
            guard let query = Self.annotationTextFTSQuery(for: text) else { return [] }
            return try await db.read { db in
                Set(try String.fetchAll(
                    db,
                    sql: """
                        SELECT DISTINCT video_file_id
                        FROM video_annotation_text_fts
                        WHERE video_annotation_text_fts MATCH ?
                        """,
                    arguments: [query]
                ))
            }

        case .hasTimeRanges(let value):
            return try await db.read { db in
                try Self.videoFileIdsWithPlayableTimeRanges(value, in: db)
            }

        case .simpleListInclude(let simpleListId):
            return try await db.read { db in
                let records = SimpleListVideoRecord.findByListId(simpleListId, in: db)
                return Set(records.map { $0.videoFileId })
            }

        case .smartListInclude(let smartListId):
            if visitedSmartListIds.contains(smartListId) {
                logger.warning("Circular smart list reference detected for \(smartListId), returning empty set")
                return []
            }

            guard let criteriaJSON = try await db.read({ db in
                try String.fetchOne(db, sql: "SELECT criteria FROM smart_lists WHERE id = ?", arguments: [smartListId])
            }),
            let criteriaData = criteriaJSON.data(using: .utf8) else {
                logger.warning("Smart list \(smartListId) not found or has no criteria")
                return []
            }

            guard let referencedCriteria = try? TolerantDateDecoding.makeDecoder().decode(SmartListCriteria.self, from: criteriaData) else {
                logger.warning("Smart list \(smartListId) has undecodable criteria, returning empty set")
                return []
            }

            var newVisited = visitedSmartListIds
            newVisited.insert(smartListId)
            return try await evaluateCriteria(referencedCriteria, db: db, visitedSmartListIds: newVisited)
        }
    }
}

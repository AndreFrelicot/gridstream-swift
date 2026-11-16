import Foundation

// MARK: - Smart list criteria (contract §2)
//
// The one criteria codec. Decoding is tolerant (dates per §1, non-UUID
// condition ids replaced, ratings and counts sent as fractional numbers
// rounded, a missing logic operator read as AND); encoding is canonical.

/// The filter conditions of a smart list, stored as JSON in `SmartListDTO.criteria`.
public struct SmartListCriteria: Hashable, Codable, Sendable {
    public var conditions: [FilterCondition]

    public init(conditions: [FilterCondition] = []) {
        self.conditions = conditions
    }
}

/// One filter condition and how it combines with the result so far.
public struct FilterCondition: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var criteriaType: CriteriaType
    public var logicOperator: LogicOperator

    private enum CodingKeys: String, CodingKey {
        case id, criteriaType, logicOperator
    }

    public init(id: UUID = UUID(), criteriaType: CriteriaType, logicOperator: LogicOperator = .and) {
        self.id = id
        self.criteriaType = criteriaType
        self.logicOperator = logicOperator
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Legacy clients sent non-UUID ids (web `Math.random()`): accept them and
        // assign a fresh UUID, which is what the canonical form stores.
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        criteriaType = try container.decode(CriteriaType.self, forKey: .criteriaType)
        logicOperator = try container.decodeIfPresent(LogicOperator.self, forKey: .logicOperator) ?? .and
    }
}

/// How a condition combines with the conditions before it.
public enum LogicOperator: String, Codable, CaseIterable, Sendable {
    case and = "AND"
    case or = "OR"
}

/// A rating range for one tag inside a `tagsInclude` condition.
public struct TagRatingFilter: Hashable, Codable, Sendable {
    public let tagId: UUID
    public var minRating: Int?
    public var maxRating: Int?

    private enum CodingKeys: String, CodingKey {
        case tagId, minRating, maxRating
    }

    public init(tagId: UUID, minRating: Int? = nil, maxRating: Int? = nil) {
        self.tagId = tagId
        self.minRating = minRating
        self.maxRating = maxRating
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagId = try container.decode(UUID.self, forKey: .tagId)
        minRating = try container.decodeRoundedIntIfPresent(forKey: .minRating)
        maxRating = try container.decodeRoundedIntIfPresent(forKey: .maxRating)
    }
}

public enum CriteriaType: Hashable, Codable, Sendable {
    case tagsInclude(tagIds: [UUID], tagRatings: [TagRatingFilter])
    case tagsExclude(tagIds: [UUID])
    case ratingMin(value: Int)
    case ratingMax(value: Int)
    case sourceDirectory(id: String)
    case fileSizeMin(megabytes: Double)
    case fileSizeMax(megabytes: Double)
    case filenameContains(text: String)
    case filenameStartsWith(text: String)
    case filenameEndsWith(text: String)
    case filenameRegex(pattern: String)
    case dateAddedAfter(date: Date)
    case dateAddedBefore(date: Date)
    case dateModifiedAfter(date: Date)
    case dateModifiedBefore(date: Date)
    case playCountMin(value: Int)
    case playCountMax(value: Int)
    case hasAnnotations(value: Bool)
    case annotationCountMin(value: Int)
    case annotationCountMax(value: Int)
    case hasTextAnnotations(value: Bool)
    case annotationTextSearch(text: String)
    case hasTimeRanges(value: Bool)
    case simpleListInclude(simpleListId: UUID)
    case smartListInclude(smartListId: UUID)
    case unplayed
    case unrated

    private enum CodingKeys: String, CodingKey {
        case type, tagIds, tagRatings, value, id, megabytes, text, pattern, date, simpleListId, smartListId
    }

    private enum TypeIdentifier: String, Codable {
        case tagsInclude, tagsExclude
        case ratingMin, ratingMax
        case sourceDirectory
        case fileSizeMin, fileSizeMax
        case filenameContains, filenameStartsWith, filenameEndsWith, filenameRegex
        case dateAddedAfter, dateAddedBefore, dateModifiedAfter, dateModifiedBefore
        case playCountMin, playCountMax
        case hasAnnotations, annotationCountMin, annotationCountMax
        case hasTextAnnotations, annotationTextSearch
        case hasTimeRanges
        case simpleListInclude
        case smartListInclude
        case unplayed, unrated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(TypeIdentifier.self, forKey: .type)

        switch type {
        case .tagsInclude:
            let tagIds = try container.decode([UUID].self, forKey: .tagIds)
            let tagRatings = try container.decodeIfPresent([TagRatingFilter].self, forKey: .tagRatings) ?? []
            self = .tagsInclude(tagIds: tagIds, tagRatings: tagRatings)
        case .tagsExclude:
            let tagIds = try container.decode([UUID].self, forKey: .tagIds)
            self = .tagsExclude(tagIds: tagIds)
        case .ratingMin:
            self = .ratingMin(value: try container.decodeRoundedInt(forKey: .value))
        case .ratingMax:
            self = .ratingMax(value: try container.decodeRoundedInt(forKey: .value))
        case .sourceDirectory:
            self = .sourceDirectory(id: try container.decode(String.self, forKey: .id))
        case .fileSizeMin:
            self = .fileSizeMin(megabytes: try container.decode(Double.self, forKey: .megabytes))
        case .fileSizeMax:
            self = .fileSizeMax(megabytes: try container.decode(Double.self, forKey: .megabytes))
        case .filenameContains:
            self = .filenameContains(text: try container.decode(String.self, forKey: .text))
        case .filenameStartsWith:
            self = .filenameStartsWith(text: try container.decode(String.self, forKey: .text))
        case .filenameEndsWith:
            self = .filenameEndsWith(text: try container.decode(String.self, forKey: .text))
        case .filenameRegex:
            self = .filenameRegex(pattern: try container.decode(String.self, forKey: .pattern))
        case .dateAddedAfter:
            self = .dateAddedAfter(date: try container.decode(Date.self, forKey: .date))
        case .dateAddedBefore:
            self = .dateAddedBefore(date: try container.decode(Date.self, forKey: .date))
        case .dateModifiedAfter:
            self = .dateModifiedAfter(date: try container.decode(Date.self, forKey: .date))
        case .dateModifiedBefore:
            self = .dateModifiedBefore(date: try container.decode(Date.self, forKey: .date))
        case .playCountMin:
            self = .playCountMin(value: try container.decodeRoundedInt(forKey: .value))
        case .playCountMax:
            self = .playCountMax(value: try container.decodeRoundedInt(forKey: .value))
        case .hasAnnotations:
            self = .hasAnnotations(value: try container.decode(Bool.self, forKey: .value))
        case .annotationCountMin:
            self = .annotationCountMin(value: try container.decodeRoundedInt(forKey: .value))
        case .annotationCountMax:
            self = .annotationCountMax(value: try container.decodeRoundedInt(forKey: .value))
        case .hasTextAnnotations:
            self = .hasTextAnnotations(value: try container.decode(Bool.self, forKey: .value))
        case .annotationTextSearch:
            self = .annotationTextSearch(text: try container.decode(String.self, forKey: .text))
        case .hasTimeRanges:
            self = .hasTimeRanges(value: try container.decode(Bool.self, forKey: .value))
        case .simpleListInclude:
            self = .simpleListInclude(simpleListId: try container.decode(UUID.self, forKey: .simpleListId))
        case .smartListInclude:
            self = .smartListInclude(smartListId: try container.decode(UUID.self, forKey: .smartListId))
        case .unplayed:
            self = .unplayed
        case .unrated:
            self = .unrated
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .tagsInclude(let tagIds, let tagRatings):
            try container.encode(TypeIdentifier.tagsInclude, forKey: .type)
            try container.encode(tagIds, forKey: .tagIds)
            try container.encode(tagRatings, forKey: .tagRatings)
        case .tagsExclude(let tagIds):
            try container.encode(TypeIdentifier.tagsExclude, forKey: .type)
            try container.encode(tagIds, forKey: .tagIds)
        case .ratingMin(let value):
            try container.encode(TypeIdentifier.ratingMin, forKey: .type)
            try container.encode(value, forKey: .value)
        case .ratingMax(let value):
            try container.encode(TypeIdentifier.ratingMax, forKey: .type)
            try container.encode(value, forKey: .value)
        case .sourceDirectory(let id):
            try container.encode(TypeIdentifier.sourceDirectory, forKey: .type)
            try container.encode(id, forKey: .id)
        case .fileSizeMin(let megabytes):
            try container.encode(TypeIdentifier.fileSizeMin, forKey: .type)
            try container.encode(megabytes, forKey: .megabytes)
        case .fileSizeMax(let megabytes):
            try container.encode(TypeIdentifier.fileSizeMax, forKey: .type)
            try container.encode(megabytes, forKey: .megabytes)
        case .filenameContains(let text):
            try container.encode(TypeIdentifier.filenameContains, forKey: .type)
            try container.encode(text, forKey: .text)
        case .filenameStartsWith(let text):
            try container.encode(TypeIdentifier.filenameStartsWith, forKey: .type)
            try container.encode(text, forKey: .text)
        case .filenameEndsWith(let text):
            try container.encode(TypeIdentifier.filenameEndsWith, forKey: .type)
            try container.encode(text, forKey: .text)
        case .filenameRegex(let pattern):
            try container.encode(TypeIdentifier.filenameRegex, forKey: .type)
            try container.encode(pattern, forKey: .pattern)
        case .dateAddedAfter(let date):
            try container.encode(TypeIdentifier.dateAddedAfter, forKey: .type)
            try container.encode(date, forKey: .date)
        case .dateAddedBefore(let date):
            try container.encode(TypeIdentifier.dateAddedBefore, forKey: .type)
            try container.encode(date, forKey: .date)
        case .dateModifiedAfter(let date):
            try container.encode(TypeIdentifier.dateModifiedAfter, forKey: .type)
            try container.encode(date, forKey: .date)
        case .dateModifiedBefore(let date):
            try container.encode(TypeIdentifier.dateModifiedBefore, forKey: .type)
            try container.encode(date, forKey: .date)
        case .playCountMin(let value):
            try container.encode(TypeIdentifier.playCountMin, forKey: .type)
            try container.encode(value, forKey: .value)
        case .playCountMax(let value):
            try container.encode(TypeIdentifier.playCountMax, forKey: .type)
            try container.encode(value, forKey: .value)
        case .hasAnnotations(let value):
            try container.encode(TypeIdentifier.hasAnnotations, forKey: .type)
            try container.encode(value, forKey: .value)
        case .annotationCountMin(let value):
            try container.encode(TypeIdentifier.annotationCountMin, forKey: .type)
            try container.encode(value, forKey: .value)
        case .annotationCountMax(let value):
            try container.encode(TypeIdentifier.annotationCountMax, forKey: .type)
            try container.encode(value, forKey: .value)
        case .hasTextAnnotations(let value):
            try container.encode(TypeIdentifier.hasTextAnnotations, forKey: .type)
            try container.encode(value, forKey: .value)
        case .annotationTextSearch(let text):
            try container.encode(TypeIdentifier.annotationTextSearch, forKey: .type)
            try container.encode(text, forKey: .text)
        case .hasTimeRanges(let value):
            try container.encode(TypeIdentifier.hasTimeRanges, forKey: .type)
            try container.encode(value, forKey: .value)
        case .simpleListInclude(let simpleListId):
            try container.encode(TypeIdentifier.simpleListInclude, forKey: .type)
            try container.encode(simpleListId, forKey: .simpleListId)
        case .smartListInclude(let smartListId):
            try container.encode(TypeIdentifier.smartListInclude, forKey: .type)
            try container.encode(smartListId, forKey: .smartListId)
        case .unplayed:
            try container.encode(TypeIdentifier.unplayed, forKey: .type)
        case .unrated:
            try container.encode(TypeIdentifier.unrated, forKey: .type)
        }
    }
}

// MARK: - Validation and canonical form

/// Why a criteria payload was rejected (mapped to HTTP 400 by the routes).
public struct CriteriaValidationError: Error, LocalizedError, Sendable {
    public let reason: String
    public var errorDescription: String? { reason }

    public init(reason: String) {
        self.reason = reason
    }
}

extension SmartListCriteria {
    /// Ratings in criteria are integers 0…10.
    public static let ratingRange = 0...10
    /// File sizes in criteria are megabytes, 0…10_000_000.
    public static let maxFileSizeMegabytes = 10_000_000.0
    /// Text, filename and regex patterns are at most 256 characters.
    public static let maxPatternLength = 256

    /// Decodes a client- or database-supplied criteria JSON string with the
    /// tolerant date strategy (contract §1).
    public static func decode(json: String) throws -> SmartListCriteria {
        guard let data = json.data(using: .utf8) else {
            throw CriteriaValidationError(reason: "Criteria must be UTF-8 JSON")
        }
        do {
            return try JSONDecoder.gridStream().decode(SmartListCriteria.self, from: data)
        } catch {
            throw CriteriaValidationError(reason: "Invalid criteria: \(Self.describe(error))")
        }
    }

    /// Decodes and validates criteria; throws `CriteriaValidationError` with a
    /// human-readable reason on any problem.
    public static func parseValidated(json: String) throws -> SmartListCriteria {
        let criteria = try decode(json: json)
        try criteria.validate()
        return criteria
    }

    /// Checks numeric bounds and pattern lengths.
    public func validate() throws {
        for (index, condition) in conditions.enumerated() {
            let position = "condition \(index + 1)"
            switch condition.criteriaType {
            case .ratingMin(let value), .ratingMax(let value):
                guard Self.ratingRange.contains(value) else {
                    throw CriteriaValidationError(reason: "\(position): rating must be between 0 and 10")
                }
            case .tagsInclude(_, let tagRatings):
                for filter in tagRatings {
                    for value in [filter.minRating, filter.maxRating].compactMap({ $0 }) where !Self.ratingRange.contains(value) {
                        throw CriteriaValidationError(reason: "\(position): tag rating must be between 0 and 10")
                    }
                }
            case .fileSizeMin(let megabytes), .fileSizeMax(let megabytes):
                guard megabytes.isFinite, megabytes >= 0, megabytes <= Self.maxFileSizeMegabytes else {
                    throw CriteriaValidationError(reason: "\(position): file size must be between 0 and 10000000 MB")
                }
            case .playCountMin(let value), .playCountMax(let value),
                 .annotationCountMin(let value), .annotationCountMax(let value):
                guard value >= 0 else {
                    throw CriteriaValidationError(reason: "\(position): count must not be negative")
                }
            case .filenameContains(let text), .filenameStartsWith(let text),
                 .filenameEndsWith(let text), .annotationTextSearch(let text):
                guard text.count <= Self.maxPatternLength else {
                    throw CriteriaValidationError(reason: "\(position): text must be at most 256 characters")
                }
            case .filenameRegex(let pattern):
                guard pattern.count <= Self.maxPatternLength else {
                    throw CriteriaValidationError(reason: "\(position): pattern must be at most 256 characters")
                }
                guard (try? NSRegularExpression(pattern: pattern)) != nil else {
                    throw CriteriaValidationError(reason: "\(position): invalid regular expression")
                }
            case .sourceDirectory, .dateAddedAfter, .dateAddedBefore, .dateModifiedAfter,
                 .dateModifiedBefore, .hasAnnotations, .hasTextAnnotations, .hasTimeRanges,
                 .simpleListInclude, .smartListInclude, .tagsExclude, .unplayed, .unrated:
                break
            }
        }
    }

    /// Canonical stored form: ISO 8601 dates without fractional seconds, UUID
    /// condition ids, sorted keys.
    public func canonicalJSON() throws -> String {
        String(decoding: try JSONEncoder.gridStreamCanonical().encode(self), as: UTF8.self)
    }

    /// Removes `tagId` from every tag condition. A tag condition left without
    /// any tag is dropped (an empty include would match nothing). Returns nil
    /// when the criteria did not reference the tag.
    public func removingTag(_ tagId: UUID) -> SmartListCriteria? {
        var changed = false
        var remaining: [FilterCondition] = []

        for var condition in conditions {
            switch condition.criteriaType {
            case .tagsInclude(let tagIds, let tagRatings):
                guard tagIds.contains(tagId) || tagRatings.contains(where: { $0.tagId == tagId }) else {
                    remaining.append(condition)
                    continue
                }
                changed = true
                let keptIds = tagIds.filter { $0 != tagId }
                guard !keptIds.isEmpty else { continue }
                condition.criteriaType = .tagsInclude(tagIds: keptIds, tagRatings: tagRatings.filter { $0.tagId != tagId })
                remaining.append(condition)
            case .tagsExclude(let tagIds):
                guard tagIds.contains(tagId) else {
                    remaining.append(condition)
                    continue
                }
                changed = true
                let keptIds = tagIds.filter { $0 != tagId }
                guard !keptIds.isEmpty else { continue }
                condition.criteriaType = .tagsExclude(tagIds: keptIds)
                remaining.append(condition)
            default:
                remaining.append(condition)
            }
        }

        return changed ? SmartListCriteria(conditions: remaining) : nil
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let context),
             DecodingError.typeMismatch(_, let context),
             DecodingError.valueNotFound(_, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
        case DecodingError.keyNotFound(let key, let context):
            let path = (context.codingPath + [key]).map(\.stringValue).joined(separator: ".")
            return "missing \(path)"
        default:
            return error.localizedDescription
        }
    }
}

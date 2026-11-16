import Foundation

// MARK: - Dates (contract §1)

/// Tolerant date decoding shared by every GridStream JSON decoder.
///
/// Accepted forms, tried in order (see contracts/decisions.md §1):
/// 1. ISO 8601 without fractional seconds (`2026-11-03T10:00:00Z`, Swift `.iso8601`),
/// 2. ISO 8601 with fractional seconds (`2026-11-03T10:00:00.123Z`, web `toISOString()`),
/// 3. date only `YYYY-MM-DD`, read as the start of that day in the current time zone,
/// 4. a JSON number, read as seconds since the reference date (legacy iPad
///    `JSONEncoder` default `.deferredToDate`).
///
/// Every encoder emits ISO 8601 UTC without fractional seconds (`.iso8601`).
public enum TolerantDateDecoding {
    public static let strategy: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()

        if let number = try? container.decode(Double.self) {
            guard number.isFinite else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Date number must be finite")
            }
            return Date(timeIntervalSinceReferenceDate: number)
        }

        let string = try container.decode(String.self)
        guard let date = date(from: string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date format: \(string)"
            )
        }
        return date
    }

    /// Parses a date string in any of the accepted string forms.
    public static func date(from string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        // Every encoder emits the plain form, so it is tried first. Each
        // formatter rejects the other form, so the order never changes a result.
        if let date = plainFormatter.date(from: trimmed) {
            return date
        }
        if let date = fractionalFormatter.date(from: trimmed) {
            return date
        }

        return dateOnly(from: trimmed)
    }

    // Shared because building an `ISO8601DateFormatter` costs far more than a
    // parse, and a catalog page decodes several dates per video.
    // `ISO8601DateFormatter` is thread-safe once configured.
    nonisolated(unsafe) private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    nonisolated(unsafe) private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// `YYYY-MM-DD` → start of that day in the current time zone.
    private static func dateOnly(from string: String) -> Date? {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else {
            return nil
        }
        return calendar.startOfDay(for: date)
    }

    /// A JSON decoder using the tolerant date strategy.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = strategy
        return decoder
    }
}

extension JSONDecoder {
    /// A decoder configured for GridStream API payloads (tolerant dates).
    public static func gridStream() -> JSONDecoder {
        TolerantDateDecoding.makeDecoder()
    }
}

extension JSONEncoder {
    /// An encoder configured for GridStream API payloads (ISO 8601 dates,
    /// no fractional seconds).
    public static func gridStream() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// The canonical encoder for stored JSON (smart list criteria): ISO 8601
    /// dates without fractional seconds and sorted keys.
    public static func gridStreamCanonical() -> JSONEncoder {
        let encoder = gridStream()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

// MARK: - Lenient numbers (contract §2)

extension KeyedDecodingContainer {
    /// Decodes an integer, accepting a JSON number with a fraction (rounded).
    /// Ratings are integers 0…10 but some clients send them as doubles.
    public func decodeRoundedInt(forKey key: Key) throws -> Int {
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        let double = try decode(Double.self, forKey: key)
        guard double.isFinite, abs(double) < 1e15 else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Number out of range")
        }
        return Int(double.rounded())
    }

    public func decodeRoundedIntIfPresent(forKey key: Key) throws -> Int? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try decodeRoundedInt(forKey: key)
    }
}

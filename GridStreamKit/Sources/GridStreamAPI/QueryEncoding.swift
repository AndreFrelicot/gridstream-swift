import Foundation

// MARK: - Query strings (contract §9)

extension URLComponents {
    /// Sets the query items and percent-encodes `+` as `%2B`.
    ///
    /// `URLComponents` leaves `+` literal, and the server (like most form
    /// decoders) reads a literal `+` as a space — so a regex `\d+` or a
    /// search for "C++" would be corrupted.
    public mutating func setQueryItemsEncodingPlus(_ items: [URLQueryItem]) {
        queryItems = items.isEmpty ? nil : items
        if let encoded = percentEncodedQuery {
            percentEncodedQuery = encoded.replacingOccurrences(of: "+", with: "%2B")
        }
    }
}

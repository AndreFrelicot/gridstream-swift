import Foundation
import GridStreamAPI
import Vapor

/// Shared validation of common query parameters (contract §9).
nonisolated enum QueryValidation {
    static let maxLimit = 10_000

    /// `limit` is clamped to 1…10_000.
    static func limit(_ value: Int?, default defaultValue: Int) -> Int {
        min(max(value ?? defaultValue, 1), maxLimit)
    }

    /// A negative `offset` is rejected with 400.
    static func offset(_ value: Int?) throws -> Int {
        let offset = value ?? 0
        guard offset >= 0 else {
            throw Abort(.badRequest, reason: "offset must not be negative")
        }
        return offset
    }

    /// Decodes and validates a `criteria` JSON string; invalid criteria → 400 with the reason.
    static func criteria(json: String) throws -> SmartListCriteria {
        do {
            return try SmartListCriteria.parseValidated(json: json)
        } catch let error as CriteriaValidationError {
            throw Abort(.badRequest, reason: error.reason)
        }
    }
}

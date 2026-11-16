//
//  APIContract.swift
//  gridstream-ipad
//
//  Client-side decoding helpers (see contracts/decisions.md). The
//  wire types, JSON coders and query helpers live in GridStreamKit
//  (`GridStreamAPI`).
//

import Foundation

// MARK: - Lossy collections (§3)

/// Decodes a value but never fails: an element that cannot be decoded
/// becomes `nil` instead of failing the enclosing array.
nonisolated struct FailableDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// An array that drops the elements it cannot decode, so one bad row never
/// fails the whole response.
nonisolated struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(_ elements: [Element]) {
        self.elements = elements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let wrapped = try container.decode([FailableDecodable<Element>].self)
        elements = wrapped.compactMap(\.value)
    }
}

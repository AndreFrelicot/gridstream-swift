//
//  APIClient.swift
//  gridstream-ipad
//
//  The one HTTP client for GridStream metadata endpoints (`/api/v1/...`).
//

import Foundation
import GridStreamAPI
import OSLog

/// Error thrown by `APIClient` for every metadata request.
enum APIError: Error, LocalizedError, Equatable, Sendable {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    /// A non-success response whose JSON body carried a `reason`.
    case serverError(message: String)
    case encodingError
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "Invalid URL")
        case .invalidResponse:
            return String(localized: "Invalid response from server")
        case .httpError(let statusCode):
            return String(localized: "Server returned HTTP \(statusCode)")
        case .serverError(let message):
            return message
        case .encodingError:
            return String(localized: "Failed to encode request")
        case .decodingError:
            return String(localized: "Failed to decode response")
        }
    }
}

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

/// Builds, sends and decodes metadata requests for one server.
///
/// - Requests go through `ServerSessionManager.data(for:serverURL:)`, so the
///   Bearer header and 401 handling stay in one place.
/// - Bodies use `JSONEncoder.gridStream()`, responses `JSONDecoder.gridStream()`
///   (tolerant dates, contract §1).
/// - Query strings encode `+` as `%2B` (contract §9).
///
/// Media URLs (stream, thumbnail, scrub frames, capture images) are not built
/// here: AVPlayer and image loaders need the `token` query item that
/// `VideoURLBuilder` adds.
@MainActor
struct APIClient {
    let serverURL: URL
    let session: ServerSessionManager

    init(serverURL: URL, session: ServerSessionManager? = nil) {
        self.serverURL = serverURL
        self.session = session ?? .shared
    }

    // MARK: - Requests

    /// Builds an authorized request for `api/v1/<path>`.
    func request(
        _ method: HTTPMethod,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        timeout: TimeInterval? = nil
    ) throws -> URLRequest {
        var url = serverURL.appendingPathComponent("api/v1/" + path)
        if !query.isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
                throw APIError.invalidURL
            }
            components.setQueryItemsEncodingPlus(query)
            guard let queryURL = components.url else {
                throw APIError.invalidURL
            }
            url = queryURL
        }

        var request = session.buildAuthenticatedRequest(url: url, method: method.rawValue, serverURL: serverURL)
        if let timeout {
            request.timeoutInterval = timeout
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder.gridStream().encode(body)
        }
        return request
    }

    /// Sends `request` without checking the status code.
    func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request, serverURL: serverURL)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        return (data, httpResponse)
    }

    /// Sends a request and returns the body when the status is in `expecting`.
    /// Any other status throws `.serverError` with the body's `reason`, or
    /// `.httpError` when there is none.
    @discardableResult
    func send(
        _ method: HTTPMethod,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        expecting: Set<Int> = [200]
    ) async throws -> Data {
        let request = try request(method, path, query: query, body: body)
        let (data, response) = try await response(for: request)
        guard expecting.contains(response.statusCode) else {
            AppLogger.video.error("\(method.rawValue) \(path) failed: HTTP \(response.statusCode)")
            throw Self.error(status: response.statusCode, body: data)
        }
        return data
    }

    /// Sends a GET request and decodes the response body as `T`.
    func fetch<T: Decodable>(_ type: T.Type, _ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await fetch(type, .get, path, query: query)
    }

    /// Sends a request and decodes the response body as `T`.
    func fetch<T: Decodable>(
        _ type: T.Type,
        _ method: HTTPMethod,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (any Encodable)? = nil,
        expecting: Set<Int> = [200]
    ) async throws -> T {
        let data = try await send(method, path, query: query, body: body, expecting: expecting)
        return try decode(type, from: data)
    }

    /// Like `fetch`, but a 404 returns `nil` instead of throwing.
    func fetchIfPresent<T: Decodable>(_ type: T.Type, _ path: String) async throws -> T? {
        let (data, response) = try await response(for: request(.get, path))
        if response.statusCode == 404 {
            return nil
        }
        guard response.statusCode == 200 else {
            AppLogger.video.error("GET \(path) failed: HTTP \(response.statusCode)")
            throw Self.error(status: response.statusCode, body: data)
        }
        return try decode(type, from: data)
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder.gridStream().decode(type, from: data)
    }

    // MARK: - Errors

    private struct ErrorBody: Decodable {
        let reason: String?
    }

    static func error(status: Int, body: Data) -> APIError {
        if let reason = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.reason {
            return .serverError(message: reason)
        }
        return .httpError(statusCode: status)
    }
}

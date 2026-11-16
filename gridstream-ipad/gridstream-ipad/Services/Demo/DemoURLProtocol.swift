//
//  DemoURLProtocol.swift
//  gridstream-ipad
//
//  Answers requests to the demo host with `DemoServer`, inside the app.
//  Registered on the API session (`ServerSessionManager.makeAPISession`) and
//  globally for `URLSession.shared` (AsyncImage). It claims nothing else, so
//  a real server is never affected.
//

import Foundation

nonisolated final class DemoURLProtocol: URLProtocol, @unchecked Sendable {
    /// The server answering requests. Replaceable in tests.
    nonisolated(unsafe) static var server = DemoServer.shared

    private var loadingTask: Task<Void, Never>?

    override class func canInit(with request: URLRequest) -> Bool {
        DemoMode.isDemo(request.url)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let method = request.httpMethod ?? "GET"
        let body = Self.body(of: request)
        let server = Self.server

        loadingTask = Task { @Sendable [weak self] in
            let response = await server.handle(method: method, url: url, body: body)
            guard let self, !Task.isCancelled else { return }

            var headers = ["Content-Length": String(response.body.count)]
            if let contentType = response.contentType {
                headers["Content-Type"] = contentType
            }
            guard let httpResponse = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: headers) else {
                self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            self.client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            if method != "HEAD" {
                self.client?.urlProtocol(self, didLoad: response.body)
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        loadingTask?.cancel()
        loadingTask = nil
    }

    /// URLSession moves a request's body into `httpBodyStream`.
    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }

        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

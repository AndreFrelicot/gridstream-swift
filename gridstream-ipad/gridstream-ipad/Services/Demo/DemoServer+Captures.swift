import AVFoundation
import Foundation
import GridStreamAPI
import UIKit

extension DemoServer {
    func routeCaptures(_ request: DemoRequest) async throws -> DemoResponse? {
        // Frame captures
        if let params = request.on("POST", "videos/:fileId/captures") {
            let fileId = params[0]
            return .json(try await createCapture(fileId: fileId, try decode(CreateFrameCaptureRequest.self, request.body)), status: 201)
        }
        if let params = request.on("GET", "videos/:fileId/captures") {
            let fileId = params[0]
            let store = try loadedStore()
            let captures = store.captures.filter { $0.fileId == fileId }.sorted { $0.timestamp < $1.timestamp }
            return .json(FrameCaptureListResponse(captures: captures.map(store.captureDTO), total: captures.count))
        }
        if request.on("GET", "captures") != nil {
            return .json(try listCaptures(query: request.query))
        }
        if let params = request.on("DELETE", "captures/:captureId") {
            let captureId = params[0]
            try deleteCapture(captureId)
            return .empty(204)
        }
        if let params = request.on("GET", "captures/:captureId/image") {
            let captureId = params[0]
            guard try loadedStore().captures.contains(where: { $0.id == captureId }),
                  let data = try? Data(contentsOf: captureFile(captureId)) else {
                throw DemoHTTPError.notFound("Capture not found")
            }
            return .jpeg(data)
        }
        return nil
    }

    // MARK: - Captures

    private func createCapture(fileId: String, _ request: CreateFrameCaptureRequest) async throws -> FrameCaptureDTO {
        guard request.timestamp >= 0 else { throw DemoHTTPError.badRequest("Timestamp must be non-negative") }
        _ = try requireVideo(fileId, in: try loadedStore())
        guard let clip = clipFile(fileId) else {
            throw DemoHTTPError.notFound("Video file not found")
        }

        let frame = try await Self.jpegFrame(from: clip, at: request.timestamp, exact: true, maximumSize: nil, quality: 0.9)
        let id = UUID().uuidString
        try FileManager.default.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)
        try frame.data.write(to: captureFile(id), options: .atomic)

        // Captures are not a catalog change on the server: no version bump.
        var updated = try loadedStore()
        let capture = DemoStore.Capture(
            id: id, fileId: fileId, timestamp: request.timestamp, width: frame.width, height: frame.height,
            fileSize: frame.data.count, createdAt: Date()
        )
        updated.captures.append(capture)
        store = updated
        try persist()
        return updated.captureDTO(capture)
    }

    private func listCaptures(query: [String: String]) throws -> FrameCaptureListResponse {
        let store = try loadedStore()
        let limit = min(max(Int(query["limit"] ?? "") ?? 50, 1), 10_000)
        let offset = Int(query["offset"] ?? "") ?? 0
        guard offset >= 0 else { throw DemoHTTPError.badRequest("offset must not be negative") }

        var captures = store.captures
        if let fileId = query["fileId"] {
            captures = captures.filter { $0.fileId == fileId }
        }
        if let json = query["criteria"] {
            let criteria: SmartListCriteria
            do {
                criteria = try SmartListCriteria.parseValidated(json: json)
            } catch let error as CriteriaValidationError {
                throw DemoHTTPError.badRequest(error.reason)
            }
            let allowed = DemoCriteriaEvaluator(store: store).fileIds(matching: criteria)
            captures = captures.filter { allowed.contains($0.fileId) }
        }
        let page = captures.sorted { $0.createdAt > $1.createdAt }.dropFirst(offset).prefix(limit)
        return FrameCaptureListResponse(captures: page.map(store.captureDTO), total: captures.count)
    }

    private func deleteCapture(_ id: String) throws {
        var updated = try loadedStore()
        guard updated.captures.contains(where: { $0.id == id }) else {
            throw DemoHTTPError.notFound("Capture not found")
        }
        updated.captures.removeAll { $0.id == id }
        store = updated
        try? FileManager.default.removeItem(at: captureFile(id))
        try persist()
    }

    private func captureFile(_ id: String) -> URL {
        capturesDirectory.appendingPathComponent("\(id).jpg")
    }
}

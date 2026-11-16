import Foundation
import GridStreamAPI

extension DemoServer {
    func routeAnnotations(_ request: DemoRequest) throws -> DemoResponse? {
        // Annotations
        if let params = request.on("GET", "videos/:fileId/annotations") {
            let fileId = params[0]
            let annotations = try loadedStore().annotations
                .filter { $0.videoFileId == fileId }
                .sorted { $0.frameTime < $1.frameTime }
            return .json(AnnotationListResponse(annotations: annotations, total: annotations.count))
        }
        if let params = request.on("GET", "videos/:fileId/annotations/times") {
            let fileId = params[0]
            let times = try loadedStore().annotations.filter { $0.videoFileId == fileId }.map(\.frameTime).sorted()
            return .json(AnnotationTimesResponse(times: times))
        }
        if let params = request.on("PUT", "videos/:fileId/annotations") {
            let fileId = params[0]
            return .json(try upsertAnnotation(fileId: fileId, try decode(UpsertAnnotationRequest.self, request.body)))
        }
        if let params = request.on("DELETE", "videos/:fileId/annotations/:annotationId") {
            let fileId = params[0]
            let annotationId = params[1]
            try deleteAnnotation(try Self.uuid(annotationId, label: "annotation"), fileId: fileId)
            return .empty(204)
        }
        return nil
    }

    // MARK: - Annotations

    private func upsertAnnotation(fileId: String, _ request: UpsertAnnotationRequest) throws -> AnnotationDTO {
        guard request.frameRate > 0 else { throw DemoHTTPError.badRequest("Frame rate must be positive") }
        let text = request.text.flatMap { $0.isEmpty ? nil : $0 }
        return try write { store in
            _ = try requireVideo(fileId, in: store)
            let now = Date()
            if let index = store.annotations.firstIndex(where: { $0.videoFileId == fileId && $0.frameTime == request.frameTime }) {
                let existing = store.annotations[index]
                let updated = AnnotationDTO(
                    id: existing.id, videoFileId: fileId, frameTime: existing.frameTime, frameRate: request.frameRate,
                    strokesJSON: request.strokesJSON, text: text, createdAt: existing.createdAt, updatedAt: now
                )
                store.annotations[index] = updated
                return updated
            }
            let created = AnnotationDTO(
                id: UUID(), videoFileId: fileId, frameTime: request.frameTime, frameRate: request.frameRate,
                strokesJSON: request.strokesJSON, text: text, createdAt: now, updatedAt: now
            )
            store.annotations.append(created)
            return created
        }
    }

    private func deleteAnnotation(_ id: UUID, fileId: String) throws {
        try write { store in
            guard store.annotations.contains(where: { $0.id == id && $0.videoFileId == fileId }) else {
                throw DemoHTTPError.notFound("Annotation not found for this video")
            }
            store.annotations.removeAll { $0.id == id }
        }
    }
}

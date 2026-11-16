import Foundation
import GridStreamAPI
import OSLog

@MainActor
final class AnnotationAPIService {
    private let sessionManager: ServerSessionManager

    init(sessionManager: ServerSessionManager? = nil) {
        self.sessionManager = sessionManager ?? .shared
    }

    // Explicit teardown avoids the isolated-deinit back-deploy shim when
    // SwiftUI releases this service outside a Swift task.
    deinit {}

    private func api(_ serverURL: URL) -> APIClient {
        APIClient(serverURL: serverURL, session: sessionManager)
    }

    // MARK: - Fetch Annotations

    func fetchAnnotations(forFileId fileId: String, serverURL: URL) async throws -> [AnnotationDTO] {
        try await api(serverURL).fetch(AnnotationListResponse.self, "videos/\(fileId)/annotations").annotations
    }

    // MARK: - Upsert Annotation

    func upsertAnnotation(
        forFileId fileId: String,
        frameTime: Double,
        frameRate: Double,
        strokesJSON: String,
        text: String?,
        serverURL: URL
    ) async throws -> AnnotationDTO {
        try await api(serverURL).fetch(
            AnnotationDTO.self, .put, "videos/\(fileId)/annotations",
            body: UpsertAnnotationRequest(frameTime: frameTime, frameRate: frameRate, strokesJSON: strokesJSON, text: text)
        )
    }

    // MARK: - Delete Annotation

    func deleteAnnotation(forFileId fileId: String, annotationId: String, serverURL: URL) async throws {
        try await api(serverURL).send(.delete, "videos/\(fileId)/annotations/\(annotationId)", expecting: [204])
    }
}

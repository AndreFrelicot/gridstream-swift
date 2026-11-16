import Foundation
import GridStreamAPI
import Vapor
import NIOFoundationCompat
@testable import gridstream_macos

/// Helpers for tests that call the real `VideoStreamRoutes` (no auth
/// middleware) over files in a temporary folder.
enum StreamRouteTesting {
    /// An application serving `videos` through the stream route.
    static func makeApp(videos: [VideoItem], sourceDirectories: [SourceDirectory]) async throws -> Application {
        var env = try Environment.detect()
        env.arguments = ["vapor", "test"]
        let app = try await Application.make(env)
        app.middleware.use(ErrorMiddleware.default(environment: app.environment))
        app.storage[VideoCatalogStorageKey.self] = TestVideoCatalog(videos: videos, sourceDirectories: sourceDirectories)
        try app.register(collection: VideoStreamRoutes())
        return app
    }

    /// `GET /api/v1/videos/:fileId/stream`, without recording a playback session.
    static func stream(_ fileId: String, range: String? = nil, in app: Application) async throws -> Response {
        var headers = HTTPHeaders()
        if let range {
            headers.add(name: .range, value: range)
        }
        return try await app.sendRequest(.GET, "/api/v1/videos/\(fileId)/stream?stats=client", headers: headers)
    }

    /// The response body, collected from the file stream.
    static func body(of response: Response, in app: Application) async throws -> Data {
        guard let buffer = try await response.body.collect(on: app.eventLoopGroup.next()).get() else {
            return Data()
        }
        return Data(buffer: buffer)
    }

    static func video(_ fileId: String, relativePath: String, in sourceDirectory: SourceDirectory) -> VideoItem {
        VideoItem(
            fileId: fileId,
            filename: (relativePath as NSString).lastPathComponent,
            relativePath: relativePath,
            sourceDirectoryId: sourceDirectory.id,
            duration: 10,
            width: 1,
            height: 1,
            codec: "h264",
            fileSize: 0,
            lastModified: Date()
        )
    }
}

private final class TestVideoCatalog: VideoCatalogProvider, @unchecked Sendable {
    // `@unchecked Sendable`: both properties are immutable after init.
    private let videos: [VideoItem]
    private let sourceDirectories: [SourceDirectory]

    init(videos: [VideoItem], sourceDirectories: [SourceDirectory]) {
        self.videos = videos
        self.sourceDirectories = sourceDirectories
    }

    func getVideos() -> [VideoItem] { videos }
    func getSourceDirectories() -> [SourceDirectory] { sourceDirectories }
    func getVideoByFileId(_ fileId: String) -> VideoItem? { videos.first { $0.fileId == fileId } }
}

import Foundation
import GridStreamAPI
import OSLog
import Vapor

nonisolated enum ServerError: LocalizedError {
    case alreadyRunning
    case notRunning
    case portInUse(Int)
    case startupFailed(Error)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Server is already running"
        case .notRunning:
            return "Server is not running"
        case .portInUse(let port):
            return "Port \(port) is already in use"
        case .startupFailed(let error):
            return "Server failed to start: \(error.localizedDescription)"
        }
    }
}

private actor ServerStartupSignal {
    private var result: Result<Void, Error>?
    private var continuations: [CheckedContinuation<Void, Error>] = []

    func wait() async throws {
        if let result {
            try result.get()
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func complete(_ result: Result<Void, Error>) {
        guard self.result == nil else { return }

        self.result = result
        let pendingContinuations = continuations
        continuations.removeAll()

        for continuation in pendingContinuations {
            continuation.resume(with: result)
        }
    }
}

// Sendable: `snapshot` is mutated only under `lock` (NSLock). All public accessors acquire the lock.
nonisolated final class DefaultVideoCatalogProvider: VideoCatalogProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot = VideoCatalogSnapshot(videos: [], sourceDirectories: [])

    var videos: [VideoItem] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return snapshot.videos
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            snapshot = VideoCatalogSnapshot(videos: newValue, sourceDirectories: snapshot.sourceDirectories)
        }
    }

    var sourceDirectories: [SourceDirectory] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return snapshot.sourceDirectories
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            snapshot = VideoCatalogSnapshot(videos: snapshot.videos, sourceDirectories: newValue)
        }
    }

    func update(videos: [VideoItem], sourceDirectories: [SourceDirectory]) {
        lock.lock()
        defer { lock.unlock() }
        snapshot = VideoCatalogSnapshot(videos: videos, sourceDirectories: sourceDirectories)
    }

    func getVideos() -> [VideoItem] {
        videos
    }

    func getSourceDirectories() -> [SourceDirectory] {
        sourceDirectories
    }

    func getVideoByFileId(_ fileId: String) -> VideoItem? {
        lock.lock()
        defer { lock.unlock() }
        return snapshot.videos.first { $0.fileId == fileId }
    }

    func getSnapshot() -> VideoCatalogSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }
}

@MainActor
@Observable
final class ServerManager {
    private(set) var isRunning = false
    private(set) var currentPort: Int?

    private let logger = Logger(subsystem: "com.gridstream.macos", category: "ServerManager")
    @ObservationIgnored private var application: Application?
    @ObservationIgnored private var serverTask: Task<Void, Never>?
    /// True while `start` is in progress, so a concurrent start cannot replace
    /// the application of a server that is coming up.
    @ObservationIgnored private var isStarting = false
    private let bonjourService = BonjourService()
    /// Devices, streams and the connection log, for the windows.
    let activity = ConnectionActivity()
    private let catalogProvider = DefaultVideoCatalogProvider()
    private let databaseManager: DatabaseManager
    private let defaults: UserDefaults

    /// True when this build of the app contains the web UI.
    static let isWebUIBundled = FileManager.default.fileExists(atPath: resolvePublicDirectory() + "browser/index.html")

    init(databaseManager: DatabaseManager, defaults: UserDefaults = .standard) {
        self.databaseManager = databaseManager
        self.defaults = defaults
    }

    func updateVideoCatalog(_ videos: [VideoItem]) {
        catalogProvider.videos = videos
    }

    func updateSourceDirectories(_ directories: [SourceDirectory]) {
        catalogProvider.sourceDirectories = directories
    }

    func updateCatalog(videos: [VideoItem], sourceDirectories: [SourceDirectory]) {
        catalogProvider.update(videos: videos, sourceDirectories: sourceDirectories)
    }

    func start(port: Int) async throws {
        guard !isRunning, !isStarting else {
            throw ServerError.alreadyRunning
        }
        isStarting = true
        defer { isStarting = false }

        logger.info("Starting server on port \(port)")

        do {
            let app = try await createApplication(port: port)
            self.application = app
            let startupSignal = ServerStartupSignal()

            serverTask = Task.detached { [weak self, startupSignal] in
                do {
                    try app.server.start()
                    await startupSignal.complete(.success(()))
                    try await app.server.onShutdown.get()
                } catch {
                    await startupSignal.complete(.failure(error))
                    await self?.handleServerError(error)
                }
            }

            try await startupSignal.wait()

            isRunning = true
            await StreamSessionTracker.shared.startProcessing()
            currentPort = port
            activity.serverDidStart(port: port)

            bonjourService.publish(port: port)

            logger.info("Server started successfully on port \(port)")
        } catch {
            logger.error("Failed to start server: \(error.localizedDescription)")

            if let app = application {
                try? await app.asyncShutdown()
                application = nil
            }

            if isPortInUseError(error) {
                throw ServerError.portInUse(port)
            }

            throw ServerError.startupFailed(error)
        }
    }

    func stop() async throws {
        guard isRunning, let app = application else {
            throw ServerError.notRunning
        }

        logger.info("Stopping server")

        bonjourService.stop()
        await StreamSessionTracker.shared.stopProcessing()

        await app.server.shutdown()

        serverTask?.cancel()
        serverTask = nil

        // Drain pending DB writes after request handlers have stopped but
        // before the Vapor app tears down, so deferred catalog/stats writes
        // queued by in-flight handlers are committed instead of dropped.
        await databaseManager.drain()

        try await app.asyncShutdown()
        application = nil

        isRunning = false
        currentPort = nil
        activity.serverDidStop()

        logger.info("Server stopped successfully")
    }

    private func createApplication(port: Int) async throws -> Application {
        // Release builds run in production: no error details in responses
        #if DEBUG
        var env = try Environment.detect()
        #else
        var env = Environment.production
        #endif
        env.arguments = ["serve"]

        let app = try await Application.make(env)

        app.http.server.configuration.hostname = "0.0.0.0"
        app.http.server.configuration.port = port

        app.storage[VideoCatalogStorageKey.self] = catalogProvider
        app.serverAuthManager = ServerAuthManager()
        app.loginRateLimiter = LoginRateLimiter()
        app.connectionMonitor = activity.monitor

        configureMiddleware(app)
        try configureRoutes(app)

        return app
    }

    private func configureMiddleware(_ app: Application) {
        Self.configureSecurityMiddleware(app)

        // Serve Angular web app if Public/browser/index.html exists, while
        // the web UI setting is on
        guard Self.isWebUIBundled else { return }
        let publicDir = Self.resolvePublicDirectory()
        // UserDefaults is thread-safe but not declared Sendable
        nonisolated(unsafe) let defaults = self.defaults
        app.middleware.use(WebUIMiddleware(publicDirectory: publicDir) {
            ConfigurationService.webUIEnabled(in: defaults)
        })
        logger.info("Web app available: serving static files from \(publicDir)")
    }

    /// Middleware shared by the server and the tests: query-token stripping
    /// and security headers wrap everything (outermost), the DNS-rebinding
    /// guard runs inside the error middleware so its 403 is rendered.
    nonisolated static func configureSecurityMiddleware(_ app: Application) {
        app.middleware.use(SecurityHeadersMiddleware(), at: .beginning)
        app.middleware.use(QueryTokenMiddleware(), at: .beginning)
        app.middleware.use(ErrorMiddleware.default(environment: app.environment))
        app.middleware.use(HostGuardMiddleware())
    }

    private static func resolvePublicDirectory() -> String {
        // Check bundle resources first (when built into the macOS app)
        if let resourcePath = Bundle.main.resourcePath {
            let bundlePath = resourcePath + "/Public/"
            if FileManager.default.fileExists(atPath: bundlePath) {
                return bundlePath
            }
        }

        // Fall back to relative path (development)
        let relativePath = FileManager.default.currentDirectoryPath + "/Public/"
        return relativePath
    }

    private func configureRoutes(_ app: Application) throws {
        try app.register(collection: HealthRoutes())
        try app.register(collection: AuthRoutes())

        // Media routes: a session is required when auth is enabled; AVPlayer and
        // AsyncImage may pass it as the `token` query item
        let media = app.grouped(SessionAuthMiddleware(allowQueryToken: true), ActivityTrackingMiddleware())
        try media.register(collection: VideoStreamRoutes())
        try media.register(collection: ThumbnailRoutes(databaseManager: databaseManager))
        try media.register(collection: ScrubRoutes(databaseManager: databaseManager))
        try media.register(collection: FrameCaptureImageRoutes(databaseManager: databaseManager))

        // Authenticated routes - metadata and all mutations require auth.
        // Only authenticated and media requests count as client activity.
        let authenticated = app.grouped(SessionAuthMiddleware(), ActivityTrackingMiddleware())
        try authenticated.register(collection: ThumbnailRoutes(databaseManager: databaseManager, mode: .authenticatedWrite))
        try authenticated.register(collection: ScrubRoutes(databaseManager: databaseManager, mode: .authenticatedWrite))
        try authenticated.register(collection: VideoRoutes(databaseManager: databaseManager))
        try authenticated.register(collection: TagRoutes(databaseManager: databaseManager))
        try authenticated.register(collection: VideoTagRoutes(databaseManager: databaseManager))
        try authenticated.register(collection: RatingRoutes(databaseManager: databaseManager))
        try authenticated.register(collection: PlaybackStatsRoutes(databaseManager: databaseManager))
        try authenticated.register(collection: CatalogRoutes(databaseManager: databaseManager))
        try authenticated.register(collection: SmartListRoutes(databaseManager: databaseManager))
        try authenticated.register(collection: SimpleListRoutes(databaseManager: databaseManager))
        try authenticated.register(collection: TimeRangeRoutes(databaseManager: databaseManager))
        try authenticated.register(collection: AnnotationRoutes(databaseManager: databaseManager))
        try authenticated.register(collection: FrameCaptureRoutes(databaseManager: databaseManager))
    }

    private func handleServerError(_ error: Error) async {
        logger.error("Server error: \(error.localizedDescription)")

        bonjourService.stop()
        await StreamSessionTracker.shared.stopProcessing()

        isRunning = false
        currentPort = nil
        activity.serverDidStop()

        if let app = application {
            try? await app.asyncShutdown()
            application = nil
        }
    }

    private func isPortInUseError(_ error: Error) -> Bool {
        let errorDescription = error.localizedDescription.lowercased()
        return errorDescription.contains("address already in use") ||
               errorDescription.contains("eaddrinuse")
    }

    deinit {
        serverTask?.cancel()
    }
}

/// Counts authenticated requests as client activity: for the scrub preloader,
/// which waits for quiet, and for the connection monitor.
nonisolated struct ActivityTrackingMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        await ClientActivityTracker.shared.recordActivity()
        guard let monitor = request.application.connectionMonitor else {
            return try await next.respond(to: request)
        }

        let response: Response
        do {
            response = try await next.respond(to: request)
        } catch {
            monitor.recordRequest(from: request.clientAddress, userAgent: request.userAgent)
            throw error
        }
        // A metered video body reports its own bytes as they are written
        let isMetered = request.storage[MeteredStreamStorageKey.self] == true
        monitor.recordRequest(
            from: request.clientAddress,
            userAgent: request.userAgent,
            bytesSent: isMetered ? 0 : max(0, response.body.count)
        )
        return response
    }
}

/// Set on a request whose response body is counted by a `StreamMeter`.
nonisolated struct MeteredStreamStorageKey: StorageKey {
    typealias Value = Bool
}

import Foundation
import OSLog

@MainActor
@Observable
final class ConfigurationService {
    nonisolated private enum Keys {
        static let serverPort = "serverPort"
        static let dataDirectory = "dataDirectory"
        static let webUIEnabled = "webUIEnabled"
    }

    private let defaults: UserDefaults
    private let authStore: ServerAuthConfigurationStore
    private let databaseManager: DatabaseManager
    private let logger = Logger(subsystem: "com.gridstream.macos", category: "ConfigurationService")
    @ObservationIgnored private var accessedURLs: [UUID: URL] = [:]

    /// The default data directory under Application Support
    static var defaultDataDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("GridStream", isDirectory: true)
    }

    /// The configured data directory. Changes require an app restart to take effect.
    var dataDirectory: URL {
        didSet {
            defaults.set(dataDirectory.path, forKey: Keys.dataDirectory)
            logger.info("Data directory changed to: \(self.dataDirectory.path)")
        }
    }

    /// Changes the data directory (effective after restart). With
    /// `moveDatabase`, the current database is moved there on next launch.
    func changeDataDirectory(to url: URL, moveDatabase: Bool) {
        let current = dataDirectory
        guard url.standardizedFileURL != current.standardizedFileURL else { return }
        if moveDatabase {
            defaults.set(current.path, forKey: DataDirectoryMigration.pendingMoveKey)
        } else {
            defaults.removeObject(forKey: DataDirectoryMigration.pendingMoveKey)
        }
        dataDirectory = url
    }

    var serverPort: Int {
        didSet {
            defaults.set(serverPort, forKey: Keys.serverPort)
        }
    }

    /// Whether the server answers browsers with the web UI. The server reads
    /// it on every request, so a change applies without a restart.
    var webUIEnabled: Bool {
        didSet {
            defaults.set(webUIEnabled, forKey: Keys.webUIEnabled)
        }
    }

    /// The stored web UI setting; on by default. Readable off the main actor.
    nonisolated static func webUIEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: Keys.webUIEnabled) as? Bool ?? true
    }

    private(set) var authEnabled: Bool
    private(set) var pinConfigured: Bool
    private(set) var sessionTTLDays: Int
    private(set) var pinRevision: Int
    /// PIN generated on first launch, shown in the menu bar and Settings until
    /// the user sets their own.
    private(set) var generatedPIN: String?

    var sourceDirectories: [SourceDirectory] = []

    /// Source folders the last scan could not read. Their videos are kept as
    /// they are until the folder becomes reachable again.
    var unavailableDirectoryIds: Set<UUID> = []

    /// `secrets` holds the auth token secret and PIN; tests pass their own store.
    init(
        databaseManager: DatabaseManager,
        defaults: UserDefaults = .standard,
        secrets: SecretStore = KeychainSecretStore()
    ) {
        self.databaseManager = databaseManager
        self.defaults = defaults
        self.authStore = ServerAuthConfigurationStore(defaults: defaults, secrets: secrets)

        let savedPort = defaults.integer(forKey: Keys.serverPort)
        self.serverPort = savedPort > 0 ? savedPort : 8080
        self.webUIEnabled = Self.webUIEnabled(in: defaults)

        if let savedPath = defaults.string(forKey: Keys.dataDirectory), !savedPath.isEmpty {
            self.dataDirectory = URL(fileURLWithPath: savedPath, isDirectory: true)
        } else {
            self.dataDirectory = Self.defaultDataDirectory
        }

        // Auth is on by default: generate a PIN when none exists yet
        do {
            if try authStore.ensureDefaultPIN() != nil {
                logger.info("Generated a server PIN and enabled authentication")
            }
        } catch {
            logger.error("Failed to generate a default server PIN: \(error.localizedDescription)")
        }

        let authConfiguration = authStore.load()
        self.generatedPIN = authConfiguration.generatedPIN
        self.authEnabled = authConfiguration.requiresAuthentication
        self.pinConfigured = authConfiguration.hasPIN
        self.sessionTTLDays = authConfiguration.sessionTTLDays
        self.pinRevision = authConfiguration.pinRevision
    }

    /// Loads source directories from the database.
    /// Should be called after database initialization.
    func loadFromDatabase() async {
        do {
            let directories = try await databaseManager.fetchSourceDirectories()
            sourceDirectories = directories
            logger.info("Loaded \(directories.count) source directories from database")
        } catch {
            logger.error("Failed to load source directories from database: \(error.localizedDescription)")
        }
    }

    private func saveSourceDirectoryToDatabase(_ directory: SourceDirectory) {
        Task {
            do {
                try await databaseManager.saveSourceDirectory(directory)
            } catch {
                logger.error("Failed to save source directory to database: \(error.localizedDescription)")
            }
        }
    }

    private func deleteSourceDirectoryFromDatabase(id: UUID) {
        Task {
            do {
                try await databaseManager.deleteSourceDirectory(id: id)
            } catch {
                logger.error("Failed to delete source directory from database: \(error.localizedDescription)")
            }
        }
    }

    /// Rejects a folder that is already configured, nested inside a configured
    /// folder, or containing one: overlapping folders list the same files twice.
    func validateNewDirectory(path: String) throws {
        try Self.validateNewDirectory(path: path, existingPaths: sourceDirectories.map(\.path))
    }

    nonisolated static func validateNewDirectory(path: String, existingPaths: [String]) throws {
        let candidate = URL(fileURLWithPath: path).standardizedFileURL.path
        for existing in existingPaths {
            let existingPath = URL(fileURLWithPath: existing).standardizedFileURL.path
            if existingPath == candidate {
                throw SourceDirectoryValidationError.alreadyAdded(existingPath)
            }
            if Self.path(candidate, isNestedIn: existingPath) {
                throw SourceDirectoryValidationError.nestedInExisting(existingPath)
            }
            if Self.path(existingPath, isNestedIn: candidate) {
                throw SourceDirectoryValidationError.containsExisting(existingPath)
            }
        }
    }

    func addDirectory(_ path: String) throws {
        try validateNewDirectory(path: path)
        let directory = SourceDirectory(path: path)
        sourceDirectories.append(directory)
        saveSourceDirectoryToDatabase(directory)
    }

    func addDirectoryWithBookmark(url: URL) throws {
        try validateNewDirectory(path: url.path)
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            let directory = SourceDirectory(
                path: url.path,
                bookmarkData: bookmarkData
            )

            sourceDirectories.append(directory)
            saveSourceDirectoryToDatabase(directory)
            logger.info("Added directory with security-scoped bookmark: \(url.path)")
        } catch {
            logger.error("Failed to create bookmark for \(url.path): \(error.localizedDescription)")
            // Fall back to adding without bookmark
            try addDirectory(url.path)
        }
    }

    func removeDirectory(id: UUID) {
        // Stop accessing the URL if we were accessing it
        if let url = accessedURLs[id] {
            url.stopAccessingSecurityScopedResource()
            accessedURLs.removeValue(forKey: id)
        }

        sourceDirectories.removeAll { $0.id == id }
        deleteSourceDirectoryFromDatabase(id: id)
    }

    func toggleDirectory(id: UUID) {
        if let index = sourceDirectories.firstIndex(where: { $0.id == id }) {
            sourceDirectories[index].isEnabled.toggle()
            saveSourceDirectoryToDatabase(sourceDirectories[index])
        }
    }

    func updateLastScanned(id: UUID, date: Date) {
        if let index = sourceDirectories.firstIndex(where: { $0.id == id }) {
            sourceDirectories[index].lastScanned = date
            saveSourceDirectoryToDatabase(sourceDirectories[index])
        }
    }

    var enabledDirectories: [SourceDirectory] {
        sourceDirectories.filter { $0.isEnabled }
    }

    var config: ServerConfig {
        let authConfiguration = authStore.load()
        return ServerConfig(
            port: serverPort,
            sourceDirectories: sourceDirectories,
            authEnabled: authConfiguration.isEnabled,
            pinHash: authConfiguration.pinHash,
            pinRevision: authConfiguration.pinRevision,
            sessionTTLDays: authConfiguration.sessionTTLDays,
            authTokenSecret: authConfiguration.tokenSecret
        )
    }

    func setAuthEnabled(_ enabled: Bool) -> Bool {
        guard pinConfigured || !enabled else {
            return false
        }

        var configuration = authStore.load()
        configuration.isEnabled = enabled
        authStore.save(configuration)
        refreshAuthState()
        return true
    }

    func setPIN(_ pin: String) throws {
        let normalizedPIN = ServerPINSecurity.normalize(pin: pin)
        let pinHash = try ServerPINSecurity.hash(pin: normalizedPIN)

        var configuration = authStore.load()
        configuration.pinHash = pinHash
        configuration.pinRevision += 1
        configuration.isEnabled = true
        configuration.generatedPIN = nil
        authStore.save(configuration)

        logger.info("Server PIN updated; all sessions revoked")
        refreshAuthState()
    }

    func updateSessionTTLDays(_ days: Int) {
        let clamped = max(1, min(days, 365))
        var configuration = authStore.load()
        configuration.sessionTTLDays = clamped
        authStore.save(configuration)
        refreshAuthState()
    }

    func revokeAllSessions() {
        var configuration = authStore.load()
        configuration.pinRevision += 1
        authStore.save(configuration)
        logger.info("All sessions revoked")
        refreshAuthState()
    }

    private func refreshAuthState() {
        let authConfiguration = authStore.load()
        authEnabled = authConfiguration.requiresAuthentication
        pinConfigured = authConfiguration.hasPIN
        sessionTTLDays = authConfiguration.sessionTTLDays
        pinRevision = authConfiguration.pinRevision
        generatedPIN = authConfiguration.generatedPIN
    }

    /// Starts accessing security-scoped resources for all enabled directories.
    /// Call this before scanning directories.
    func startAccessingSecurityScopedResources() {
        let enabled = enabledDirectories
        for directory in enabled {
            guard let bookmarkData = directory.bookmarkData else {
                continue
            }

            // Skip directories nested within another enabled source directory.
            // The ancestor's access already covers them, and running the
            // start/stop security-scope cycle on a nested path can leave that
            // subtree inaccessible to this (non-sandboxed) process, causing
            // streaming/file lookups under it to fail with "file not found".
            if let ancestor = enabled.first(where: {
                $0.id != directory.id && Self.path(directory.path, isNestedIn: $0.path)
            }) {
                logger.info("Skipping security scope for nested source directory \(directory.path); covered by \(ancestor.path)")
                continue
            }

            do {
                var isStale = false
                var url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                if isStale {
                    logger.warning("Bookmark is stale for \(directory.path), attempting to refresh")
                    if let refreshed = refreshBookmark(for: directory.id, url: url) {
                        url = refreshed
                    }
                } else {
                    syncPath(for: directory.id, with: url)
                }

                if url.startAccessingSecurityScopedResource() {
                    accessedURLs[directory.id] = url
                    logger.debug("Started accessing security-scoped resource: \(url.path)")
                } else {
                    logger.warning("Failed to start accessing security-scoped resource: \(url.path)")
                }
            } catch {
                logger.error("Failed to resolve bookmark for \(directory.path): \(error.localizedDescription)")
            }
        }
    }

    /// Stops accessing all security-scoped resources.
    /// Call this after scanning is complete.
    func stopAccessingSecurityScopedResources() {
        for (id, url) in accessedURLs {
            url.stopAccessingSecurityScopedResource()
            logger.debug("Stopped accessing security-scoped resource: \(url.path)")
            accessedURLs.removeValue(forKey: id)
        }
    }

    /// Refreshes a stale security-scoped bookmark and returns the URL
    /// re-resolved from the new bookmark data. The caller should use the
    /// returned URL (not the stale one) for `startAccessingSecurityScopedResource()`
    /// so that the OS reconciles the new bookmark to its target.
    private func refreshBookmark(for id: UUID, url: URL) -> URL? {
        guard let index = sourceDirectories.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        do {
            let newBookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            var stillStale = false
            let refreshedURL = try URL(
                resolvingBookmarkData: newBookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stillStale
            )
            if stillStale {
                logger.warning("Bookmark still stale after refresh for \(refreshedURL.path)")
            }

            // A bookmark goes stale when the folder was renamed or moved: keep
            // the stored path in sync so scans and streaming use the new location.
            sourceDirectories[index].bookmarkData = newBookmarkData
            syncPath(for: id, with: refreshedURL)
            saveSourceDirectoryToDatabase(sourceDirectories[index])
            logger.info("Refreshed stale bookmark for \(refreshedURL.path)")
            return refreshedURL
        } catch {
            logger.error("Failed to refresh bookmark for \(url.path): \(error.localizedDescription)")
            return nil
        }
    }

    /// Updates the stored path of a source folder when its bookmark resolves
    /// to a different location (folder renamed or moved in the Finder).
    private func syncPath(for id: UUID, with url: URL) {
        guard let index = sourceDirectories.firstIndex(where: { $0.id == id }) else { return }
        let resolvedPath = url.standardizedFileURL.path
        guard sourceDirectories[index].path != resolvedPath else { return }
        logger.info("Source folder moved from \(self.sourceDirectories[index].path) to \(resolvedPath)")
        sourceDirectories[index].path = resolvedPath
        saveSourceDirectoryToDatabase(sourceDirectories[index])
    }

    /// Returns true when `child` is a descendant path of `parent`.
    nonisolated private static func path(_ child: String, isNestedIn parent: String) -> Bool {
        let prefix = parent.hasSuffix("/") ? parent : parent + "/"
        return child.hasPrefix(prefix)
    }
}

enum SourceDirectoryValidationError: LocalizedError, Equatable {
    case alreadyAdded(String)
    case nestedInExisting(String)
    case containsExisting(String)

    var errorDescription: String? {
        switch self {
        case .alreadyAdded:
            return String(localized: "This folder is already a source folder.")
        case .nestedInExisting(let parent):
            return String(localized: "This folder is inside the source folder “\((parent as NSString).lastPathComponent)”, which already includes its videos.")
        case .containsExisting(let child):
            return String(localized: "This folder contains the source folder “\((child as NSString).lastPathComponent)”. Remove that folder first, or add a folder that does not overlap it.")
        }
    }
}

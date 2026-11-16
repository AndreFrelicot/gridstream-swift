import Foundation
import GRDB
import OSLog

actor DatabaseManager {
    private let logger = Logger(subsystem: "com.gridstream.macos", category: "DatabaseManager")

    private var dbPool: DatabasePool?
    private let customDatabasePath: URL?

    static let shared = DatabaseManager()

    private static let catalogVersionKey = "catalog_version"

    private init() {
        self.customDatabasePath = nil
    }

    init(databasePath: URL) {
        self.customDatabasePath = databasePath
    }

    var databasePath: URL {
        if let customPath = customDatabasePath {
            return customPath
        }

        return Self.resolveDataDirectory().appendingPathComponent("gridstream.sqlite")
    }

    /// Resolves the data directory from UserDefaults or falls back to the default.
    /// Can be called from any isolation context (reads UserDefaults directly).
    static func resolveDataDirectory() -> URL {
        if let savedPath = UserDefaults.standard.string(forKey: "dataDirectory"), !savedPath.isEmpty {
            return URL(fileURLWithPath: savedPath, isDirectory: true)
        }
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("GridStream", isDirectory: true)
    }

    var isInitialized: Bool {
        dbPool != nil
    }

    func initialize() async throws {
        guard dbPool == nil else { return }

        let dbPath = databasePath
        let dbDirectory = dbPath.deletingLastPathComponent()

        // A data directory change recorded last session moves the database now,
        // before it is opened
        if customDatabasePath == nil {
            DataDirectoryMigration.applyPendingMove(to: dbDirectory)
        }

        try FileManager.default.createDirectory(
            at: dbDirectory,
            withIntermediateDirectories: true
        )

        logger.info("Initializing database at: \(dbPath.path)")

        var configuration = Configuration()
        #if DEBUG
        configuration.prepareDatabase { db in
            db.trace { self.logger.debug("\($0)") }
        }
        #endif

        let pool = try DatabasePool(path: dbPath.path, configuration: configuration)
        dbPool = pool

        try runMigrations(pool)

        logger.info("Database initialized successfully")
    }

    private nonisolated func runMigrations(_ pool: DatabasePool) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration(V1_CreateVideoFilesTable.migrationIdentifier) { db in
            try V1_CreateVideoFilesTable.migrate(db)
        }

        migrator.registerMigration(V2_CreateTagsTable.migrationIdentifier) { db in
            try V2_CreateTagsTable.migrate(db)
        }

        migrator.registerMigration(V3_AddRatings.migrationIdentifier) { db in
            try V3_AddRatings.migrate(db)
        }

        migrator.registerMigration(V4_CreateThumbnailsTable.migrationIdentifier) { db in
            try V4_CreateThumbnailsTable.migrate(db)
        }

        migrator.registerMigration(V5_CreateAppMetadataTable.migrationIdentifier) { db in
            try V5_CreateAppMetadataTable.migrate(db)
        }

        migrator.registerMigration(V6_AddPlayCountTracking.migrationIdentifier) { db in
            try V6_AddPlayCountTracking.migrate(db)
        }

        migrator.registerMigration(V7_CreateSmartListsTable.migrationIdentifier) { db in
            try V7_CreateSmartListsTable.migrate(db)
        }

        migrator.registerMigration(V8_CreateSimpleListsTable.migrationIdentifier) { db in
            try V8_CreateSimpleListsTable.migrate(db)
        }

        migrator.registerMigration(V9_CreateSimpleListVideosTable.migrationIdentifier) { db in
            try V9_CreateSimpleListVideosTable.migrate(db)
        }

        // V10 and V11 previously created scrub_videos and scrub_queue tables (MP4 system, removed).
        // Keep migration identifiers so GRDB doesn't re-run them on existing databases.
        migrator.registerMigration("v10_create_scrub_videos") { db in
            // Dropped: MP4 scrub video generation removed
            try db.execute(sql: "DROP TABLE IF EXISTS scrub_videos")
        }

        migrator.registerMigration("v11_create_scrub_queue") { db in
            // Dropped: MP4 scrub queue removed
            try db.execute(sql: "DROP TABLE IF EXISTS scrub_queue")
        }

        migrator.registerMigration(V12_CreateScrubFramesTable.migrationIdentifier) { db in
            try V12_CreateScrubFramesTable.migrate(db)
        }

        migrator.registerMigration(V13_CreateSourceDirectoriesTable.migrationIdentifier) { db in
            try V13_CreateSourceDirectoriesTable.migrate(db)
        }

        migrator.registerMigration(V14_CreateTimeRangesTable.migrationIdentifier) { db in
            try V14_CreateTimeRangesTable.migrate(db)
        }

        migrator.registerMigration(V15_AddLastPlayedAt.migrationIdentifier) { db in
            try V15_AddLastPlayedAt.migrate(db)
        }

        migrator.registerMigration(V16_CreateAnnotationsTable.migrationIdentifier) { db in
            try V16_CreateAnnotationsTable.migrate(db)
        }

        migrator.registerMigration(V17_AddAnnotationCount.migrationIdentifier) { db in
            try V17_AddAnnotationCount.migrate(db)
        }

        migrator.registerMigration(V18_AddScrubFrameFormat.migrationIdentifier) { db in
            try V18_AddScrubFrameFormat.migrate(db)
        }

        migrator.registerMigration(V19_AddFilterIndexes.migrationIdentifier) { db in
            try V19_AddFilterIndexes.migrate(db)
        }

        migrator.registerMigration(V20_CreateFrameCapturesTable.migrationIdentifier) { db in
            try V20_CreateFrameCapturesTable.migrate(db)
        }

        migrator.registerMigration(V21_AddAnnotationText.migrationIdentifier) { db in
            try V21_AddAnnotationText.migrate(db)
        }

        migrator.registerMigration(V22_CreateAnnotationTextSearch.migrationIdentifier) { db in
            try V22_CreateAnnotationTextSearch.migrate(db)
        }

        migrator.registerMigration(V23_AddLastPlayedAtPartialIndex.migrationIdentifier) { db in
            try V23_AddLastPlayedAtPartialIndex.migrate(db)
        }

        migrator.registerMigration(V24_AddScrubFrameCount.migrationIdentifier) { db in
            try V24_AddScrubFrameCount.migrate(db)
        }

        migrator.registerMigration(V25_DropRedundantScrubIndexes.migrationIdentifier) { db in
            try V25_DropRedundantScrubIndexes.migrate(db)
        }

        migrator.registerMigration(V26_AddScrubFailureTracking.migrationIdentifier) { db in
            try V26_AddScrubFailureTracking.migrate(db)
        }

        migrator.registerMigration(V27_AddMissingSince.migrationIdentifier) { db in
            try V27_AddMissingSince.migrate(db)
        }

        migrator.registerMigration(V28_NormalizeSmartListCriteria.migrationIdentifier) { db in
            try V28_NormalizeSmartListCriteria.migrate(db)
        }

        migrator.registerMigration(V29_NormalizeSimpleListSortOrder.migrationIdentifier) { db in
            try V29_NormalizeSimpleListSortOrder.migrate(db)
        }

        try migrator.migrate(pool)
    }

    func read<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        guard let pool = dbPool else {
            throw DatabaseError.notInitialized
        }

        return try await pool.read { db in
            try block(db)
        }
    }

    func write<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        guard let pool = dbPool else {
            throw DatabaseError.notInitialized
        }

        return try await pool.write { db in
            try block(db)
        }
    }

    func close() async throws {
        guard let pool = dbPool else { return }
        try pool.close()
        dbPool = nil
        logger.info("Database connection closed")
    }

    /// Awaits an empty write through the GRDB pool. Because writes are
    /// serialized, returning from this call guarantees that every write
    /// previously enqueued on the pool has been committed. Call before
    /// shutting down the Vapor application so in-flight stats / annotation
    /// / catalog writes are not lost when the process exits.
    func drain() async {
        guard let pool = dbPool else { return }
        do {
            try await pool.write { _ in }
        } catch {
            logger.error("Database drain failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Catalog Version Methods

    /// Fetches the current catalog version from the database.
    /// The catalog version is an Int64 timestamp (milliseconds since epoch) that
    /// indicates when the catalog was last modified.
    /// Returns 0 if no version is stored.
    func fetchCatalogVersion() async throws -> Int64 {
        try await read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT value FROM app_metadata WHERE key = ?",
                arguments: [Self.catalogVersionKey]
            )
            guard let valueString = row?["value"] as? String,
                  let version = Int64(valueString) else {
                return 0
            }
            return version
        }
    }

    /// Runs a write transaction that may change the catalog (videos, tags,
    /// ratings, lists, annotations, time ranges, captures, thumbnails, playback
    /// statistics, source folders). When `block` reports a change, the catalog
    /// version is bumped in the same transaction, so clients that refetch after
    /// seeing the new version always observe the change. This is the only way
    /// the version moves besides `updateCatalogVersion(_:)`.
    func writeCatalog<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> CatalogWrite<T>) async throws -> T {
        try await write { db in
            let outcome = try block(db)
            if outcome.changed {
                try Self.updateCatalogVersion(in: db)
            }
            return outcome.value
        }
    }

    /// Bumps the catalog version on its own, for changes made outside a single
    /// transaction (end of a scan). Without `version`, the current time in
    /// milliseconds is used.
    func updateCatalogVersion(_ version: Int64? = nil) async throws {
        try await write { db in
            try Self.updateCatalogVersion(in: db, version: version)
        }

        logger.debug("Catalog version updated")
    }

    /// Updates the catalog version as part of an existing write transaction.
    /// Callers outside this type use `writeCatalog`.
    private nonisolated static func updateCatalogVersion(in db: Database, version: Int64? = nil) throws {
        let newVersion = version ?? Int64(Date().timeIntervalSince1970 * 1000)
        let now = Date().timeIntervalSince1970

        try db.execute(
            sql: """
                INSERT INTO app_metadata (key, value, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
                """,
            arguments: [catalogVersionKey, String(newVersion), now]
        )
    }

    // MARK: - Clear All Data

    /// Clears all data from the database including videos, thumbnails, tags, ratings.
    /// This is a destructive operation that cannot be undone.
    /// Returns the count of deleted records by table.
    func clearAllData() async throws -> ClearDataResult {
        logger.warning("Clearing all data from database")

        let result = try await write { db -> ClearDataResult in
            func deleteIfExists(_ table: String) throws -> Int {
                guard try db.tableExists(table) else { return 0 }
                try db.execute(sql: "DELETE FROM \(table)")
                return db.changesCount
            }

            // Delete in order to respect foreign key constraints
            let ftsDeleted = try deleteIfExists("video_annotation_text_fts")
            let frameCapturesDeleted = try deleteIfExists("frame_captures")
            let scrubFramesDeleted = try deleteIfExists("scrub_frames")
            let timeRangesDeleted = try deleteIfExists("time_ranges")
            let annotationsDeleted = try deleteIfExists("video_annotations")
            let simpleListVideosDeleted = try deleteIfExists("simple_list_videos")
            let simpleListsDeleted = try deleteIfExists("simple_lists")
            let smartListsDeleted = try deleteIfExists("smart_lists")
            let videoTagsDeleted = try deleteIfExists("video_tags")
            let thumbnailsDeleted = try deleteIfExists("thumbnails")
            let videoFilesDeleted = try deleteIfExists("video_files")
            let tagsDeleted = try deleteIfExists("tags")
            let sourceDirectoriesDeleted = try deleteIfExists("source_directories")
            let metadataDeleted = try deleteIfExists("app_metadata")

            return ClearDataResult(
                videoFilesDeleted: videoFilesDeleted,
                thumbnailsDeleted: thumbnailsDeleted,
                tagsDeleted: tagsDeleted,
                videoTagsDeleted: videoTagsDeleted,
                metadataDeleted: metadataDeleted,
                otherRecordsDeleted: ftsDeleted
                    + frameCapturesDeleted
                    + scrubFramesDeleted
                    + timeRangesDeleted
                    + annotationsDeleted
                    + simpleListVideosDeleted
                    + simpleListsDeleted
                    + smartListsDeleted
                    + sourceDirectoriesDeleted
            )
        }

        logger.info("Cleared all data: \(result.videoFilesDeleted) videos, \(result.thumbnailsDeleted) thumbnails, \(result.tagsDeleted) tags")

        return result
    }

    // MARK: - Source Directory Methods

    /// Fetches all source directories from the database.
    func fetchSourceDirectories() async throws -> [SourceDirectory] {
        try await read { db in
            SourceDirectoryRecord.findAll(in: db).map { $0.toSourceDirectory() }
        }
    }

    /// Saves a source directory to the database (insert or update).
    func saveSourceDirectory(_ directory: SourceDirectory) async throws {
        var record = SourceDirectoryRecord.from(directory)
        record.touch()
        let touched = record

        try await write { db in
            try touched.save(db)
        }
    }

    /// Deletes a source directory from the database by ID.
    func deleteSourceDirectory(id: UUID) async throws {
        try await write { db in
            _ = try SourceDirectoryRecord
                .filter(Column("id") == id)
                .deleteAll(db)
        }
    }
}

/// Result of clearing all database data.
/// Outcome of a `DatabaseManager.writeCatalog` transaction: the value handed
/// back to the caller and whether the catalog changed (which bumps its version).
nonisolated struct CatalogWrite<Value: Sendable>: Sendable {
    let value: Value
    let changed: Bool

    static func changed(_ value: Value) -> CatalogWrite { CatalogWrite(value: value, changed: true) }
    static func unchanged(_ value: Value) -> CatalogWrite { CatalogWrite(value: value, changed: false) }
}

nonisolated extension CatalogWrite where Value == Void {
    static var changed: CatalogWrite { CatalogWrite(value: (), changed: true) }
    static var unchanged: CatalogWrite { CatalogWrite(value: (), changed: false) }
}

nonisolated struct ClearDataResult: Sendable {
    let videoFilesDeleted: Int
    let thumbnailsDeleted: Int
    let tagsDeleted: Int
    let videoTagsDeleted: Int
    let metadataDeleted: Int
    let otherRecordsDeleted: Int

    var totalDeleted: Int {
        videoFilesDeleted + thumbnailsDeleted + tagsDeleted + videoTagsDeleted + metadataDeleted + otherRecordsDeleted
    }
}

nonisolated enum DatabaseError: Error, LocalizedError {
    case notInitialized

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Database has not been initialized. Call initialize() first."
        }
    }
}

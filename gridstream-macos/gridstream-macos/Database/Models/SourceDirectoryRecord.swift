import Foundation
import GRDB

nonisolated struct SourceDirectoryRecord: Sendable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "source_directories"

    var id: UUID
    var path: String
    var isEnabled: Bool
    var lastScanned: Double?
    var bookmarkData: Data?
    var createdAt: Double
    var updatedAt: Double

    enum CodingKeys: String, CodingKey {
        case id
        case path
        case isEnabled = "is_enabled"
        case lastScanned = "last_scanned"
        case bookmarkData = "bookmark_data"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID = UUID(),
        path: String,
        isEnabled: Bool = true,
        lastScanned: Double? = nil,
        bookmarkData: Data? = nil,
        createdAt: Double = Date().timeIntervalSince1970,
        updatedAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.path = path
        self.isEnabled = isEnabled
        self.lastScanned = lastScanned
        self.bookmarkData = bookmarkData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(row: Row) throws {
        id = row["id"]
        path = row["path"]
        isEnabled = row["is_enabled"]
        lastScanned = row["last_scanned"]
        bookmarkData = row["bookmark_data"]
        createdAt = row["created_at"]
        updatedAt = row["updated_at"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["path"] = path
        container["is_enabled"] = isEnabled
        container["last_scanned"] = lastScanned
        container["bookmark_data"] = bookmarkData
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
    }

    mutating func touch() {
        updatedAt = Date().timeIntervalSince1970
    }
}

// MARK: - Conversion Methods

nonisolated extension SourceDirectoryRecord {
    /// Converts this record to a SourceDirectory model.
    func toSourceDirectory() -> SourceDirectory {
        SourceDirectory(
            id: id,
            path: path,
            isEnabled: isEnabled,
            lastScanned: lastScanned.map { Date(timeIntervalSince1970: $0) },
            bookmarkData: bookmarkData
        )
    }

    /// Creates a record from a SourceDirectory model.
    static func from(_ directory: SourceDirectory) -> SourceDirectoryRecord {
        SourceDirectoryRecord(
            id: directory.id,
            path: directory.path,
            isEnabled: directory.isEnabled,
            lastScanned: directory.lastScanned?.timeIntervalSince1970,
            bookmarkData: directory.bookmarkData
        )
    }
}

// MARK: - Query Helpers

nonisolated extension SourceDirectoryRecord {
    static func findAll(in db: Database) -> [SourceDirectoryRecord] {
        (try? SourceDirectoryRecord.fetchAll(db)) ?? []
    }

    static func findById(_ id: UUID, in db: Database) -> SourceDirectoryRecord? {
        try? SourceDirectoryRecord
            .filter(Column("id") == id)
            .fetchOne(db)
    }

    static func findByPath(_ path: String, in db: Database) -> SourceDirectoryRecord? {
        try? SourceDirectoryRecord
            .filter(Column("path") == path)
            .fetchOne(db)
    }

    static func findEnabled(in db: Database) -> [SourceDirectoryRecord] {
        (try? SourceDirectoryRecord
            .filter(Column("is_enabled") == true)
            .fetchAll(db)) ?? []
    }

    static func countAll(in db: Database) -> Int {
        (try? SourceDirectoryRecord.fetchCount(db)) ?? 0
    }
}

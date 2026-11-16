import Foundation
import GRDB

/// A simple list with the fileIds of its videos, in list order.
nonisolated struct SimpleListWithVideos: Sendable {
    let list: SimpleListRecord
    let videoFileIds: [String]
}

/// Persistence of simple lists (`simple_lists`, `simple_list_videos`).
nonisolated struct SimpleListRepository: Sendable {
    /// Maximum number of simple lists.
    static let maxCount = 50

    let database: DatabaseManager

    func all() async throws -> [SimpleListWithVideos] {
        try await database.read { db in
            SimpleListRecord.findAll(in: db).map { list in
                SimpleListWithVideos(list: list, videoFileIds: Self.videoFileIds(of: list.id, in: db))
            }
        }
    }

    func find(id: UUID) async throws -> SimpleListWithVideos {
        try await database.read { db in
            guard let list = SimpleListRecord.findById(id, in: db) else {
                throw RepositoryError.notFound("Simple list not found")
            }
            return SimpleListWithVideos(list: list, videoFileIds: Self.videoFileIds(of: id, in: db))
        }
    }

    /// Creates a list with an already normalized name; `displayName` is the
    /// name as the client sent it, used in the duplicate-name error.
    func create(name: String, displayName: String, sortOrder: String) async throws -> SimpleListRecord {
        try await database.writeCatalog { db in
            if SimpleListRecord.countAll(in: db) >= Self.maxCount {
                throw RepositoryError.invalid("Simple list limit reached. Maximum of \(Self.maxCount) simple lists allowed.")
            }
            if SimpleListRecord.findByName(name, in: db) != nil {
                throw RepositoryError.invalid("A simple list with the name '\(displayName)' already exists.")
            }

            let list = SimpleListRecord(name: name, sortOrder: sortOrder)
            try list.insert(db)
            return .changed(list)
        }
    }

    /// Renames and/or re-sorts a list in one read-modify-write transaction.
    func update(id: UUID, name: String?, displayName: String?, sortOrder: String?) async throws -> SimpleListWithVideos {
        try await database.writeCatalog { db in
            guard var list = SimpleListRecord.findById(id, in: db) else {
                throw RepositoryError.notFound("Simple list not found")
            }

            if let name, name != list.name {
                if SimpleListRecord.findByName(name, in: db) != nil {
                    throw RepositoryError.invalid("A simple list with the name '\(displayName ?? name)' already exists.")
                }
                list.name = name
            }

            if let sortOrder {
                list.sortOrder = sortOrder
            }

            list.touch()
            try list.update(db)
            return .changed(SimpleListWithVideos(list: list, videoFileIds: Self.videoFileIds(of: id, in: db)))
        }
    }

    /// Deletes a list and its memberships; returns the deleted list.
    func delete(id: UUID) async throws -> SimpleListRecord {
        try await database.writeCatalog { db in
            guard let list = SimpleListRecord.findById(id, in: db) else {
                throw RepositoryError.notFound("Simple list not found")
            }
            try SimpleListVideoRecord.deleteByListId(id, in: db)
            _ = try SimpleListRecord.filter(Column("id") == id).deleteAll(db)
            return .changed(list)
        }
    }

    /// Appends the videos that are not in the list yet, in request order.
    func addVideos(_ videoFileIds: [String], toList id: UUID) async throws -> SimpleListWithVideos {
        try await database.writeCatalog { db in
            guard var list = SimpleListRecord.findById(id, in: db) else {
                throw RepositoryError.notFound("Simple list not found")
            }

            var maxPosition = SimpleListVideoRecord.getMaxPosition(forListId: id, in: db)
            var didAddVideo = false

            for videoFileId in videoFileIds
            where SimpleListVideoRecord.findByListIdAndVideoFileId(id, videoFileId, in: db) == nil {
                maxPosition += 1
                let record = SimpleListVideoRecord(simpleListId: id, videoFileId: videoFileId, position: maxPosition)
                try record.insert(db)
                didAddVideo = true
            }

            if didAddVideo {
                list.touch()
                try list.update(db)
            }

            let result = SimpleListWithVideos(list: list, videoFileIds: Self.videoFileIds(of: id, in: db))
            return didAddVideo ? .changed(result) : .unchanged(result)
        }
    }

    /// Removes a video from the list (no-op when it is not in it).
    func removeVideo(_ videoFileId: String, fromList id: UUID) async throws -> SimpleListWithVideos {
        try await database.writeCatalog { db in
            guard var list = SimpleListRecord.findById(id, in: db) else {
                throw RepositoryError.notFound("Simple list not found")
            }

            var didRemove = false
            if let record = SimpleListVideoRecord.findByListIdAndVideoFileId(id, videoFileId, in: db) {
                _ = try SimpleListVideoRecord.filter(Column("id") == record.id).deleteAll(db)
                list.touch()
                try list.update(db)
                didRemove = true
            }

            let result = SimpleListWithVideos(list: list, videoFileIds: Self.videoFileIds(of: id, in: db))
            return didRemove ? .changed(result) : .unchanged(result)
        }
    }

    private static func videoFileIds(of listId: UUID, in db: Database) -> [String] {
        SimpleListVideoRecord.findByListId(listId, in: db).map(\.videoFileId)
    }
}

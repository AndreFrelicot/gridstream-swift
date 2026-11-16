import Foundation
import GRDB
import GridStreamAPI

/// Persistence and evaluation of smart lists (`smart_lists`).
nonisolated struct SmartListRepository: Sendable {
    /// Maximum number of smart lists.
    static let maxCount = 50

    let database: DatabaseManager

    func all() async throws -> [SmartListRecord] {
        try await database.read { db in
            SmartListRecord.findAll(in: db)
        }
    }

    func find(id: UUID) async throws -> SmartListRecord {
        try await database.read { db in
            guard let list = SmartListRecord.findById(id, in: db) else {
                throw RepositoryError.notFound("Smart list not found")
            }
            return list
        }
    }

    /// Creates a list with an already normalized name and canonical criteria;
    /// `displayName` is the name as the client sent it.
    func create(name: String, displayName: String, criteria: String) async throws -> SmartListRecord {
        try await database.writeCatalog { db in
            if SmartListRecord.countAll(in: db) >= Self.maxCount {
                throw RepositoryError.invalid("Smart list limit reached. Maximum of \(Self.maxCount) smart lists allowed.")
            }
            if SmartListRecord.findByName(name, in: db) != nil {
                throw RepositoryError.invalid("A smart list with the name '\(displayName)' already exists.")
            }

            let list = SmartListRecord(name: name, criteria: criteria)
            try list.insert(db)
            return .changed(list)
        }
    }

    /// Renames and/or replaces the criteria in one read-modify-write transaction.
    func update(id: UUID, name: String?, displayName: String?, criteria: String?) async throws -> SmartListRecord {
        try await database.writeCatalog { db in
            guard var list = SmartListRecord.findById(id, in: db) else {
                throw RepositoryError.notFound("Smart list not found")
            }

            if let name, name != list.name {
                if SmartListRecord.findByName(name, in: db) != nil {
                    throw RepositoryError.invalid("A smart list with the name '\(displayName ?? name)' already exists.")
                }
                list.name = name
            }

            if let criteria {
                list.criteria = criteria
            }

            list.touch()
            try list.update(db)
            return .changed(list)
        }
    }

    /// Deletes a list; returns the deleted list.
    func delete(id: UUID) async throws -> SmartListRecord {
        try await database.writeCatalog { db in
            guard let list = SmartListRecord.findById(id, in: db) else {
                throw RepositoryError.notFound("Smart list not found")
            }
            _ = try SmartListRecord.filter(Column("id") == id).deleteAll(db)
            return .changed(list)
        }
    }

    /// Evaluates every smart list's criteria and inverts the results into a
    /// `fileId -> [smartListId]` map. Lists with undecodable criteria are skipped.
    func memberships() async throws -> [String: [UUID]] {
        let smartLists = try await all()
        let evaluator = CriteriaEvaluator()

        // Only videos visible in the catalog can be members
        let liveFileIds = try await database.read { db in
            try VideoFileRecord.liveFileIds(in: db)
        }

        var memberships: [String: [UUID]] = [:]
        for smartList in smartLists {
            guard let criteria = try? SmartListCriteria.decode(json: smartList.criteria) else {
                continue
            }

            let fileIds = try await evaluator.evaluateCriteria(criteria, db: database).intersection(liveFileIds)
            let smartListId = smartList.id
            for fileId in fileIds {
                memberships[fileId, default: []].append(smartListId)
            }
        }

        return memberships
    }
}

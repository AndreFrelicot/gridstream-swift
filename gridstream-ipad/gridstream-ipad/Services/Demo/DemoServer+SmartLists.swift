import Foundation
import GridStreamAPI

extension DemoServer {
    func routeSmartLists(_ request: DemoRequest) throws -> DemoResponse? {
        // Smart lists
        if request.on("GET", "smart-lists") != nil {
            let store = try loadedStore()
            return .json(SmartListsResponse(smartLists: store.smartLists.map(store.smartListDTO)))
        }
        if request.on("GET", "smart-lists/memberships") != nil {
            return .json(SmartListMembershipsResponse(memberships: try smartListMemberships()))
        }
        if request.on("POST", "smart-lists") != nil {
            return .json(try createSmartList(try decode(CreateSmartListRequest.self, request.body)), status: 201)
        }
        if let params = request.on("GET", "smart-lists/:id") {
            let id = params[0]
            let store = try loadedStore()
            let uuid = try Self.uuid(id, label: "smart list")
            guard let list = store.smartLists.first(where: { $0.id == uuid }) else { throw DemoHTTPError.notFound("Smart list not found") }
            return .json(store.smartListDTO(list))
        }
        if let params = request.on("PUT", "smart-lists/:id") {
            let id = params[0]
            return .json(try updateSmartList(try Self.uuid(id, label: "smart list"), try decode(UpdateSmartListRequest.self, request.body)))
        }
        if let params = request.on("DELETE", "smart-lists/:id") {
            let id = params[0]
            return .json(try deleteSmartList(try Self.uuid(id, label: "smart list")))
        }
        return nil
    }

    // MARK: - Smart lists

    private func smartListMemberships() throws -> [String: [UUID]] {
        let store = try loadedStore()
        let evaluator = DemoCriteriaEvaluator(store: store)
        var memberships: [String: [UUID]] = [:]
        for list in store.smartLists {
            guard let criteria = try? SmartListCriteria.decode(json: list.criteria) else { continue }
            for fileId in evaluator.fileIds(matching: criteria) {
                memberships[fileId, default: []].append(list.id)
            }
        }
        return memberships
    }

    private func createSmartList(_ request: CreateSmartListRequest) throws -> SmartListDTO {
        let name = try Self.normalizedName(request.name, kind: "Smart list")
        let criteria = try Self.canonicalCriteria(request.criteria)
        return try write { store in
            guard !store.smartLists.contains(where: { $0.name == name }) else {
                throw DemoHTTPError.badRequest("A smart list with the name '\(request.name)' already exists.")
            }
            let now = Date()
            let list = DemoStore.SmartList(id: UUID(), name: name, criteria: criteria, createdAt: now, updatedAt: now)
            store.smartLists.append(list)
            return store.smartListDTO(list)
        }
    }

    private func updateSmartList(_ id: UUID, _ request: UpdateSmartListRequest) throws -> SmartListDTO {
        let name = try request.name.map { try Self.normalizedName($0, kind: "Smart list") }
        let criteria = try request.criteria.map(Self.canonicalCriteria)
        return try write { store in
            guard let index = store.smartLists.firstIndex(where: { $0.id == id }) else {
                throw DemoHTTPError.notFound("Smart list not found")
            }
            if let name, name != store.smartLists[index].name {
                guard !store.smartLists.contains(where: { $0.name == name }) else {
                    throw DemoHTTPError.badRequest("A smart list with the name '\(request.name ?? name)' already exists.")
                }
                store.smartLists[index].name = name
            }
            if let criteria { store.smartLists[index].criteria = criteria }
            store.smartLists[index].updatedAt = Date()
            return store.smartListDTO(store.smartLists[index])
        }
    }

    private func deleteSmartList(_ id: UUID) throws -> SmartListDeleteResponse {
        try write { store in
            guard let list = store.smartLists.first(where: { $0.id == id }) else {
                throw DemoHTTPError.notFound("Smart list not found")
            }
            store.smartLists.removeAll { $0.id == id }
            return SmartListDeleteResponse(success: true, message: "Smart list '\(list.name)' deleted successfully")
        }
    }
}

import Foundation
import GridStreamAPI

extension DemoServer {
    func routeSimpleLists(_ request: DemoRequest) throws -> DemoResponse? {
        // Simple lists
        if request.on("GET", "simple-lists") != nil {
            let store = try loadedStore()
            return .json(SimpleListsResponse(simpleLists: store.simpleLists.map(store.simpleListDTO)))
        }
        if request.on("POST", "simple-lists") != nil {
            return .json(try createSimpleList(try decode(CreateSimpleListRequest.self, request.body)), status: 201)
        }
        if let params = request.on("GET", "simple-lists/:id") {
            let id = params[0]
            let store = try loadedStore()
            return .json(store.simpleListDTO(try requireSimpleList(try Self.uuid(id, label: "simple list"), in: store)))
        }
        if let params = request.on("PUT", "simple-lists/:id") {
            let id = params[0]
            return .json(try updateSimpleList(try Self.uuid(id, label: "simple list"), try decode(UpdateSimpleListRequest.self, request.body)))
        }
        if let params = request.on("DELETE", "simple-lists/:id") {
            let id = params[0]
            return .json(try deleteSimpleList(try Self.uuid(id, label: "simple list")))
        }
        if let params = request.on("POST", "simple-lists/:id/videos") {
            let id = params[0]
            return .json(try addVideos(try decode(AddVideosRequest.self, request.body).videoIds, toList: try Self.uuid(id, label: "simple list")))
        }
        if let params = request.on("DELETE", "simple-lists/:id/videos/:fileId") {
            let id = params[0]
            let fileId = params[1]
            return .json(try removeVideo(fileId, fromList: try Self.uuid(id, label: "simple list")))
        }
        return nil
    }

    // MARK: - Simple lists

    private func createSimpleList(_ request: CreateSimpleListRequest) throws -> SimpleListDTO {
        let name = try Self.normalizedName(request.name, kind: "Simple list")
        let sortOrder = try Self.canonicalSortOrder(request.sortOrder ?? SimpleListSortOrder.defaultValue)
        return try write { store in
            guard !store.simpleLists.contains(where: { $0.name == name }) else {
                throw DemoHTTPError.badRequest("A simple list with the name '\(request.name)' already exists.")
            }
            let now = Date()
            let list = DemoStore.SimpleList(id: UUID(), name: name, sortOrder: sortOrder, videoIds: [], createdAt: now, updatedAt: now)
            store.simpleLists.append(list)
            return store.simpleListDTO(list)
        }
    }

    private func updateSimpleList(_ id: UUID, _ request: UpdateSimpleListRequest) throws -> SimpleListDTO {
        let name = try request.name.map { try Self.normalizedName($0, kind: "Simple list") }
        let sortOrder = try request.sortOrder.map(Self.canonicalSortOrder)
        return try write { store in
            guard let index = store.simpleLists.firstIndex(where: { $0.id == id }) else {
                throw DemoHTTPError.notFound("Simple list not found")
            }
            if let name, name != store.simpleLists[index].name {
                guard !store.simpleLists.contains(where: { $0.name == name }) else {
                    throw DemoHTTPError.badRequest("A simple list with the name '\(request.name ?? name)' already exists.")
                }
                store.simpleLists[index].name = name
            }
            if let sortOrder { store.simpleLists[index].sortOrder = sortOrder }
            store.simpleLists[index].updatedAt = Date()
            return store.simpleListDTO(store.simpleLists[index])
        }
    }

    private func deleteSimpleList(_ id: UUID) throws -> SimpleListDeleteResponse {
        try write { store in
            guard let list = store.simpleLists.first(where: { $0.id == id }) else {
                throw DemoHTTPError.notFound("Simple list not found")
            }
            store.simpleLists.removeAll { $0.id == id }
            return SimpleListDeleteResponse(success: true, message: "Simple list '\(list.name)' deleted successfully")
        }
    }

    /// Appends the videos that are not in the list yet, in request order.
    private func addVideos(_ fileIds: [String], toList id: UUID) throws -> SimpleListDTO {
        try write { store in
            guard let index = store.simpleLists.firstIndex(where: { $0.id == id }) else {
                throw DemoHTTPError.notFound("Simple list not found")
            }
            for fileId in fileIds where !store.simpleLists[index].videoIds.contains(fileId) {
                store.simpleLists[index].videoIds.append(fileId)
            }
            store.simpleLists[index].updatedAt = Date()
            return store.simpleListDTO(store.simpleLists[index])
        }
    }

    private func removeVideo(_ fileId: String, fromList id: UUID) throws -> SimpleListDTO {
        try write { store in
            guard let index = store.simpleLists.firstIndex(where: { $0.id == id }) else {
                throw DemoHTTPError.notFound("Simple list not found")
            }
            store.simpleLists[index].videoIds.removeAll { $0 == fileId }
            store.simpleLists[index].updatedAt = Date()
            return store.simpleListDTO(store.simpleLists[index])
        }
    }
}

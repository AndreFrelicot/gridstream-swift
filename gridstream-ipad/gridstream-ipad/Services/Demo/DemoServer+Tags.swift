import Foundation
import GridStreamAPI

extension DemoServer {
    func routeTags(_ request: DemoRequest) throws -> DemoResponse? {
        // Tags
        if request.on("GET", "tags") != nil {
            let store = try loadedStore()
            let tags = store.tags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return .json(TagsResponse(tags: tags.map(store.tagDTO)))
        }
        if request.on("POST", "tags") != nil {
            return .json(try createTag(try decode(CreateTagRequest.self, request.body)), status: 201)
        }
        if let params = request.on("GET", "tags/:id") {
            let id = params[0]
            let store = try loadedStore()
            return .json(store.tagDTO(try requireTag(try Self.uuid(id, label: "tag"), in: store)))
        }
        if let params = request.on("PUT", "tags/:id") {
            let id = params[0]
            return .json(try updateTag(try Self.uuid(id, label: "tag"), try decode(UpdateTagRequest.self, request.body)))
        }
        if let params = request.on("DELETE", "tags/:id") {
            let id = params[0]
            return .json(try deleteTag(try Self.uuid(id, label: "tag")))
        }
        if request.on("POST", "tags/apply") != nil {
            return .json(try applyTagsInBulk(try decode(BulkTagApplyRequest.self, request.body)))
        }

        // Video tags
        if let params = request.on("GET", "videos/:fileId/tags") {
            let fileId = params[0]
            let store = try loadedStore()
            _ = try requireVideo(fileId, in: store)
            return .json(VideoTagsResponse(tags: store.tagSummaries(fileId: fileId, withRatings: false)))
        }
        if let params = request.on("POST", "videos/:fileId/tags") {
            let fileId = params[0]
            return .json(try replaceTags(fileId: fileId, with: try decode(ApplyTagsRequest.self, request.body).tagIds))
        }
        if let params = request.on("POST", "videos/:fileId/tags/:tagId") {
            let fileId = params[0]
            let tagId = params[1]
            return .json(try attachTag(try Self.uuid(tagId, label: "tag"), to: fileId))
        }
        if let params = request.on("DELETE", "videos/:fileId/tags/:tagId") {
            let fileId = params[0]
            let tagId = params[1]
            try detachTag(try Self.uuid(tagId, label: "tag"), from: fileId)
            return .empty(204)
        }
        if let params = request.on("GET", "videos/:fileId/tags/:tagId/rating") {
            let fileId = params[0]
            let tagId = params[1]
            let store = try loadedStore()
            let tagUUID = try Self.uuid(tagId, label: "tag")
            guard let link = store.videoTags.first(where: { $0.fileId == fileId && $0.tagId == tagUUID }) else {
                throw DemoHTTPError.notFound("Video does not have this tag assigned")
            }
            return .json(RatingDTO(rating: link.rating ?? 0))
        }
        if let params = request.on("PUT", "videos/:fileId/tags/:tagId/rating") {
            let fileId = params[0]
            let tagId = params[1]
            let request = try decode(RatingRequest.self, request.body)
            try Self.validateRating(request.rating)
            try setTagRating(request.rating, tagId: try Self.uuid(tagId, label: "tag"), fileId: fileId)
            return .json(RatingDTO(rating: request.rating))
        }
        return nil
    }

    // MARK: - Tags

    private func createTag(_ request: CreateTagRequest) throws -> TagDTO {
        try Self.validateColor(request.color)
        let name = request.name.lowercased()
        return try write { store in
            guard !store.tags.contains(where: { $0.name == name }) else {
                throw DemoHTTPError.badRequest("A tag with the name '\(request.name)' already exists.")
            }
            let now = Date()
            let tag = DemoStore.Tag(
                id: UUID(), name: name, color: request.color, description: request.description,
                ratingEnabled: request.ratingEnabled ?? false, createdAt: now, updatedAt: now
            )
            store.tags.append(tag)
            return store.tagDTO(tag)
        }
    }

    private func updateTag(_ id: UUID, _ request: UpdateTagRequest) throws -> TagDTO {
        if let color = request.color {
            try Self.validateColor(color)
        }
        return try write { store in
            guard let index = store.tags.firstIndex(where: { $0.id == id }) else {
                throw DemoHTTPError.notFound("Tag not found")
            }
            if let newName = request.name {
                let normalized = newName.lowercased()
                if normalized != store.tags[index].name {
                    guard !store.tags.contains(where: { $0.name == normalized }) else {
                        throw DemoHTTPError.badRequest("A tag with the name '\(newName)' already exists.")
                    }
                    store.tags[index].name = normalized
                }
            }
            if let color = request.color { store.tags[index].color = color }
            if let description = request.description { store.tags[index].description = description.isEmpty ? nil : description }
            if let ratingEnabled = request.ratingEnabled { store.tags[index].ratingEnabled = ratingEnabled }
            store.tags[index].updatedAt = Date()
            return store.tagDTO(store.tags[index])
        }
    }

    private func deleteTag(_ id: UUID) throws -> TagDeleteResponse {
        try write { store in
            guard let tag = store.tag(id: id) else { throw DemoHTTPError.notFound("Tag not found") }
            let affected = store.videoCount(tagId: id)
            store.videoTags.removeAll { $0.tagId == id }
            store.tags.removeAll { $0.id == id }
            // Smart lists must not keep referencing the deleted tag.
            for index in store.smartLists.indices {
                if let criteria = try? SmartListCriteria.decode(json: store.smartLists[index].criteria),
                   let updated = criteria.removingTag(id),
                   let json = try? updated.canonicalJSON() {
                    store.smartLists[index].criteria = json
                }
            }
            return TagDeleteResponse(success: true, message: "Tag '\(tag.name)' deleted successfully", affectedVideoCount: affected)
        }
    }

    private func replaceTags(fileId: String, with tagIds: [UUID]) throws -> VideoTagsResponse {
        try write { store in
            _ = try requireVideo(fileId, in: store)
            for tagId in tagIds where store.tag(id: tagId) == nil {
                throw DemoHTTPError.badRequest("Tag with ID '\(tagId)' not found")
            }
            let previous = store.videoTags.filter { $0.fileId == fileId }
            store.videoTags.removeAll { $0.fileId == fileId }
            var seen = Set<UUID>()
            for tagId in tagIds where seen.insert(tagId).inserted {
                let rating = previous.first { $0.tagId == tagId }?.rating
                store.videoTags.append(DemoStore.VideoTag(fileId: fileId, tagId: tagId, rating: rating))
            }
            return VideoTagsResponse(tags: store.tagSummaries(fileId: fileId, withRatings: false))
        }
    }

    private func attachTag(_ tagId: UUID, to fileId: String) throws -> VideoTagsResponse {
        try write { store in
            _ = try requireVideo(fileId, in: store)
            _ = try requireTag(tagId, in: store)
            if !store.videoTags.contains(where: { $0.fileId == fileId && $0.tagId == tagId }) {
                store.videoTags.append(DemoStore.VideoTag(fileId: fileId, tagId: tagId, rating: nil))
            }
            return VideoTagsResponse(tags: store.tagSummaries(fileId: fileId, withRatings: false))
        }
    }

    private func detachTag(_ tagId: UUID, from fileId: String) throws {
        try write { store in
            _ = try requireVideo(fileId, in: store)
            guard store.videoTags.contains(where: { $0.fileId == fileId && $0.tagId == tagId }) else {
                throw DemoHTTPError.notFound("Tag is not assigned to this video")
            }
            store.videoTags.removeAll { $0.fileId == fileId && $0.tagId == tagId }
        }
    }

    private func applyTagsInBulk(_ request: BulkTagApplyRequest) throws -> BulkTagApplyResponse {
        let fileIds = Array(Set(request.fileIds))
        let add = Set(request.addTagIds ?? [])
        let remove = Set(request.removeTagIds ?? [])
        guard fileIds.count <= 10_000 else { throw DemoHTTPError.badRequest("At most 10000 fileIds per request") }
        guard add.isDisjoint(with: remove) else { throw DemoHTTPError.badRequest("A tag cannot be both added and removed") }

        return try write { store in
            if let unknown = fileIds.first(where: { store.video(fileId: $0) == nil }) {
                throw DemoHTTPError.badRequest("Unknown fileId '\(unknown)'")
            }
            if let unknown = add.union(remove).first(where: { store.tag(id: $0) == nil }) {
                throw DemoHTTPError.badRequest("Tag with ID '\(unknown)' not found")
            }
            var updated = 0
            for fileId in fileIds {
                let before = store.videoTags.filter { $0.fileId == fileId }
                store.videoTags.removeAll { $0.fileId == fileId && remove.contains($0.tagId) }
                for tagId in add.sorted(by: { $0.uuidString < $1.uuidString })
                where !store.videoTags.contains(where: { $0.fileId == fileId && $0.tagId == tagId }) {
                    store.videoTags.append(DemoStore.VideoTag(fileId: fileId, tagId: tagId, rating: nil))
                }
                if store.videoTags.filter({ $0.fileId == fileId }) != before {
                    updated += 1
                }
            }
            return BulkTagApplyResponse(updated: updated)
        }
    }

    private func setTagRating(_ rating: Int, tagId: UUID, fileId: String) throws {
        try write { store in
            let tag = try requireTag(tagId, in: store)
            guard tag.ratingEnabled else {
                throw DemoHTTPError.badRequest("Tag '\(tag.name)' does not have rating enabled")
            }
            guard let index = store.videoTags.firstIndex(where: { $0.fileId == fileId && $0.tagId == tagId }) else {
                throw DemoHTTPError.notFound("Video does not have this tag assigned")
            }
            store.videoTags[index].rating = rating
        }
    }
}

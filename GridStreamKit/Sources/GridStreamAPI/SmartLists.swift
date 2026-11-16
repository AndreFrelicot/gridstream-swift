import Foundation

// MARK: - Smart lists

/// A smart list. `criteria` is the canonical JSON of `SmartListCriteria`.
public struct SmartListDTO: Codable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let criteria: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: UUID, name: String, criteria: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.criteria = criteria
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Body of `POST /api/v1/smart-lists`.
public struct CreateSmartListRequest: Codable, Sendable {
    public let name: String
    public let criteria: String

    public init(name: String, criteria: String) {
        self.name = name
        self.criteria = criteria
    }
}

/// Body of `PUT /api/v1/smart-lists/:id`.
public struct UpdateSmartListRequest: Codable, Sendable {
    public let name: String?
    public let criteria: String?

    public init(name: String?, criteria: String?) {
        self.name = name
        self.criteria = criteria
    }
}

/// Response of `DELETE /api/v1/smart-lists/:id`.
public struct SmartListDeleteResponse: Codable, Sendable {
    public let success: Bool
    public let message: String

    public init(success: Bool, message: String) {
        self.success = success
        self.message = message
    }
}

/// `GET /api/v1/smart-lists`.
public struct SmartListsResponse: Codable, Sendable {
    public let smartLists: [SmartListDTO]

    public init(smartLists: [SmartListDTO]) {
        self.smartLists = smartLists
    }
}

/// `GET /api/v1/smart-lists/memberships`: each video `fileId` mapped to the
/// ids of the smart lists it currently matches. Only videos that belong to at
/// least one smart list are included.
public struct SmartListMembershipsResponse: Codable, Sendable {
    public let memberships: [String: [UUID]]

    public init(memberships: [String: [UUID]]) {
        self.memberships = memberships
    }
}

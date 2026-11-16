import Foundation

nonisolated struct SourceDirectory: Codable, Identifiable, Hashable {
    let id: UUID
    var path: String
    var isEnabled: Bool
    var lastScanned: Date?
    var bookmarkData: Data?

    init(
        id: UUID = UUID(),
        path: String,
        isEnabled: Bool = true,
        lastScanned: Date? = nil,
        bookmarkData: Data? = nil
    ) {
        self.id = id
        self.path = path
        self.isEnabled = isEnabled
        self.lastScanned = lastScanned
        self.bookmarkData = bookmarkData
    }
}

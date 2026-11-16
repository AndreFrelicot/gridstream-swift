import Foundation
import GRDB

nonisolated enum V21_AddAnnotationText: Sendable {
    static let migrationIdentifier = "v21_add_annotation_text"

    static func migrate(_ db: Database) throws {
        try db.alter(table: "video_annotations") { t in
            t.add(column: "text", .text)
        }
    }
}

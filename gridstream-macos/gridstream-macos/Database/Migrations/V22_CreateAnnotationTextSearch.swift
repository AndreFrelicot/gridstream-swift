import Foundation
import GRDB

nonisolated enum V22_CreateAnnotationTextSearch: Sendable {
    static let migrationIdentifier = "v22_create_annotation_text_search"

    static func migrate(_ db: Database) throws {
        try db.execute(sql: """
            CREATE VIRTUAL TABLE video_annotation_text_fts USING fts5(
                annotation_id UNINDEXED,
                video_file_id UNINDEXED,
                text,
                tokenize = 'unicode61'
            )
            """)

        try db.execute(sql: """
            INSERT INTO video_annotation_text_fts(rowid, annotation_id, video_file_id, text)
            SELECT rowid, id, video_file_id, text
            FROM video_annotations
            WHERE text IS NOT NULL AND TRIM(text) <> ''
            """)

        try db.execute(sql: """
            CREATE TRIGGER video_annotations_text_fts_insert
            AFTER INSERT ON video_annotations
            WHEN NEW.text IS NOT NULL AND TRIM(NEW.text) <> ''
            BEGIN
                INSERT INTO video_annotation_text_fts(rowid, annotation_id, video_file_id, text)
                VALUES (NEW.rowid, NEW.id, NEW.video_file_id, NEW.text);
            END
            """)

        try db.execute(sql: """
            CREATE TRIGGER video_annotations_text_fts_update
            AFTER UPDATE OF video_file_id, text ON video_annotations
            BEGIN
                DELETE FROM video_annotation_text_fts WHERE rowid = OLD.rowid;
                INSERT INTO video_annotation_text_fts(rowid, annotation_id, video_file_id, text)
                SELECT NEW.rowid, NEW.id, NEW.video_file_id, NEW.text
                WHERE NEW.text IS NOT NULL AND TRIM(NEW.text) <> '';
            END
            """)

        try db.execute(sql: """
            CREATE TRIGGER video_annotations_text_fts_delete
            AFTER DELETE ON video_annotations
            BEGIN
                DELETE FROM video_annotation_text_fts WHERE rowid = OLD.rowid;
            END
            """)
    }
}

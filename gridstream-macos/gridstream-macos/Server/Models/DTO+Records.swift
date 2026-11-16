import Foundation
import GridStreamAPI

// Mapping from stored GRDB records to the shared wire types (GridStreamAPI).
// Record timestamps are seconds since 1970.

nonisolated extension TagDTO {
    init(from tag: TagRecord, videoCount: Int) {
        self.init(
            id: tag.id,
            name: tag.name,
            color: tag.color,
            description: tag.description,
            ratingEnabled: tag.ratingEnabled,
            videoCount: videoCount,
            createdAt: Date(timeIntervalSince1970: tag.createdAt),
            updatedAt: Date(timeIntervalSince1970: tag.updatedAt)
        )
    }
}

nonisolated extension TagSummary {
    init(from tag: TagRecord, rating: Int? = nil) {
        self.init(id: tag.id, name: tag.name, color: tag.color, ratingEnabled: tag.ratingEnabled, rating: rating)
    }
}

nonisolated extension SmartListDTO {
    init(from smartList: SmartListRecord) {
        self.init(
            id: smartList.id,
            name: smartList.name,
            criteria: smartList.criteria,
            createdAt: Date(timeIntervalSince1970: smartList.createdAt),
            updatedAt: Date(timeIntervalSince1970: smartList.updatedAt)
        )
    }
}

nonisolated extension SimpleListDTO {
    /// `sort_order` is stored canonical (validated on write, normalized by V29).
    init(from simpleList: SimpleListRecord, videoIds: [String]) {
        self.init(
            id: simpleList.id,
            name: simpleList.name,
            videoIds: videoIds,
            videoCount: videoIds.count,
            sortOrder: SimpleListSortOrder(lenient: simpleList.sortOrder),
            createdAt: Date(timeIntervalSince1970: simpleList.createdAt),
            updatedAt: Date(timeIntervalSince1970: simpleList.updatedAt)
        )
    }
}

nonisolated extension TimeRangeDTO {
    init(from record: TimeRangeRecord) {
        self.init(
            id: record.id,
            videoFileId: record.videoFileId,
            startTime: record.startTime,
            endTime: record.endTime,
            label: record.label,
            createdAt: Date(timeIntervalSince1970: record.createdAt),
            updatedAt: Date(timeIntervalSince1970: record.updatedAt)
        )
    }
}

nonisolated extension AnnotationDTO {
    init(from record: AnnotationRecord) {
        self.init(
            id: record.id,
            videoFileId: record.videoFileId,
            frameTime: record.frameTime,
            frameRate: record.frameRate,
            strokesJSON: record.strokesJSON,
            text: record.text,
            createdAt: Date(timeIntervalSince1970: record.createdAt),
            updatedAt: Date(timeIntervalSince1970: record.updatedAt)
        )
    }
}

nonisolated extension FrameCaptureDTO {
    init(from record: FrameCaptureRecord, filename: String? = nil) {
        self.init(
            id: record.id,
            fileId: record.fileId,
            timestamp: record.timestamp,
            width: record.width,
            height: record.height,
            fileSize: record.fileSize,
            createdAt: Date(timeIntervalSince1970: record.createdAt),
            filename: filename
        )
    }
}

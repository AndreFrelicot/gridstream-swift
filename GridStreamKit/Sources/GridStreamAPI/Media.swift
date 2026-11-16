import Foundation

// MARK: - Time ranges

/// A labelled segment of a video (`/api/v1/videos/:fileId/time-ranges`).
public struct TimeRangeDTO: Codable, Identifiable, Sendable {
    public let id: UUID
    public let videoFileId: String
    public let startTime: Double
    public let endTime: Double
    public let label: String?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        videoFileId: String,
        startTime: Double,
        endTime: Double,
        label: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.videoFileId = videoFileId
        self.startTime = startTime
        self.endTime = endTime
        self.label = label
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Body of `POST /api/v1/videos/:fileId/time-ranges`.
public struct CreateTimeRangeRequest: Codable, Sendable {
    public let startTime: Double
    public let endTime: Double
    public let label: String?

    public init(startTime: Double, endTime: Double, label: String?) {
        self.startTime = startTime
        self.endTime = endTime
        self.label = label
    }
}

/// `GET /api/v1/videos/:fileId/time-ranges`.
public struct TimeRangeListResponse: Codable, Sendable {
    public let timeRanges: [TimeRangeDTO]
    public let total: Int

    public init(timeRanges: [TimeRangeDTO], total: Int) {
        self.timeRanges = timeRanges
        self.total = total
    }
}

// MARK: - Annotations

/// A drawing (and optional text) pinned to one frame of a video.
/// `strokesJSON` is opaque to the server.
public struct AnnotationDTO: Codable, Identifiable, Sendable {
    public let id: UUID
    public let videoFileId: String
    public let frameTime: Double
    public let frameRate: Double
    public let strokesJSON: String
    public let text: String?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        videoFileId: String,
        frameTime: Double,
        frameRate: Double,
        strokesJSON: String,
        text: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.videoFileId = videoFileId
        self.frameTime = frameTime
        self.frameRate = frameRate
        self.strokesJSON = strokesJSON
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Body of `PUT /api/v1/videos/:fileId/annotations`. `text` is always
/// encoded, as `null` when there is none (clearing a previous text).
public struct UpsertAnnotationRequest: Codable, Sendable {
    public let frameTime: Double
    public let frameRate: Double
    public let strokesJSON: String
    public let text: String?

    private enum CodingKeys: String, CodingKey {
        case frameTime, frameRate, strokesJSON, text
    }

    public init(frameTime: Double, frameRate: Double, strokesJSON: String, text: String?) {
        self.frameTime = frameTime
        self.frameRate = frameRate
        self.strokesJSON = strokesJSON
        self.text = text
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frameTime, forKey: .frameTime)
        try container.encode(frameRate, forKey: .frameRate)
        try container.encode(strokesJSON, forKey: .strokesJSON)
        try container.encode(text, forKey: .text)
    }
}

/// `GET /api/v1/videos/:fileId/annotations`.
public struct AnnotationListResponse: Codable, Sendable {
    public let annotations: [AnnotationDTO]
    public let total: Int

    public init(annotations: [AnnotationDTO], total: Int) {
        self.annotations = annotations
        self.total = total
    }
}

/// `GET /api/v1/videos/:fileId/annotations/times`.
public struct AnnotationTimesResponse: Codable, Sendable {
    public let times: [Double]

    public init(times: [Double]) {
        self.times = times
    }
}

// MARK: - Frame captures

/// A still frame captured from a video.
public struct FrameCaptureDTO: Codable, Identifiable, Sendable {
    public let id: String
    public let fileId: String
    public let timestamp: Double
    public let width: Int
    public let height: Int
    public let fileSize: Int
    public let createdAt: Date
    public let filename: String?

    public init(
        id: String,
        fileId: String,
        timestamp: Double,
        width: Int,
        height: Int,
        fileSize: Int,
        createdAt: Date,
        filename: String? = nil
    ) {
        self.id = id
        self.fileId = fileId
        self.timestamp = timestamp
        self.width = width
        self.height = height
        self.fileSize = fileSize
        self.createdAt = createdAt
        self.filename = filename
    }
}

/// Body of `POST /api/v1/videos/:fileId/captures`.
public struct CreateFrameCaptureRequest: Codable, Sendable {
    public let timestamp: Double

    public init(timestamp: Double) {
        self.timestamp = timestamp
    }
}

/// `GET /api/v1/videos/:fileId/captures` and `GET /api/v1/captures`.
public struct FrameCaptureListResponse: Codable, Sendable {
    public let captures: [FrameCaptureDTO]
    public let total: Int

    public init(captures: [FrameCaptureDTO], total: Int) {
        self.captures = captures
        self.total = total
    }
}

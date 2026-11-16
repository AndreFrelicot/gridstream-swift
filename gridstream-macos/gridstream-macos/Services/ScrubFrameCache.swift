import Foundation
import GRDB
import OSLog

actor ScrubFrameCache {
    static let shared = ScrubFrameCache(databaseManager: .shared)

    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    private let logger = Logger(subsystem: "com.gridstream.macos", category: "ScrubFrameCache")

    func getFrame(videoId: String, time: Double) async throws -> Data? {
        let roundedTime = roundTime(time)
        return try await databaseManager.read { db in
            try ScrubFrameRecord.find(fileId: videoId, timestamp: roundedTime, in: db)?.frameData
        }
    }

    func storeFrame(videoId: String, time: Double, data: Data) async throws {
        let roundedTime = roundTime(time)
        try await databaseManager.write { db in
            let record = ScrubFrameRecord(
                fileId: videoId,
                timestamp: roundedTime,
                frameData: data,
                quality: 85
            )
            try record.upsert(db)
            try db.execute(sql: """
                UPDATE video_files SET scrub_frame_count =
                    (SELECT COUNT(*) FROM scrub_frames WHERE file_id = ?)
                WHERE file_id = ?
                """, arguments: [videoId, videoId])
        }
        logger.debug("Stored frame for \(videoId) at \(roundedTime)s, size: \(data.count) bytes")
    }

    /// Stores many frames for a video in a single write transaction.
    /// `using` is a seam for tests to target a temp database; production callers use `.shared`.
    func storeFrames(
        videoId: String,
        frames: [(time: Double, data: Data)],
        using databaseManager: DatabaseManager = .shared
    ) async throws {
        guard !frames.isEmpty else { return }
        let prepared = frames.map { (timestamp: roundTime($0.time), data: $0.data) }
        try await databaseManager.write { db in
            for frame in prepared {
                let record = ScrubFrameRecord(
                    fileId: videoId,
                    timestamp: frame.timestamp,
                    frameData: frame.data,
                    quality: 85
                )
                try record.upsert(db)
            }
            try db.execute(sql: """
                UPDATE video_files SET scrub_frame_count =
                    (SELECT COUNT(*) FROM scrub_frames WHERE file_id = ?)
                WHERE file_id = ?
                """, arguments: [videoId, videoId])
        }
        logger.debug("Stored \(prepared.count) frames for \(videoId) in one transaction")
    }

    func getCachedTimes(videoId: String) async throws -> [Double] {
        try await databaseManager.read { db in
            try ScrubFrameRecord.timestamps(forFileId: videoId, in: db)
        }
    }

    func clearFrames(videoId: String) async throws {
        let count = try await databaseManager.write { db in
            let deleted = try ScrubFrameRecord.deleteByFileId(videoId, in: db)
            try db.execute(sql: "UPDATE video_files SET scrub_frame_count = 0 WHERE file_id = ?", arguments: [videoId])
            return deleted
        }
        logger.info("Cleared \(count) frames for video \(videoId)")
    }

    func frameCount(videoId: String) async throws -> Int {
        try await databaseManager.read { db in
            try ScrubFrameRecord.count(forFileId: videoId, in: db)
        }
    }

    func hasFrame(videoId: String, time: Double) async throws -> Bool {
        let roundedTime = roundTime(time)
        return try await databaseManager.read { db in
            try ScrubFrameRecord.find(fileId: videoId, timestamp: roundedTime, in: db) != nil
        }
    }

    func clearAllScrubData() async throws -> (framesDeleted: Int, videosDeleted: Int) {
        let framesDeleted = try await databaseManager.write { db in
            let deleted = try ScrubFrameRecord.deleteAll(in: db)
            try db.execute(sql: "UPDATE video_files SET scrub_frame_count = 0")
            return deleted
        }
        logger.info("Cleared all scrub data: \(framesDeleted) frames")
        return (framesDeleted, 0)
    }

    private func roundTime(_ time: Double) -> Double {
        (time / ScrubFrameGenerator.frameInterval).rounded() * ScrubFrameGenerator.frameInterval
    }
}

import Foundation
import OSLog

actor BackgroundFrameManager {
    static let shared = BackgroundFrameManager(databaseManager: .shared)

    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    private let logger = Logger(subsystem: "com.gridstream.macos", category: "BackgroundFrameManager")

    private struct ActiveGeneration {
        let id: UUID
        let task: Task<Void, Never>
    }

    private var activeTasks: [String: ActiveGeneration] = [:]
    private var pausedVideoIds: Set<String> = []
    private var queued: [String] = []
    private var runningCount = 0

    /// At most this many videos generate concurrently; the rest wait FIFO in `queued`.
    private static let maxConcurrentVideos = 2
    /// Small batch ⇒ frames become visible to the iPad's `cached-times` polling quickly.
    /// Intentionally far below the idle path's 100 (no one is watching the idle sweep).
    private static let onDemandFlushBatch = 15

    /// Enqueue a video for bulk scrub generation. Lightweight: the expensive prep
    /// (DB lookup, cached-times, time computation) happens in `runGeneration` only
    /// once a slot opens. Re-triggering a running or queued video is a no-op (dedup).
    func startGeneration(videoId: String) {
        guard activeTasks[videoId] == nil, !queued.contains(videoId) else {
            return
        }
        queued.append(videoId)
        pump()
    }

    /// Start queued videos until the concurrency cap is reached.
    private func pump() {
        while runningCount < Self.maxConcurrentVideos, !queued.isEmpty {
            let videoId = queued.removeFirst()
            runningCount += 1

            let generationId = UUID()
            let task = Task { [weak self] in
                guard let self else { return }
                defer {
                    Task { await self.finishGeneration(videoId: videoId, generationId: generationId) }
                }
                await self.runGeneration(videoId: videoId)
            }
            activeTasks[videoId] = ActiveGeneration(id: generationId, task: task)
        }
    }

    /// Per-video work: prepare the times to generate, then stream-and-store them.
    private func runGeneration(videoId: String) async {
        let videoRecord: VideoFileRecord?
        do {
            videoRecord = try await databaseManager.read { db in
                try VideoFileRecord.findByFileId(videoId, in: db)
            }
        } catch {
            logger.error("Failed to look up video \(videoId): \(error.localizedDescription)")
            return
        }

        guard let record = videoRecord else {
            logger.error("Video not found: \(videoId)")
            return
        }

        let totalFrames = Int(record.duration / ScrubFrameGenerator.frameInterval)
        guard totalFrames > 0 else {
            logger.debug("No frames to generate for \(videoId) (duration: \(record.duration)s)")
            return
        }

        let allTimes = (0..<totalFrames).map { Double($0) * ScrubFrameGenerator.frameInterval }

        let cachedTimes: Set<Double>
        do {
            let times = try await ScrubFrameCache.shared.getCachedTimes(videoId: videoId)
            cachedTimes = Set(times)
        } catch {
            logger.error("Failed to get cached times for \(videoId): \(error.localizedDescription)")
            return
        }

        // Sorted (not shuffled) so the reused generator decodes sequentially with minimal seeking.
        let timesToGenerate = allTimes.filter { !cachedTimes.contains($0) }.sorted()
        guard !timesToGenerate.isEmpty else {
            logger.info("All \(totalFrames) frames already cached for \(videoId)")
            return
        }
        let expected = timesToGenerate.count

        logger.info("Starting background generation for \(videoId): \(timesToGenerate.count) frames remaining")

        let result = await ScrubFrameGenerator.shared.generateAndStore(
            videoId: videoId,
            videoPath: record.path,
            times: timesToGenerate,
            flushEvery: Self.onDemandFlushBatch
        )

        // On-demand failures surface too; don't count a cancelled run as a failed attempt.
        if !Task.isCancelled {
            await ScrubFrameGenerator.shared.recordOutcome(
                fileId: videoId, expected: expected, result: result)
        }

        logger.info("Background generation finished for \(videoId)")
    }

    func stopGeneration(videoId: String) {
        if let generation = activeTasks[videoId] {
            // The task's `defer` → `finishGeneration` decrements `runningCount` and pumps next.
            generation.task.cancel()
            logger.info("Stopped generation for \(videoId)")
        } else if let index = queued.firstIndex(of: videoId) {
            queued.remove(at: index)
            logger.debug("Removed queued generation for \(videoId)")
        } else {
            logger.debug("No active generation to stop for \(videoId)")
        }
    }

    func isGenerating(videoId: String) -> Bool {
        if let generation = activeTasks[videoId] {
            return !generation.task.isCancelled
        }
        return queued.contains(videoId)
    }

    func pauseAll() -> Int {
        pausedVideoIds = Set(activeTasks.keys).union(queued)
        queued.removeAll()

        for (videoId, generation) in activeTasks {
            generation.task.cancel()
            logger.debug("Paused generation for \(videoId)")
        }
        // Reset bookkeeping synchronously; the cancelled tasks' deferred `finishGeneration`
        // calls become no-ops (the `generationId` guard fails once the slot is gone), so
        // `runningCount` cannot go negative and no stale task can corrupt state on resume.
        activeTasks.removeAll()
        runningCount = 0

        logger.info("Paused all background generation: \(self.pausedVideoIds.count) videos")
        return pausedVideoIds.count
    }

    func resumeAll() -> Int {
        let videosToResume = pausedVideoIds
        pausedVideoIds.removeAll()

        guard !videosToResume.isEmpty else {
            logger.debug("No paused videos to resume")
            return 0
        }

        logger.info("Resuming background generation for \(videosToResume.count) videos")

        for videoId in videosToResume {
            startGeneration(videoId: videoId)
        }

        return videosToResume.count
    }

    func getPausedCount() -> Int {
        pausedVideoIds.count
    }

    private func finishGeneration(videoId: String, generationId: UUID) {
        guard activeTasks[videoId]?.id == generationId else {
            return
        }
        activeTasks.removeValue(forKey: videoId)
        runningCount -= 1
        pump()
    }
}

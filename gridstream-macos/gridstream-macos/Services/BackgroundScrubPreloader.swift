import Foundation
import OSLog

enum BackgroundScrubStatus: String {
    case idle = "Idle"
    case running = "Running"
    case paused = "Paused (client connected)"
    case disabled = "Disabled"

    /// The status as shown in Settings.
    var title: LocalizedStringResource {
        switch self {
        case .idle: "Idle"
        case .running: "Running"
        case .paused: "Paused (client connected)"
        case .disabled: "Disabled"
        }
    }
}

/// Stable per-worker progress for the idle scrub sweep. One entry per active worker
/// slot so the settings UI can update the filename/frame in place — no row appearing
/// or disappearing between videos (which previously caused flickering).
struct ScrubWorkerProgress: Identifiable {
    let id: Int
    var videoName: String?
    var currentFrame: Int = 0
    var totalFrames: Int = 0
}

@MainActor @Observable
final class BackgroundScrubPreloader {
    static let shared = BackgroundScrubPreloader(databaseManager: .shared)

    private let logger = Logger(subsystem: "com.gridstream.macos", category: "BackgroundScrubPreloader")
    private let userDefaultsKey = "backgroundScrubEnabled"
    private let workersKey = "backgroundScrubWorkers"
    private let inactivityThreshold: TimeInterval = 30
    private static let insertBatchSize = 100

    private(set) var status: BackgroundScrubStatus = .disabled
    private(set) var workers: [ScrubWorkerProgress] = []

    private var processingTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var nextVideoIndex = 0
    private let databaseManager: DatabaseManager

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: userDefaultsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: userDefaultsKey)
            if newValue {
                startMonitoring()
            } else {
                stopAll()
            }
        }
    }

    var maxConcurrentWorkers: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: workersKey)
            return value > 0 ? min(value, 4) : 2
        }
        set {
            UserDefaults.standard.set(min(max(newValue, 1), 4), forKey: workersKey)
        }
    }

    private init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
        if isEnabled {
            startMonitoring()
        }
    }

    func startMonitoring() {
        guard monitorTask == nil else { return }

        logger.info("Starting background scrub monitoring")
        status = .idle

        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                let hasActivity = await ClientActivityTracker.shared.hasRecentActivity(within: self.inactivityThreshold)

                await MainActor.run {
                    if hasActivity {
                        if self.status == .running {
                            self.pauseProcessing()
                        }
                    } else {
                        if self.status == .idle || self.status == .paused {
                            self.startProcessing()
                        }
                    }
                }

                try? await Task.sleep(nanoseconds: 5_000_000_000) // Check every 5 seconds
            }
        }
    }

    private func startProcessing() {
        guard processingTask == nil else { return }
        guard isEnabled else {
            status = .disabled
            return
        }

        logger.info("Starting background scrub processing")
        status = .running

        processingTask = Task { [weak self] in
            await self?.processAllVideos()
        }
    }

    private func pauseProcessing() {
        processingTask?.cancel()
        processingTask = nil
        status = .paused
        workers = []
        logger.info("Paused background scrub processing (client connected)")
    }

    private func stopAll() {
        monitorTask?.cancel()
        monitorTask = nil
        processingTask?.cancel()
        processingTask = nil
        status = .disabled
        workers = []
        logger.info("Stopped background scrub processing")
    }

    private func processAllVideos() async {
        let videos: [VideoFileRecord]
        do {
            videos = try await databaseManager.read { db in
                try VideoFileRecord.fetchScrubCandidates(in: db)
            }
        } catch {
            logger.error("Failed to fetch videos: \(error.localizedDescription)")
            status = .idle
            processingTask = nil
            return
        }

        guard !videos.isEmpty else {
            logger.info("No videos to process")
            status = .idle
            processingTask = nil
            return
        }

        // One stable slot per worker. The settings UI renders these rows for the whole
        // run and only their contents change, so nothing appears/disappears mid-sweep.
        let workerCount = min(maxConcurrentWorkers, videos.count)
        nextVideoIndex = 0
        workers = (0..<workerCount).map { ScrubWorkerProgress(id: $0, videoName: nil) }

        logger.info("Processing \(videos.count) videos for scrub frames with \(workerCount) workers")

        // Fixed worker tasks pull videos from a shared cursor. Each `processVideo` is
        // @MainActor but its heavy work is the `nonisolated` helper, so videos decode
        // concurrently while cheap slot updates interleave serially on MainActor.
        await withTaskGroup(of: Void.self) { group in
            for slot in 0..<workerCount {
                group.addTask { await self.runWorker(slot: slot, videos: videos) }
            }
        }

        // On cancellation (pause/stop) the caller already reset state — don't clobber it.
        if !Task.isCancelled {
            status = .idle
            workers = []
            processingTask = nil
        }

        logger.info("Background scrub processing complete")
    }

    /// Pulls videos from the shared cursor until the catalog is exhausted, keeping this
    /// worker's slot pointed at whatever it is currently decoding.
    private func runWorker(slot: Int, videos: [VideoFileRecord]) async {
        while let video = claimNextVideo(from: videos) {
            await processVideo(video, slot: slot)
        }
    }

    /// Atomically (MainActor-isolated) hands the next unclaimed video to a worker.
    private func claimNextVideo(from videos: [VideoFileRecord]) -> VideoFileRecord? {
        guard nextVideoIndex < videos.count, !Task.isCancelled else { return nil }
        let video = videos[nextVideoIndex]
        nextVideoIndex += 1
        return video
    }

    private func processVideo(_ video: VideoFileRecord, slot: Int) async {
        let totalFrames = Int(video.duration / ScrubFrameGenerator.frameInterval)
        guard totalFrames > 0 else { return }

        let allTimes = (0..<totalFrames).map { Double($0) * ScrubFrameGenerator.frameInterval }

        let cachedTimes: Set<Double>
        do {
            let times = try await ScrubFrameCache.shared.getCachedTimes(videoId: video.fileId)
            cachedTimes = Set(times)
        } catch {
            logger.error("Failed to get cached times for \(video.filename): \(error.localizedDescription)")
            return
        }

        // Sorted (not shuffled) so the reused generator decodes sequentially with minimal seeking.
        let timesToGenerate = allTimes.filter { !cachedTimes.contains($0) }.sorted()
        guard !timesToGenerate.isEmpty else { return }
        let expected = timesToGenerate.count

        // Point this worker's slot at the video it is now decoding (updated in place).
        if slot < workers.count {
            workers[slot].videoName = video.filename
            workers[slot].currentFrame = 0
            workers[slot].totalFrames = timesToGenerate.count
        }

        let result = await ScrubFrameGenerator.shared.generateAndStore(
            videoId: video.fileId,
            videoPath: video.path,
            times: timesToGenerate,
            flushEvery: Self.insertBatchSize
        ) { count in
            await MainActor.run {
                guard slot < self.workers.count else { return }
                self.workers[slot].currentFrame += count
            }
        }

        // Don't count a paused/cancelled sweep as a failed attempt.
        if !Task.isCancelled {
            await ScrubFrameGenerator.shared.recordOutcome(
                fileId: video.fileId, expected: expected, result: result)
        }

        logger.info("Completed \(video.filename): \(timesToGenerate.count) frames requested")
    }
}

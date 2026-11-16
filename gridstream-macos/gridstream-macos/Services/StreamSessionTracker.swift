import Foundation
import OSLog
import GRDB

actor StreamSessionTracker {
    static let shared = StreamSessionTracker(databaseManager: .shared)

    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    private let logger = Logger(subsystem: "com.gridstream.macos", category: "StreamSessionTracker")

    // Session keyed by (fileId, clientIP)
    private struct SessionKey: Hashable {
        let fileId: String
        let clientIP: String
    }

    private struct Session {
        var firstActivity: Date
        var lastActivity: Date
        var playCountIncremented: Bool = false
        var lastFlushTime: Date

        init() {
            let now = Date()
            firstActivity = now
            lastActivity = now
            lastFlushTime = now
        }
    }

    private enum PendingStatMutation {
        case incrementPlayCount(fileId: String)
        case addViewTime(fileId: String, seconds: Int)
    }

    private var sessions: [SessionKey: Session] = [:]
    private var processingTask: Task<Void, Never>?

    // Constants
    private static let processInterval: UInt64 = 10_000_000_000 // 10 seconds
    private static let playCountThreshold: TimeInterval = 60 // 60s of activity → increment play count
    private static let viewTimeFlushInterval: TimeInterval = 60 // flush view time every 60s
    private static let sessionTimeout: TimeInterval = 30 // expire after 30s inactivity

    /// Called on each stream request to record activity
    func recordStreamActivity(fileId: String, clientIP: String) {
        let key = SessionKey(fileId: fileId, clientIP: clientIP)
        if sessions[key] != nil {
            sessions[key]!.lastActivity = Date()
        } else {
            sessions[key] = Session()
            logger.info("New stream session: \(fileId) from \(clientIP)")
        }
    }

    /// Start the background processing loop
    func startProcessing() {
        guard processingTask == nil else { return }
        logger.info("Starting stream session processing")
        processingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.processInterval)
                guard !Task.isCancelled else { break }
                await self?.processSessions()
            }
        }
    }

    /// Stop the background processing loop and flush remaining sessions
    func stopProcessing() async {
        processingTask?.cancel()
        processingTask = nil
        await flushAllSessions()
        logger.info("Stopped stream session processing")
    }

    private func processSessions() async {
        let now = Date()
        var expiredKeys: [SessionKey] = []
        var pendingMutations: [PendingStatMutation] = []

        for (key, var session) in sessions {
            let activityDuration = session.lastActivity.timeIntervalSince(session.firstActivity)
            let timeSinceLastActivity = now.timeIntervalSince(session.lastActivity)

            // Check if session has expired (no activity for 30s)
            if timeSinceLastActivity >= Self.sessionTimeout {
                if !session.playCountIncremented && activityDuration >= Self.playCountThreshold {
                    pendingMutations.append(.incrementPlayCount(fileId: key.fileId))
                    session.playCountIncremented = true
                }

                // Flush any remaining accumulated time before removing
                let unflushedSeconds = session.lastActivity.timeIntervalSince(session.lastFlushTime)
                if unflushedSeconds > 0 {
                    let secondsToFlush = Int(unflushedSeconds)
                    if secondsToFlush > 0 {
                        pendingMutations.append(.addViewTime(fileId: key.fileId, seconds: secondsToFlush))
                    }
                }
                expiredKeys.append(key)
                logger.info("Session expired: \(key.fileId) from \(key.clientIP) (duration: \(Int(activityDuration))s)")
                continue
            }

            // Check if we should increment play count (after 60s of activity, once per session)
            if !session.playCountIncremented && activityDuration >= Self.playCountThreshold {
                session.playCountIncremented = true
                pendingMutations.append(.incrementPlayCount(fileId: key.fileId))
                logger.info("Play count incremented: \(key.fileId) from \(key.clientIP)")
            }

            // Flush accumulated view time every 60s
            let timeSinceLastFlush = now.timeIntervalSince(session.lastFlushTime)
            if timeSinceLastFlush >= Self.viewTimeFlushInterval {
                let secondsToFlush = Int(timeSinceLastFlush)
                if secondsToFlush > 0 {
                    pendingMutations.append(.addViewTime(fileId: key.fileId, seconds: secondsToFlush))
                    session.lastFlushTime = now
                }
            }

            sessions[key] = session
        }

        // Remove expired sessions
        for key in expiredKeys {
            sessions.removeValue(forKey: key)
        }

        await apply(pendingMutations)
    }

    private func flushAllSessions() async {
        var pendingMutations: [PendingStatMutation] = []

        for (key, session) in sessions {
            let activityDuration = session.lastActivity.timeIntervalSince(session.firstActivity)
            if !session.playCountIncremented && activityDuration >= Self.playCountThreshold {
                pendingMutations.append(.incrementPlayCount(fileId: key.fileId))
            }

            let unflushedSeconds = session.lastActivity.timeIntervalSince(session.lastFlushTime)
            if unflushedSeconds > 0 {
                let secondsToFlush = Int(unflushedSeconds)
                if secondsToFlush > 0 {
                    pendingMutations.append(.addViewTime(fileId: key.fileId, seconds: secondsToFlush))
                }
            }
        }
        sessions.removeAll()

        await apply(pendingMutations)
    }

    // MARK: - Database Operations

    private func apply(_ mutations: [PendingStatMutation]) async {
        for mutation in mutations {
            switch mutation {
            case .incrementPlayCount(let fileId):
                await incrementPlayCount(fileId: fileId)
            case .addViewTime(let fileId, let seconds):
                await flushViewTime(fileId: fileId, seconds: seconds)
            }
        }
    }

    private func incrementPlayCount(fileId: String) async {
        do {
            try await databaseManager.writeCatalog { db in
                try VideoFileRecord.applyPlaybackReport(
                    fileId: fileId, incrementPlayCount: true, addViewTime: 0, in: db
                ) != nil ? .changed : .unchanged
            }
        } catch {
            logger.error("Failed to increment play count for \(fileId): \(error.localizedDescription)")
        }
    }

    private func flushViewTime(fileId: String, seconds: Int) async {
        do {
            try await databaseManager.writeCatalog { db in
                try VideoFileRecord.applyPlaybackReport(
                    fileId: fileId, incrementPlayCount: false, addViewTime: seconds, in: db
                ) != nil ? .changed : .unchanged
            }
        } catch {
            logger.error("Failed to flush view time for \(fileId): \(error.localizedDescription)")
        }
    }
}

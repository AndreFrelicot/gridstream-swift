import Foundation
import OSLog

actor ClientActivityTracker {
    static let shared = ClientActivityTracker()

    private let logger = Logger(subsystem: "com.gridstream.macos", category: "ClientActivityTracker")
    private var lastActivityTime: Date = .distantPast
    private var activityCount: Int = 0

    func recordActivity() {
        lastActivityTime = Date()
        activityCount += 1
    }

    func hasRecentActivity(within threshold: TimeInterval = 30) -> Bool {
        Date().timeIntervalSince(lastActivityTime) < threshold
    }

    func secondsSinceLastActivity() -> TimeInterval {
        Date().timeIntervalSince(lastActivityTime)
    }

    func getActivityCount() -> Int {
        activityCount
    }

    func reset() {
        lastActivityTime = .distantPast
        activityCount = 0
    }
}

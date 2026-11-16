//
//  PlaybackStatsQueueTests.swift
//  gridstream-ipadTests
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class PlaybackStatsQueueTests: XCTestCase {

    private struct SendFailure: Error {}

    /// Records every call; fails while `failing` is true.
    @MainActor
    private final class RecordingReporter {
        var calls: [(fileId: String, incrementPlayCount: Bool, addViewTime: Int)] = []
        var failing = false

        var reporter: VideoPlayerState.PlaybackStatsReporter {
            { [self] fileId, incrementPlayCount, addViewTime in
                calls.append((fileId, incrementPlayCount, addViewTime))
                if failing { throw SendFailure() }
            }
        }
    }

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "PlaybackStatsQueueTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    func testSuccessfulReportIsSentOnceAndRemoved() async {
        let queue = PlaybackStatsQueue(defaults: defaults)
        let recorder = RecordingReporter()

        await queue.enqueue(fileId: "a", incrementPlayCount: true, addViewTime: 60, reporter: recorder.reporter)
        await queue.flush()
        await queue.flush()

        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertTrue(queue.pendingReports.isEmpty)
    }

    func testFailedReportIsRetriedOnceWithoutDuplication() async {
        let queue = PlaybackStatsQueue(defaults: defaults)
        let recorder = RecordingReporter()
        recorder.failing = true

        await queue.enqueue(fileId: "a", incrementPlayCount: true, addViewTime: 60, reporter: recorder.reporter)
        await queue.enqueue(fileId: "a", incrementPlayCount: false, addViewTime: 30, reporter: recorder.reporter)
        XCTAssertEqual(queue.pendingReports.count, 2, "Failed reports stay queued, unmerged")

        recorder.failing = false
        recorder.calls.removeAll()
        await queue.flush()
        await queue.flush()

        XCTAssertEqual(recorder.calls.count, 2, "Each report is delivered exactly once")
        XCTAssertEqual(recorder.calls.filter { $0.incrementPlayCount }.count, 1)
        XCTAssertEqual(recorder.calls.map(\.addViewTime).reduce(0, +), 90)
        XCTAssertTrue(queue.pendingReports.isEmpty)
    }

    func testPendingReportsSurviveRelaunchAndAreSentOnce() async {
        let recorder = RecordingReporter()
        recorder.failing = true
        let firstLaunch = PlaybackStatsQueue(defaults: defaults)
        await firstLaunch.enqueue(fileId: "a", incrementPlayCount: true, addViewTime: 0, reporter: recorder.reporter)

        recorder.failing = false
        recorder.calls.removeAll()
        let secondLaunch = PlaybackStatsQueue(defaults: defaults)
        XCTAssertEqual(secondLaunch.pendingReports.count, 1)
        await secondLaunch.setReporter(recorder.reporter)
        await secondLaunch.flush()

        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertTrue(PlaybackStatsQueue(defaults: defaults).pendingReports.isEmpty,
                      "A delivered report is gone from disk too")
    }

    func testManyPlayersSharingTheQueueDoNotResendEachOthersReports() async {
        let queue = PlaybackStatsQueue(defaults: defaults)
        let recorder = RecordingReporter()
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!

        let players = (0..<3).map { _ in VideoPlayerState(statsQueue: queue) }
        for (index, player) in players.enumerated() {
            player.configurePlaybackStatsReporter(recorder.reporter)
            player.setupPlayer(url: testURL, fileId: "file-\(index)", autoplay: false)
            for second in 0...60 {
                player.recordPlaybackStatsProgressForTesting(currentTime: Double(second), isPlaybackActive: true)
            }
        }

        // Let the hand-off Tasks run, then flush repeatedly as foregrounding would
        for _ in 0..<5 {
            await Task.yield()
            await queue.flush()
        }

        XCTAssertEqual(recorder.calls.count, 3, "One play-count report per player, sent once")
        XCTAssertEqual(Set(recorder.calls.map(\.fileId)), ["file-0", "file-1", "file-2"])
        XCTAssertTrue(queue.pendingReports.isEmpty)
    }

    func testLegacyReportsAreMigrated() async throws {
        struct Legacy: Encodable { let incrementPlayCount: Bool; let addViewTime: Int }
        let data = try JSONEncoder().encode(["a": Legacy(incrementPlayCount: true, addViewTime: 12)])
        defaults.set(data, forKey: "GridStreamDeferredPlaybackStatsReports")

        let queue = PlaybackStatsQueue(defaults: defaults)

        XCTAssertEqual(queue.pendingReports.count, 1)
        XCTAssertEqual(queue.pendingReports.first?.addViewTime, 12)
        XCTAssertNil(defaults.data(forKey: "GridStreamDeferredPlaybackStatsReports"))
    }
}

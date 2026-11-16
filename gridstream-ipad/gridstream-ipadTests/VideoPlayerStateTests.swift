//
//  VideoPlayerStateTests.swift
//  gridstream-ipadTests
//

import AVFoundation
import XCTest
@testable import gridstream_ipad

@MainActor
final class VideoPlayerStateTests: XCTestCase {

    func testInitialStateIsNotPlayingAndNotBuffering() async {
        let state = VideoPlayerState()

        XCTAssertFalse(state.isPlaying)
        XCTAssertFalse(state.wantsToPlay)
        XCTAssertFalse(state.isBuffering)
        XCTAssertNil(state.playbackStatus)
        XCTAssertEqual(state.currentTime, 0)
        XCTAssertEqual(state.duration, 0)
        XCTAssertNil(state.error)
    }

    func testPlaySetsIsPlayingToTrue() async {
        let state = VideoPlayerState()
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!

        state.setupPlayer(url: testURL)
        state.play()

        XCTAssertTrue(state.isPlaying)
        XCTAssertTrue(state.wantsToPlay)
    }

    func testPauseSetsIsPlayingToFalse() async {
        let state = VideoPlayerState()
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!

        state.setupPlayer(url: testURL)
        state.play()
        state.pause()

        XCTAssertFalse(state.isPlaying)
        XCTAssertFalse(state.wantsToPlay)
    }

    func testProgressCalculatedCorrectly() async {
        let state = VideoPlayerState()

        // Progress should be 0 when duration is 0
        XCTAssertEqual(state.progress, 0)
    }

    func testRetryWithoutURLDoesNotCrash() async {
        let state = VideoPlayerState()

        // Should not crash when retrying without a URL set
        state.retry()

        XCTAssertNil(state.error)
    }

    func testSetupPlayerClearsError() async {
        let state = VideoPlayerState()
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!

        // Setup player should clear any previous error state
        state.setupPlayer(url: testURL)

        XCTAssertNil(state.error)
        XCTAssertNotNil(state.player)
    }

    func testMutedPlaybackStillReportsPlayCount() async {
        let state = VideoPlayerState()
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!
        let reported = expectation(description: "playback stats reported")

        state.configurePlaybackStatsReporter { fileId, incrementPlayCount, addViewTime in
            XCTAssertEqual(fileId, "test-file")
            XCTAssertTrue(incrementPlayCount)
            XCTAssertEqual(addViewTime, 60)
            reported.fulfill()
        }

        state.setupPlayer(url: testURL, fileId: "test-file", autoplay: false)
        state.setMuted(true)

        XCTAssertTrue(state.isMuted)
        XCTAssertFalse(state.recordPlaybackStatsProgressForTesting(currentTime: 0, isPlaybackActive: true))

        for second in 1...59 {
            XCTAssertFalse(state.recordPlaybackStatsProgressForTesting(currentTime: Double(second), isPlaybackActive: true))
        }

        XCTAssertTrue(state.recordPlaybackStatsProgressForTesting(currentTime: 60, isPlaybackActive: true))

        await fulfillment(of: [reported], timeout: 1.0)
    }

    func testPausedMutedPlaybackDoesNotReportPlayCount() async {
        let state = VideoPlayerState()
        let testURL = URL(string: "http://localhost:8080/api/v1/videos/test/stream")!

        state.configurePlaybackStatsReporter { _, _, _ in
            XCTFail("Paused playback should not report stats")
        }

        state.setupPlayer(url: testURL, fileId: "test-file", autoplay: false)
        state.setMuted(true)

        for second in 0...60 {
            XCTAssertFalse(state.recordPlaybackStatsProgressForTesting(currentTime: Double(second), isPlaybackActive: false))
        }
    }

    func testBufferRecoveryRequiresActivePlaybackIntentAndAvailableData() async {
        XCTAssertTrue(VideoPlayerState.shouldResumeAfterBufferRecovery(
            wantsToPlay: true,
            isAppInactive: false,
            isSeeking: false,
            isAtEnd: false,
            isBufferEmpty: false
        ))

        XCTAssertFalse(VideoPlayerState.shouldResumeAfterBufferRecovery(
            wantsToPlay: false,
            isAppInactive: false,
            isSeeking: false,
            isAtEnd: false,
            isBufferEmpty: false
        ))
        XCTAssertFalse(VideoPlayerState.shouldResumeAfterBufferRecovery(
            wantsToPlay: true,
            isAppInactive: true,
            isSeeking: false,
            isAtEnd: false,
            isBufferEmpty: false
        ))
        XCTAssertFalse(VideoPlayerState.shouldResumeAfterBufferRecovery(
            wantsToPlay: true,
            isAppInactive: false,
            isSeeking: true,
            isAtEnd: false,
            isBufferEmpty: false
        ))
        XCTAssertFalse(VideoPlayerState.shouldResumeAfterBufferRecovery(
            wantsToPlay: true,
            isAppInactive: false,
            isSeeking: false,
            isAtEnd: true,
            isBufferEmpty: false
        ))
        XCTAssertFalse(VideoPlayerState.shouldResumeAfterBufferRecovery(
            wantsToPlay: true,
            isAppInactive: false,
            isSeeking: false,
            isAtEnd: false,
            isBufferEmpty: true
        ))
    }

    func testActivePlaybackSeekDoesNotTargetExactEnd() async {
        let target = VideoPlayerState.resolvedSeekTarget(
            requestedTime: 120,
            duration: 120,
            frameRate: 24,
            wantsToPlay: true
        )

        XCTAssertEqual(target, 120 - (1.0 / 24.0), accuracy: 0.000_001)
    }

    func testPausedSeekCanTargetExactEndAndClampsToValidRange() async {
        XCTAssertEqual(VideoPlayerState.resolvedSeekTarget(
            requestedTime: 150,
            duration: 120,
            frameRate: 24,
            wantsToPlay: false
        ), 120)
        XCTAssertEqual(VideoPlayerState.resolvedSeekTarget(
            requestedTime: -10,
            duration: 120,
            frameRate: 24,
            wantsToPlay: false
        ), 0)
    }

    // MARK: - Audio session interruptions and route changes

    private func playingState() -> VideoPlayerState {
        let state = VideoPlayerState()
        state.setupPlayer(url: URL(string: "http://localhost:8080/api/v1/videos/test/stream")!)
        state.play()
        return state
    }

    func testInterruptionHoldsPlaybackButKeepsTheIntent() async {
        let state = playingState()

        state.handleAudioInterruption(.began, shouldResume: false)

        XCTAssertTrue(state.isAudioInterrupted)
        XCTAssertFalse(state.isPlaying)
        XCTAssertTrue(state.wantsToPlay)
    }

    func testInterruptionEndWithShouldResumeRestartsPlayback() async {
        let state = playingState()
        state.handleAudioInterruption(.began, shouldResume: false)

        state.handleAudioInterruption(.ended, shouldResume: true)

        XCTAssertFalse(state.isAudioInterrupted)
        XCTAssertTrue(state.isPlaying)
        XCTAssertTrue(state.wantsToPlay)
    }

    func testInterruptionEndWithoutShouldResumeLeavesTilePaused() async {
        let state = playingState()
        state.handleAudioInterruption(.began, shouldResume: false)

        state.handleAudioInterruption(.ended, shouldResume: false)

        XCTAssertFalse(state.isPlaying)
        XCTAssertFalse(state.wantsToPlay, "Paused, not stuck waiting to play")
    }

    func testPlayRequestDuringInterruptionWaitsForItsEnd() async {
        var interrupted = true
        let state = VideoPlayerState(activateAudioSession: {
            if interrupted { throw URLError(.cannotConnectToHost) }
        })
        state.setupPlayer(url: URL(string: "http://localhost:8080/api/v1/videos/test/stream")!)
        state.handleAudioInterruption(.began, shouldResume: false)

        state.play()
        XCTAssertFalse(state.isPlaying)

        interrupted = false
        state.handleAudioInterruption(.ended, shouldResume: true)
        XCTAssertTrue(state.isPlaying)
    }

    func testSuspendedAudioSessionRecoversWithoutAnEndNotification() {
        let state = VideoPlayerState(activateAudioSession: {})
        state.setupPlayer(url: URL(string: "http://demo.gridstream.invalid/api/v1/videos/test/stream")!)
        state.play()
        state.handleAppWillResignActive()
        state.handleAudioInterruption(.began, shouldResume: false)
        state.handleAppDidBecomeActive()
        XCTAssertFalse(state.isAudioInterrupted)
        XCTAssertTrue(state.wantsToPlay)
        XCTAssertNotEqual(state.playbackStatus, .interrupted)
    }

    func testForegroundDoesNotResumeAnOngoingCall() {
        var activationFails = false
        let state = VideoPlayerState(activateAudioSession: {
            if activationFails { throw URLError(.cannotConnectToHost) }
        })
        state.setupPlayer(url: URL(string: "http://localhost/api/v1/videos/test/stream")!)
        state.play()
        state.handleAppWillResignActive()
        state.handleAudioInterruption(.began, shouldResume: false)
        activationFails = true
        state.handleAppDidBecomeActive()
        XCTAssertTrue(state.isAudioInterrupted)
        XCTAssertFalse(state.isPlaying)
    }

    func testExplicitPlayRetriesAnInterruptionWhoseEndWasLost() {
        var activationFails = false
        let state = VideoPlayerState(activateAudioSession: {
            if activationFails { throw URLError(.cannotConnectToHost) }
        })
        state.setupPlayer(url: URL(string: "http://localhost/api/v1/videos/test/stream")!)
        state.handleAudioInterruption(.began, shouldResume: false)
        activationFails = true
        state.play()
        XCTAssertTrue(state.isAudioInterrupted)
        XCTAssertFalse(state.isPlaying)
        activationFails = false
        state.play()
        XCTAssertFalse(state.isAudioInterrupted)
        XCTAssertTrue(state.isPlaying)
    }

    func testHeadphonesUnpluggedPausesAndClearsIntent() async {
        let state = playingState()

        state.handleAudioRouteChange(.oldDeviceUnavailable)

        XCTAssertFalse(state.isPlaying)
        XCTAssertFalse(state.wantsToPlay)
    }

    func testNewRouteDoesNotPause() async {
        let state = playingState()

        state.handleAudioRouteChange(.newDeviceAvailable)

        XCTAssertTrue(state.isPlaying)
    }

    // MARK: - Deferred seek readiness

    func testWaitForReadinessGivesUpWhenThePlayerLoadsAnotherVideo() async {
        let state = VideoPlayerState()
        state.setupPlayer(url: URL(string: "http://localhost:8080/api/v1/videos/a/stream")!)
        let wait = Task { await state.waitUntilReadyToPlay(timeout: 2) }
        for _ in 0..<3 { await Task.yield() }  // let the wait pick up the first item

        state.setupPlayer(url: URL(string: "http://localhost:8080/api/v1/videos/b/stream")!)

        let stillApplies = await wait.value
        XCTAssertFalse(stillApplies, "A seek meant for the old video must be dropped")
    }

    func testWaitForReadinessGivesUpWhenCancelled() async {
        let state = VideoPlayerState()
        state.setupPlayer(url: URL(string: "http://localhost:8080/api/v1/videos/a/stream")!)
        let wait = Task { await state.waitUntilReadyToPlay(timeout: 2) }
        await Task.yield()

        wait.cancel()

        let stillApplies = await wait.value
        XCTAssertFalse(stillApplies)
    }
}

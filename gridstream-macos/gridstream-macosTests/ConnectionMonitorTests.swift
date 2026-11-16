//
//  ConnectionMonitorTests.swift
//  gridstream-macosTests
//
//  Devices, streams, rates and log entries of the connection monitor, on an
//  injected clock.
//

import XCTest
@testable import gridstream_macos

final class ConnectionMonitorTests: XCTestCase {

    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private let iPadAgent = "gridstream-ipad/1 CFNetwork/1568 Darwin/24.0.0"
    private let avPlayerAgent = "AppleCoreMedia/1.0.0.22A3354 (iPad; U; CPU OS 18_0 like Mac OS X; fr_fr)"
    private let safariAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    // MARK: - Client kinds

    func testUserAgentsAreRecognised() {
        XCTAssertEqual(ClientKind.guess(fromUserAgent: iPadAgent).kind, .iPad)
        XCTAssertEqual(ClientKind.guess(fromUserAgent: safariAgent).kind, .browser("Safari"))
        XCTAssertEqual(
            ClientKind.guess(fromUserAgent: "Mozilla/5.0 (Macintosh) AppleWebKit/537.36 Chrome/130.0 Safari/537.36 Edg/130.0").kind,
            .browser("Edge")
        )
        XCTAssertEqual(ClientKind.guess(fromUserAgent: "curl/8.7.1").kind, .unknown)
        XCTAssertEqual(ClientKind.guess(fromUserAgent: nil).kind, .unknown)
    }

    func testAVPlayerGuessGivesWayToAClearerAgent() {
        let monitor = ConnectionMonitor()
        monitor.recordRequest(from: "10.0.0.2", userAgent: avPlayerAgent, at: at(0))
        monitor.recordRequest(from: "10.0.0.2", userAgent: safariAgent, at: at(1))
        monitor.recordRequest(from: "10.0.0.2", userAgent: avPlayerAgent, at: at(2))

        XCTAssertEqual(monitor.sample(at: at(3)).clients.first?.identity.kind, .browser("Safari"))
    }

    func testIPv4MappedAddressesAreShownPlain() {
        let monitor = ConnectionMonitor()
        monitor.recordRequest(from: "::ffff:192.168.1.20", userAgent: iPadAgent, at: at(0))

        XCTAssertEqual(monitor.sample(at: at(1)).clients.map(\.identity.address), ["192.168.1.20"])
    }

    // MARK: - Devices

    func testFirstRequestConnectsTheDeviceOnce() {
        let monitor = ConnectionMonitor()
        monitor.recordRequest(from: "10.0.0.2", userAgent: iPadAgent, bytesSent: 100, at: at(0))
        monitor.recordRequest(from: "10.0.0.2", userAgent: iPadAgent, bytesSent: 50, at: at(1))

        let sample = monitor.sample(at: at(2))
        XCTAssertEqual(sample.events.map(\.kind), [.connected])
        XCTAssertEqual(sample.clients.count, 1)
        XCTAssertEqual(sample.clients.first?.bytesSent, 150)
        XCTAssertEqual(sample.bytesSent, 150)
    }

    func testQuietDeviceGoesIdleAfterTheTimeout() {
        let monitor = ConnectionMonitor(idleTimeout: 60)
        monitor.recordRequest(from: "10.0.0.2", userAgent: iPadAgent, bytesSent: 10, at: at(0))
        _ = monitor.sample(at: at(1))

        XCTAssertEqual(monitor.sample(at: at(59)).clients.count, 1)

        let sample = monitor.sample(at: at(60))
        XCTAssertTrue(sample.clients.isEmpty)
        XCTAssertEqual(sample.events.map(\.kind), [.wentIdle(bytesSent: 10)])
    }

    // MARK: - Streams

    func testStreamIsLoggedFromFirstBodyToLingerAfterTheLast() {
        let monitor = ConnectionMonitor(streamLinger: 5)
        let first = monitor.openStream(from: "10.0.0.2", userAgent: avPlayerAgent, fileId: "a", filename: "a.mp4", at: at(0))
        first.add(1_000)
        first.close()
        // AVPlayer's next range request continues the same stream
        let second = monitor.openStream(from: "10.0.0.2", userAgent: avPlayerAgent, fileId: "a", filename: "a.mp4", at: at(2))
        second.add(500)

        var sample = monitor.sample(at: at(3))
        XCTAssertEqual(sample.events.map(\.kind), [.connected, .streamStarted(filename: "a.mp4")])
        XCTAssertEqual(sample.videosServed, 1)
        XCTAssertEqual(sample.clients.first?.streams.map(\.bytesSent), [1_500])

        second.close()
        // Still open bodies or within the linger: the stream goes on
        XCTAssertEqual(monitor.sample(at: at(4)).clients.first?.streams.count, 1)

        sample = monitor.sample(at: .distantFuture)
        XCTAssertTrue(sample.clients.isEmpty, "Ended stream and quiet device are both gone")
        guard case .streamEnded(let filename, let bytesSent, _)? = sample.events.first?.kind else {
            return XCTFail("Expected the stream to end first, got \(sample.events)")
        }
        XCTAssertEqual(filename, "a.mp4")
        XCTAssertEqual(bytesSent, 1_500)
    }

    func testOpenStreamKeepsTheDeviceConnected() {
        let monitor = ConnectionMonitor(idleTimeout: 10, streamLinger: 5)
        let meter = monitor.openStream(from: "10.0.0.2", userAgent: avPlayerAgent, fileId: "a", filename: "a.mp4", at: at(0))

        // A paused player keeps its body open without reading
        let sample = monitor.sample(at: at(600))
        XCTAssertEqual(sample.clients.first?.streams.count, 1)
        meter.close()
    }

    func testRatesFollowTheBytesSent() {
        let monitor = ConnectionMonitor()
        let meter = monitor.openStream(from: "10.0.0.2", userAgent: avPlayerAgent, fileId: "a", filename: "a.mp4", at: at(0))
        _ = monitor.sample(at: at(0))

        meter.add(2_000)
        let sample = monitor.sample(at: at(1))

        // Smoothed: half of the new rate on the first interval
        XCTAssertEqual(sample.clients.first?.bytesPerSecond ?? 0, 1_000, accuracy: 0.001)
        XCTAssertEqual(sample.clients.first?.streams.first?.bytesPerSecond ?? 0, 1_000, accuracy: 0.001)
        meter.close()
    }

    // MARK: - Sign-in

    func testSignInOutcomesAreLogged() {
        let monitor = ConnectionMonitor()
        monitor.recordSignIn(from: "10.0.0.3", userAgent: safariAgent, outcome: .wrongPIN, at: at(0))
        monitor.recordSignIn(from: "10.0.0.3", userAgent: safariAgent, outcome: .blocked, at: at(1))

        var sample = monitor.sample(at: at(2))
        XCTAssertEqual(sample.events.map(\.kind), [.wrongPIN, .signInBlocked])
        XCTAssertTrue(sample.clients.isEmpty, "A failed sign-in does not connect the device")
        XCTAssertEqual(sample.events.first?.client, ClientIdentity(address: "10.0.0.3", kind: .browser("Safari")))

        monitor.recordSignIn(from: "10.0.0.3", userAgent: safariAgent, outcome: .succeeded, at: at(3))
        sample = monitor.sample(at: at(4))
        XCTAssertEqual(sample.events.map(\.kind), [.connected, .signedIn])
        XCTAssertEqual(sample.clients.count, 1)
    }

    func testResetForgetsEverything() {
        let monitor = ConnectionMonitor()
        let meter = monitor.openStream(from: "10.0.0.2", userAgent: avPlayerAgent, fileId: "a", filename: "a.mp4", at: at(0))
        monitor.reset()
        // A body still being written when the server stopped
        meter.add(100)
        meter.close()

        let sample = monitor.sample(at: at(1))
        XCTAssertTrue(sample.clients.isEmpty)
        XCTAssertTrue(sample.events.isEmpty)
        XCTAssertEqual(sample.videosServed, 0)
        XCTAssertEqual(sample.bytesSent, 0)
    }
}

@MainActor
final class ConnectionActivityTests: XCTestCase {

    func testActivityKeepsTheNewestEventsFirst() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let activity = ConnectionActivity(monitor: ConnectionMonitor())
        activity.monitor.recordRequest(from: "10.0.0.2", userAgent: nil, at: start)
        activity.monitor.recordSignOut(from: "10.0.0.2", userAgent: nil, at: start.addingTimeInterval(1))
        activity.update(at: start.addingTimeInterval(2))

        XCTAssertEqual(activity.events.map(\.kind), [.signedOut, .connected])
        XCTAssertEqual(activity.clients.count, 1)

        activity.clearLog()
        XCTAssertTrue(activity.events.isEmpty)
    }
}

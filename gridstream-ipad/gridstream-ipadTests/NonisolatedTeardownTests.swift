//
//  NonisolatedTeardownTests.swift
//  gridstream-ipadTests
//

import UIKit
import XCTest
@testable import gridstream_ipad

/// These types tear down in a nonisolated deinit (an isolated one aborts when
/// the object is released outside a Swift task). Released here from a plain,
/// synchronous test, which is that case.
@MainActor
final class NonisolatedTeardownTests: XCTestCase {

    func testObjectsCanBeReleasedOutsideASwiftTask() {
        weak var releasedPlayer: VideoPlayerState?
        weak var releasedGenerator: ScrubPreviewGenerator?
        weak var releasedDiscovery: ServerDiscoveryService?
        autoreleasepool {
            let player = VideoPlayerState()
            player.setupPlayer(url: URL(fileURLWithPath: "/nonexistent/clip.mp4"), autoplay: false)
            let generator = ScrubPreviewGenerator()
            let discovery = ServerDiscoveryService()
            releasedPlayer = player
            releasedGenerator = generator
            releasedDiscovery = discovery
        }
        XCTAssertNil(releasedPlayer)
        XCTAssertNil(releasedGenerator)
        XCTAssertNil(releasedDiscovery)
    }

    func testReleasedDismissGestureCoordinatorRemovesItsRecognizer() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let initialCount = window.gestureRecognizers?.count ?? 0
        autoreleasepool {
            let coordinator = PiPDismissGestureView.Coordinator(onGestureChanged: { _, _, _ in }, onGestureEnded: { _, _, _ in })
            coordinator.installOnWindow(window)
            XCTAssertEqual(window.gestureRecognizers?.count ?? 0, initialCount + 1)
        }
        XCTAssertEqual(window.gestureRecognizers?.count ?? 0, initialCount)
    }
}

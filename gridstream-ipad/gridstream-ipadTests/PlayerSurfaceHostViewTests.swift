//
//  PlayerSurfaceHostViewTests.swift
//  gridstream-ipadTests
//

import AVFoundation
import UIKit
import XCTest
@testable import gridstream_ipad

/// A player's picture is one view, passed between the views that show the
/// player. Each of them attaching its own layer left the new layer black
/// until the player had drawn into it: black frames on every swap.
@MainActor
final class PlayerSurfaceHostViewTests: XCTestCase {

    private var window: UIWindow!

    override func setUp() async throws {
        try await super.setUp()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
    }

    override func tearDown() async throws {
        window = nil
        try await super.tearDown()
    }

    func testAPlayerKeepsOnePictureFollowingItsAVPlayer() {
        let player = VideoPlayerState()
        let surface = player.surface
        XCTAssertNil(surface.playerLayer.player)

        player.setupPlayer(url: URL(fileURLWithPath: "/dev/null"), autoplay: false)
        XCTAssertTrue(player.surface === surface)
        XCTAssertNotNil(player.player)
        XCTAssertTrue(surface.playerLayer.player === player.player)

        player.releasePlayerResources()
        XCTAssertNil(surface.playerLayer.player)
    }

    func testAPictureMadeAfterThePlayerShowsIt() {
        let player = VideoPlayerState()
        player.setupPlayer(url: URL(fileURLWithPath: "/dev/null"), autoplay: false)
        XCTAssertTrue(player.surface.playerLayer.player === player.player)
        player.releasePlayerResources()
    }

    func testAViewThatStartsShowingAPlayerTakesItsPicture() {
        let surface = PlayerLayerView()
        let fullscreen = host(width: 800, height: 450)
        let pip = host(width: 240, height: 135)

        pip.show(surface)
        XCTAssertTrue(surface.superview === pip)
        XCTAssertEqual(surface.bounds.size, CGSize(width: 240, height: 135))

        // The swap: the fullscreen view takes the picture the PiP showed.
        fullscreen.show(surface)
        XCTAssertTrue(surface.superview === fullscreen)
        XCTAssertEqual(surface.bounds.size, CGSize(width: 800, height: 450))
        XCTAssertEqual(surface.center, CGPoint(x: 400, y: 225))
    }

    func testAViewOnItsWayOutLeavesThePictureWhereItWent() {
        let surface = PlayerLayerView()
        let fullscreen = host(width: 800, height: 450)
        let pip = host(width: 240, height: 135)
        pip.show(surface)
        fullscreen.show(surface)

        // Updated again during its removal transition.
        pip.show(surface)
        XCTAssertTrue(surface.superview === fullscreen)

        // And removed.
        pip.releaseSurface()
        XCTAssertTrue(surface.superview === fullscreen)
    }

    func testAViewShowingAnotherPlayerDropsThePictureItStillHolds() {
        let first = PlayerLayerView()
        let second = PlayerLayerView()
        let fullscreen = host(width: 800, height: 450)
        let pip = host(width: 240, height: 135)
        fullscreen.show(first)
        pip.show(second)

        // The swap, fullscreen view first: it drops the picture it held.
        fullscreen.show(second)
        XCTAssertNil(first.superview)
        XCTAssertEqual(fullscreen.subviews, [second])

        // The swap, new PiP first: the fullscreen view must not pull the
        // picture the new PiP already took.
        let newPiP = host(width: 240, height: 135)
        newPiP.show(second)
        fullscreen.show(first)
        XCTAssertTrue(second.superview === newPiP)
        XCTAssertEqual(fullscreen.subviews, [first])
    }

    func testAViewTakesBackAPictureNoViewHolds() {
        let surface = PlayerLayerView()
        let tile = host(width: 400, height: 225, onScreen: false)
        let other = host(width: 240, height: 135, onScreen: false)
        tile.show(surface)
        other.show(surface)
        other.releaseSurface()
        XCTAssertNil(surface.superview)

        tile.show(surface)
        XCTAssertTrue(surface.superview === tile)
    }

    /// Entering fullscreen and leaving it before the transition ended left
    /// every video black: SwiftUI put the grid views back as they were,
    /// without an update, and the pictures stayed in the fullscreen views.
    func testAViewStillOnScreenGetsThePictureBackWhenItsHolderLeaves() async {
        let surface = PlayerLayerView()
        let tile = host(width: 400, height: 225)
        let fullscreen = host(width: 800, height: 450)
        tile.show(surface, framing: PlayerFraming(mode: .fit))
        fullscreen.show(surface, framing: PlayerFraming(mode: .fill))
        XCTAssertEqual(surface.playerLayer.videoGravity, .resizeAspectFill)

        // The fullscreen view leaves the screen without being torn down.
        fullscreen.removeFromSuperview()
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(tile.subviews, [surface])
        XCTAssertEqual(surface.bounds.size, CGSize(width: 400, height: 225))
        XCTAssertEqual(surface.playerLayer.videoGravity, .resizeAspect)
    }

    func testAViewStillOnScreenGetsThePictureBackWhenItsHolderIsTornDown() {
        let surface = PlayerLayerView()
        let tile = host(width: 400, height: 225)
        let fullscreen = host(width: 800, height: 450)
        tile.show(surface)
        fullscreen.show(surface)

        fullscreen.releaseSurface()

        XCTAssertEqual(tile.subviews, [surface])
        XCTAssertEqual(surface.bounds.size, CGSize(width: 400, height: 225))
    }

    /// Leaving fullscreen and entering it again at once: the fullscreen
    /// view comes back on screen as it was, the grid view goes.
    func testAViewPutBackOnScreenTakesAPictureLeftOffScreen() async {
        let surface = PlayerLayerView()
        let fullscreen = host(width: 800, height: 450)
        let tile = host(width: 400, height: 225)
        fullscreen.show(surface)
        fullscreen.removeFromSuperview()
        tile.show(surface)
        XCTAssertTrue(surface.superview === tile)

        tile.removeFromSuperview()
        window.addSubview(fullscreen)
        XCTAssertEqual(fullscreen.subviews, [surface])

        // The view that left has nothing to take back.
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(fullscreen.subviews, [surface])
        XCTAssertTrue(tile.subviews.isEmpty)
    }

    func testAViewThatIsNotOnScreenLeavesThePictureWithTheOneThatIs() {
        let surface = PlayerLayerView()
        let cached = host(width: 400, height: 225, onScreen: false)
        let fullscreen = host(width: 800, height: 450)
        cached.show(surface)
        fullscreen.show(surface)

        cached.show(surface)
        XCTAssertTrue(surface.superview === fullscreen)
    }

    func testThePictureIsFramedForTheViewThatHoldsIt() {
        let surface = PlayerLayerView()
        let tile = host(width: 400, height: 225)
        let pip = host(width: 240, height: 135)
        tile.show(surface, framing: PlayerFraming(mode: .custom, scale: 2, offset: CGPoint(x: 10, y: 20)))
        XCTAssertEqual(surface.playerLayer.videoGravity, .resizeAspect)
        XCTAssertEqual(surface.playerLayer.affineTransform().a, 2, accuracy: 0.001)

        pip.show(surface, framing: PlayerFraming(mode: .fill))
        XCTAssertEqual(surface.playerLayer.videoGravity, .resizeAspectFill)
        XCTAssertTrue(surface.playerLayer.affineTransform().isIdentity)

        // The view that lost the picture does not frame it any more.
        tile.show(surface, framing: PlayerFraming(mode: .fit))
        XCTAssertEqual(surface.playerLayer.videoGravity, .resizeAspectFill)
    }

    func testThePictureFollowsTheViewsSize() {
        let surface = PlayerLayerView()
        let tile = host(width: 400, height: 225)
        tile.show(surface)

        tile.bounds = CGRect(x: 0, y: 0, width: 600, height: 300)
        tile.layoutIfNeeded()
        XCTAssertEqual(surface.bounds.size, CGSize(width: 600, height: 300))
        XCTAssertEqual(surface.center, CGPoint(x: 300, y: 150))
    }

    /// Setting the picture's frame under the zoom transform of a custom
    /// framing shrank it on every layout pass, without end.
    func testAZoomedCustomFramingKeepsThePictureAtTheViewsSize() {
        let surface = PlayerLayerView()
        let tile = host(width: 400, height: 225)
        tile.show(surface, framing: PlayerFraming(mode: .custom, scale: 1.5, offset: CGPoint(x: 50, y: 30)))

        tile.bounds = CGRect(x: 0, y: 0, width: 600, height: 300)
        tile.layoutIfNeeded()
        tile.setNeedsLayout()
        tile.layoutIfNeeded()

        XCTAssertEqual(surface.bounds.size, CGSize(width: 600, height: 300))
        XCTAssertEqual(surface.center, CGPoint(x: 300, y: 150))
        let transform = surface.playerLayer.affineTransform()
        XCTAssertEqual(transform.a, 1.5, accuracy: 0.001)
        XCTAssertEqual(transform.tx, 50, accuracy: 0.001)
        XCTAssertEqual(transform.ty, 30, accuracy: 0.001)
    }

    private func host(width: CGFloat, height: CGFloat, onScreen: Bool = true) -> PlayerSurfaceHostView {
        let host = PlayerSurfaceHostView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        if onScreen { window.addSubview(host) }
        return host
    }
}

//
//  ServerMenuTests.swift
//  gridstream-ipadTests
//

import SwiftUI
import UIKit
import XCTest
@testable import gridstream_ipad

/// The top bar hides itself after a few seconds. While the server menu is
/// open it must stay: hidden, it left the menu floating over nothing.
@MainActor
final class ServerMenuTests: XCTestCase {

    private var window: UIWindow!
    private var overlay: OverlayState!
    /// SwiftUI lets go of the environment after the test, outside any Swift
    /// task, where releasing these objects aborts the test host: keep them.
    private static var environment: [AnyObject] = []

    override func setUp() async throws {
        try await super.setUp()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        overlay = OverlayState()
    }

    override func tearDown() async throws {
        window.isHidden = true
        window.rootViewController = nil
        window = nil
        overlay = nil
        try await super.tearDown()
    }

    func testTheBarStaysWhileTheMenuIsOpen() async throws {
        let button = try await showMenuButton()
        overlay.show()

        button.onMenuOpen?()
        try await settle()
        XCTAssertTrue(overlay.isSuspended)
        XCTAssertTrue(overlay.isVisible)

        button.onMenuClose?()
        try await settle()
        XCTAssertFalse(overlay.isSuspended)
    }

    func testOpeningTheMenuBringsTheBarBack() async throws {
        let button = try await showMenuButton()
        XCTAssertFalse(overlay.isVisible)

        button.onMenuOpen?()
        try await settle()
        XCTAssertTrue(overlay.isVisible)
    }

    /// The server menu wired to the overlay as the top bar wires it.
    private func showMenuButton() async throws -> MenuCircleButton.MenuButton {
        let overlay = overlay!
        let demo = DemoController(defaults: try XCTUnwrap(UserDefaults(suiteName: "ServerMenuTests")))
        let discovery = ServerDiscoveryService()
        let grid = GridState()
        Self.environment += [demo, discovery, grid]

        let menu = ServerMenu(
            status: .searching,
            onMenuOpen: {
                overlay.show()
                overlay.suspendAutoHide()
            },
            onMenuClose: { overlay.resumeAutoHide() }
        )
        .environment(demo)
        .environment(discovery)
        .environment(grid)

        window.rootViewController = UIHostingController(rootView: menu)
        window.isHidden = false
        try await settle()
        return try XCTUnwrap(menuButton(in: window))
    }

    private func menuButton(in view: UIView) -> MenuCircleButton.MenuButton? {
        if let button = view as? MenuCircleButton.MenuButton { return button }
        return view.subviews.lazy.compactMap { self.menuButton(in: $0) }.first
    }

    /// Lets SwiftUI apply a change. The window has no scene, so nothing
    /// draws it: lay it out by hand.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(50))
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
    }
}

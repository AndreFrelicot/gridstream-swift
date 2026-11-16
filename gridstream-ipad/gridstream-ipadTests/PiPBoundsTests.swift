//
//  PiPBoundsTests.swift
//  gridstream-ipadTests
//

import CoreGraphics
import XCTest
@testable import gridstream_ipad

@MainActor
final class PiPBoundsTests: XCTestCase {
    private let screen = CGSize(width: 1180, height: 820)
    private let width: CGFloat = 236
    private var height: CGFloat { width / (16.0 / 9.0) }

    func testAnUnrotatedPiPKeepsTwentyPercentOnScreen() {
        let pastLeftAndTop = PiPBounds.clamp(CGPoint(x: -1000, y: -1000), width: width, height: height, rotation: 0, screen: screen)
        XCTAssertEqual(pastLeftAndTop.x, -width * 0.8, accuracy: 0.001)
        XCTAssertEqual(pastLeftAndTop.y, -height * 0.8, accuracy: 0.001)

        let pastRightAndBottom = PiPBounds.clamp(CGPoint(x: 5000, y: 5000), width: width, height: height, rotation: 0, screen: screen)
        XCTAssertEqual(pastRightAndBottom.x, screen.width - width * 0.2, accuracy: 0.001)
        XCTAssertEqual(pastRightAndBottom.y, screen.height - height * 0.2, accuracy: 0.001)

        let inside = CGPoint(x: 300, y: 200)
        XCTAssertEqual(PiPBounds.clamp(inside, width: width, height: height, rotation: 0, screen: screen), inside)
    }

    func testAQuarterTurnedPiPStaysVisibleAtASideEdge() {
        // The old rule allowed its frame 80% off the left edge: turned a
        // quarter, the picture was then entirely off screen.
        let position = PiPBounds.clamp(CGPoint(x: -width * 0.8, y: 300), width: width, height: height, rotation: .pi / 2, screen: screen)
        XCTAssertTrue(isVisible(position, rotation: .pi / 2))
    }

    func testAPiPStaysVisibleAtEveryEdgeAndCornerWhateverItsRotation() {
        let farAway: [CGPoint] = [
            CGPoint(x: -5000, y: -5000), CGPoint(x: 5000, y: -5000), CGPoint(x: 5000, y: 5000), CGPoint(x: -5000, y: 5000),
            CGPoint(x: -5000, y: 300), CGPoint(x: 5000, y: 300), CGPoint(x: 500, y: -5000), CGPoint(x: 500, y: 5000),
            CGPoint(x: -5000, y: 5), CGPoint(x: 5, y: -5000)
        ]
        for step in 0..<48 {
            let rotation = CGFloat(step) * .pi / 24
            for point in farAway {
                let position = PiPBounds.clamp(point, width: width, height: height, rotation: rotation, screen: screen)
                XCTAssertTrue(isVisible(position, rotation: rotation), "Lost at \(point), rotation \(rotation)")
            }
        }
    }

    func testANonFinitePositionOrRotationIsBroughtBack() {
        let position = PiPBounds.clamp(CGPoint(x: CGFloat.nan, y: 100), width: width, height: height, rotation: 0, screen: screen)
        XCTAssertTrue(isVisible(position, rotation: 0))

        let turned = PiPBounds.clamp(CGPoint(x: -5000, y: 100), width: width, height: height, rotation: .infinity, screen: screen)
        XCTAssertTrue(isVisible(turned, rotation: 0))
    }

    /// Whether part of the tile, turned clockwise about its center as SwiftUI
    /// draws it, lies at least 5 points inside the screen.
    private func isVisible(_ position: CGPoint, rotation: CGFloat) -> Bool {
        let center = CGPoint(x: position.x + width / 2, y: position.y + height / 2)
        let inner = CGRect(origin: .zero, size: screen).insetBy(dx: 5, dy: 5)
        for i in 0...20 {
            for j in 0...20 {
                let x = (CGFloat(i) / 20 - 0.5) * width
                let y = (CGFloat(j) / 20 - 0.5) * height
                let point = CGPoint(
                    x: center.x + x * cos(rotation) - y * sin(rotation),
                    y: center.y + x * sin(rotation) + y * cos(rotation)
                )
                if inner.contains(point) { return true }
            }
        }
        return false
    }
}

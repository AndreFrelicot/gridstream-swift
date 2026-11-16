//
//  VideoFramingTests.swift
//  gridstream-ipadTests
//

import XCTest
import AVFoundation
@testable import gridstream_ipad

@MainActor
final class VideoFramingTests: XCTestCase {

    func testFillModeUsesResizeAspectFillGravity() async {
        // Given a PlayerLayerView
        let playerLayerView = PlayerLayerView()

        // When configured with fill mode
        playerLayerView.playerLayer.videoGravity = .resizeAspectFill
        playerLayerView.resetTransform()

        // Then the video gravity should be resizeAspectFill
        XCTAssertEqual(playerLayerView.playerLayer.videoGravity, .resizeAspectFill)

        // And the transform should be identity
        XCTAssertEqual(playerLayerView.playerLayer.affineTransform(), .identity)
    }

    func testFitModeUsesResizeAspectGravity() async {
        // Given a PlayerLayerView
        let playerLayerView = PlayerLayerView()

        // When configured with fit mode
        playerLayerView.playerLayer.videoGravity = .resizeAspect
        playerLayerView.resetTransform()

        // Then the video gravity should be resizeAspect
        XCTAssertEqual(playerLayerView.playerLayer.videoGravity, .resizeAspect)

        // And the transform should be identity
        XCTAssertEqual(playerLayerView.playerLayer.affineTransform(), .identity)
    }

    func testCustomModeAppliesCGAffineTransformCorrectly() async {
        // Given a PlayerLayerView
        let playerLayerView = PlayerLayerView()

        // When applying custom transform with scale and offset
        let scale: CGFloat = 2.0
        let offset = CGPoint(x: 100, y: 50)
        playerLayerView.applyCustomTransform(scale: scale, offset: offset)

        // Then the transform should not be identity
        XCTAssertNotEqual(playerLayerView.playerLayer.affineTransform(), .identity)

        // And the transform's scale components should reflect the scale
        let transform = playerLayerView.playerLayer.affineTransform()
        XCTAssertEqual(transform.a, scale, accuracy: 0.001) // scaleX
        XCTAssertEqual(transform.d, scale, accuracy: 0.001) // scaleY
    }

    func testTransformResetsWhenModeChangesFromCustom() async {
        // Given a PlayerLayerView with custom transform applied
        let playerLayerView = PlayerLayerView()
        playerLayerView.applyCustomTransform(scale: 2.0, offset: CGPoint(x: 100, y: 50))

        // Verify transform is not identity
        XCTAssertNotEqual(playerLayerView.playerLayer.affineTransform(), .identity)

        // When resetting transform (simulating mode change from Custom)
        playerLayerView.resetTransform()

        // Then the transform should be reset to identity
        XCTAssertEqual(playerLayerView.playerLayer.affineTransform(), .identity)
    }
}

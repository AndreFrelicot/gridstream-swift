//
//  AnnotationCoordinateHelperTests.swift
//  gridstream-ipadTests
//

import CoreGraphics
import XCTest
@testable import gridstream_ipad

/// Where the video sits inside the view decides where a drawing is stored
/// on the frame. It has to be the rect the player really draws.
@MainActor
final class AnnotationCoordinateHelperTests: XCTestCase {

    private let wideVideo = CGSize(width: 1920, height: 1080)
    private let tallVideo = CGSize(width: 1080, height: 1920)
    private let squareView = CGSize(width: 400, height: 400)

    func testFitLetterboxesTheVideoInsideTheView() {
        XCTAssertEqual(
            AnnotationCoordinateHelper.computeVideoRect(videoSize: wideVideo, viewSize: squareView, framingMode: .fit),
            CGRect(x: 0, y: 87.5, width: 400, height: 225)
        )
        XCTAssertEqual(
            AnnotationCoordinateHelper.computeVideoRect(videoSize: tallVideo, viewSize: squareView, framingMode: .fit),
            CGRect(x: 87.5, y: 0, width: 225, height: 400)
        )
    }

    func testFillCropsTheVideoToTheView() {
        let rect = AnnotationCoordinateHelper.computeVideoRect(
            videoSize: wideVideo, viewSize: squareView, framingMode: .fill
        )
        XCTAssertEqual(rect.height, 400)
        XCTAssertEqual(rect.width, 400 * 16 / 9, accuracy: 0.001)
        XCTAssertEqual(rect.midX, 200, accuracy: 0.001)
    }

    /// The player draws a custom framing from the fitted picture. Mapped as
    /// a filled one, a drawing was stored away from where it was made
    /// whenever the video and the view had different shapes.
    func testCustomFramingStartsFromTheFittedPicture() {
        for video in [wideVideo, tallVideo] {
            XCTAssertEqual(
                AnnotationCoordinateHelper.computeVideoRect(videoSize: video, viewSize: squareView, framingMode: .custom),
                AnnotationCoordinateHelper.computeVideoRect(videoSize: video, viewSize: squareView, framingMode: .fit)
            )
        }
    }
}

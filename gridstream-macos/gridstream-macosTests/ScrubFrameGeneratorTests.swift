import XCTest
@testable import gridstream_macos

final class ScrubFrameGeneratorTests: XCTestCase {

    /// AVAssetImageGenerator can't open a time at/before the first frame's PTS (files with a
    /// non-zero stream start_time). The t=0 grid point must be requested slightly later.
    func testFirstGridTimeIsNudgedPastStreamStart() {
        XCTAssertGreaterThan(ScrubFrameGenerator.requestTime(forGridTime: 0.0), 0.0)
    }

    /// Non-zero grid points must be requested unchanged.
    func testNonZeroGridTimesAreUnchanged() {
        XCTAssertEqual(ScrubFrameGenerator.requestTime(forGridTime: 2.0), 2.0, accuracy: 1e-9)
        XCTAssertEqual(ScrubFrameGenerator.requestTime(forGridTime: 1272.0), 1272.0, accuracy: 1e-9)
    }

    /// The nudge must stay within frameInterval/2 so the stored frame still rounds to grid
    /// slot 0 — otherwise the cached-times diff would never see it and it would be
    /// re-requested (and re-fail) on every sweep.
    func testNudgedFirstTimeStillRoundsToGridSlotZero() async {
        let requested = ScrubFrameGenerator.requestTime(forGridTime: 0.0)
        XCTAssertLessThan(ScrubFrameGenerator.firstFrameRequestOffset, ScrubFrameGenerator.frameInterval / 2)
        let rounded = await ScrubFrameGenerator.shared.roundTime(requested)
        XCTAssertEqual(rounded, 0.0, accuracy: 1e-9)
    }
}

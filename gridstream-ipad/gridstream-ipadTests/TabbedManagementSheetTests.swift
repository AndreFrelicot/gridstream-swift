//
//  TabbedManagementSheetTests.swift
//  gridstream-ipad
//

import XCTest
@testable import gridstream_ipad

@MainActor
final class TabbedManagementSheetTests: XCTestCase {

    // MARK: - Tag CRUD Callback Integration Tests

    func testTagInfoCreation() async {
        // Verify TagInfo can be created with required properties
        let tagId = UUID()
        let tag = TagInfo(
            id: tagId,
            name: "test-tag",
            color: "#EF4444",
            ratingEnabled: false
        )

        XCTAssertEqual(tag.id, tagId)
        XCTAssertEqual(tag.name, "test-tag")
        XCTAssertEqual(tag.color, "#EF4444")
        XCTAssertFalse(tag.ratingEnabled)
    }

    func testTagInfoWithRatingEnabled() async {
        let tag = TagInfo(
            id: UUID(),
            name: "rated-tag",
            color: "#22C55E",
            ratingEnabled: true
        )

        XCTAssertTrue(tag.ratingEnabled)
    }

    func testTagInfoEquatable() async {
        let tagId = UUID()
        let tag1 = TagInfo(id: tagId, name: "tag", color: "#000000", ratingEnabled: false)
        let tag2 = TagInfo(id: tagId, name: "tag", color: "#000000", ratingEnabled: false)
        let tag3 = TagInfo(id: UUID(), name: "tag", color: "#000000", ratingEnabled: false)

        XCTAssertEqual(tag1, tag2)
        XCTAssertNotEqual(tag1, tag3)
    }
}

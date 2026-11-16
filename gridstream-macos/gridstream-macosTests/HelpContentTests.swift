//
//  HelpContentTests.swift
//  gridstream-macosTests
//
//  The Help window's topics: unique ids and one topic per settings pane.
//

import XCTest
@testable import gridstream_macos

@MainActor
final class HelpContentTests: XCTestCase {

    func testTopicIDsAreUnique() {
        let ids = HelpTopic.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEverySettingsPaneHasAHelpTopic() {
        for tab in SettingsView.SettingsTab.allCases {
            XCTAssertNotNil(HelpTopic.topic(id: tab.helpTopicID), "No help topic for \(tab)")
        }
    }

    func testEveryTopicHasItems() {
        for topic in HelpTopic.all {
            XCTAssertFalse(topic.items.isEmpty, "\(topic.id) has no items")
        }
    }
}

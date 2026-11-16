//
//  PlayCountFilterTests.swift
//  gridstream-ipadTests
//
//  Tests for play count Smart Filters integration.
//

import XCTest
import SwiftUI
@testable import gridstream_ipad

@MainActor
final class PlayCountFilterTests: XCTestCase {

    // MARK: - Test 1: FilterChip.unplayed displays correctly

    func testUnplayedFilterChipDisplaysCorrectly() async {
        // Given an unplayed filter chip
        let chip = FilterChip.unplayed

        // Then it should have correct display properties
        XCTAssertEqual(chip.displayText, "Unplayed")
        XCTAssertTrue(chip.id.contains("unplayed"))
    }

    // MARK: - Test 2: FilterChip.minPlayCount displays correctly

    func testMinPlayCountFilterChipDisplaysCorrectly() async {
        // Given a min play count filter chip with value 3
        let chip = FilterChip.minPlayCount(value: 3)

        // Then it should have correct display properties
        XCTAssertEqual(chip.displayText, "Played 3+ times")
        XCTAssertTrue(chip.id.contains("minPlayCount"))
    }

    // MARK: - Test 3: ContentLibraryFilters includes play count properties

    func testContentLibraryFiltersHasPlayCountProperties() async {
        // Given a fresh filters object
        var filters = ContentLibraryFilters()

        // Initially play count filters should be nil/false
        XCTAssertNil(filters.minPlayCount)
        XCTAssertFalse(filters.unplayedOnly)

        // When setting play count filters
        filters.minPlayCount = 5
        filters.unplayedOnly = true

        // Then they should persist
        XCTAssertEqual(filters.minPlayCount, 5)
        XCTAssertTrue(filters.unplayedOnly)
    }

    // MARK: - Test 4: hasActiveFilters includes play count filters

    func testHasActiveFiltersIncludesPlayCount() async {
        // Given a filters object with only play count filters
        var filters = ContentLibraryFilters()
        XCTAssertFalse(filters.hasActiveFilters)

        // When setting unplayedOnly
        filters.unplayedOnly = true

        // Then hasActiveFilters should be true
        XCTAssertTrue(filters.hasActiveFilters)

        // When clearing and setting minPlayCount instead
        filters.unplayedOnly = false
        filters.minPlayCount = 3

        // Then hasActiveFilters should still be true
        XCTAssertTrue(filters.hasActiveFilters)
    }

    // MARK: - Test 5: activeChips includes play count chips

    func testActiveChipsIncludesPlayCountChips() async {
        // Given filters with play count settings
        var filters = ContentLibraryFilters()
        filters.unplayedOnly = true
        filters.minPlayCount = 2

        // When getting active chips
        let chips = filters.activeChips

        // Then play count chips should be present
        let unplayedChip = chips.first { chip in
            if case .unplayed = chip { return true }
            return false
        }
        XCTAssertNotNil(unplayedChip)

        let minPlayCountChip = chips.first { chip in
            if case .minPlayCount = chip { return true }
            return false
        }
        XCTAssertNotNil(minPlayCountChip)
    }

    // MARK: - Test 6: removeChip handles play count chips

    func testRemoveChipHandlesPlayCountChips() async {
        // Given filters with play count settings
        var filters = ContentLibraryFilters()
        filters.unplayedOnly = true
        filters.minPlayCount = 3

        // When removing unplayed chip
        filters.removeChip(.unplayed)

        // Then unplayedOnly should be false
        XCTAssertFalse(filters.unplayedOnly)
        XCTAssertEqual(filters.minPlayCount, 3) // Other filter unchanged

        // When removing minPlayCount chip
        filters.removeChip(.minPlayCount(value: 3))

        // Then minPlayCount should be nil
        XCTAssertNil(filters.minPlayCount)
    }

    // MARK: - Test 7: clear resets play count filters

    func testClearResetsPlayCountFilters() async {
        // Given filters with various settings including play count
        var filters = ContentLibraryFilters()
        filters.searchText = "test"
        filters.unplayedOnly = true
        filters.minPlayCount = 5

        // When clearing
        filters.clear()

        // Then all play count filters should be reset
        XCTAssertFalse(filters.unplayedOnly)
        XCTAssertNil(filters.minPlayCount)
        XCTAssertTrue(filters.searchText.isEmpty)
    }

    // MARK: - Additional Tests

    func testFilterChipColorsForPlayCount() async {
        // Given play count filter chips
        let unplayedChip = FilterChip.unplayed
        let minPlayCountChip = FilterChip.minPlayCount(value: 5)

        // Then they should have appropriate colors (teal for play count)
        XCTAssertEqual(unplayedChip.color, Color.teal)
        XCTAssertEqual(minPlayCountChip.color, Color.teal)
    }

    func testMultiplePlayCountChipsDisplay() async {
        // Given filters with multiple play count values
        var filters = ContentLibraryFilters()
        filters.minPlayCount = 10

        let chips = filters.activeChips

        // Should have exactly one min play count chip
        let minPlayCountChips = chips.filter { chip in
            if case .minPlayCount = chip { return true }
            return false
        }
        XCTAssertEqual(minPlayCountChips.count, 1)
    }
}

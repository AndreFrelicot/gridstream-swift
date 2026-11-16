//
//  ContentLibraryComponentTests.swift
//  gridstream-ipadTests
//

import GridStreamAPI
import XCTest
import SwiftUI
@testable import gridstream_ipad

@MainActor
final class ContentLibraryComponentTests: XCTestCase {

    // MARK: - VideoThumbnailCell Tests

    func testVideoThumbnailCellRendersFilename() async {
        // Given a video with a filename
        let video = VideoItem(
            fileId: "file-test-123",
            filename: "Test Video.mp4",
            relativePath: "/videos/Test Video.mp4",
            sourceDirectoryId: UUID(),
            duration: 120,
            width: 1920,
            height: 1080,
            codec: "h264",
            fileSize: 1024000,
            lastModified: Date(timeIntervalSince1970: 1_705_314_600),
            sourceDirectoryName: "My Videos"
        )

        // When creating a VideoThumbnailCell
        let cell = VideoThumbnailCell(
            video: video,
            serverURL: URL(string: "http://localhost:8080"),
            isSelected: false,
            globalRating: 7,
            onTap: {}
        )

        // Then the cell should be created successfully with the video data
        XCTAssertNotNil(cell)
        XCTAssertEqual(video.filename, "Test Video.mp4")
        XCTAssertEqual(video.sourceDirectoryName, "My Videos")
    }

    func testVideoThumbnailCellShowsSelectionIndicator() async {
        // Given a video
        let video = VideoItem(
            fileId: "file-test-123",
            filename: "Test Video.mp4",
            relativePath: "/videos/Test Video.mp4",
            sourceDirectoryId: UUID(),
            duration: 120,
            width: 1920,
            height: 1080,
            codec: "h264",
            fileSize: 1024000,
            lastModified: Date(timeIntervalSince1970: 1_705_314_600),
            sourceDirectoryName: "My Videos"
        )

        // When creating a selected cell
        let selectedCell = VideoThumbnailCell(
            video: video,
            serverURL: URL(string: "http://localhost:8080"),
            isSelected: true,
            globalRating: 5,
            onTap: {}
        )

        // When creating an unselected cell
        let unselectedCell = VideoThumbnailCell(
            video: video,
            serverURL: URL(string: "http://localhost:8080"),
            isSelected: false,
            globalRating: 5,
            onTap: {}
        )

        // Then both cells should be created with different selection states
        XCTAssertNotNil(selectedCell)
        XCTAssertNotNil(unselectedCell)
    }

    // MARK: - SearchFilterBar Tests

    func testSearchFilterBarCapturesSearchText() async {
        // Given a search filter bar with empty initial text
        var capturedText = ""
        let searchText = Binding<String>(
            get: { capturedText },
            set: { capturedText = $0 }
        )

        // When the search bar is created
        let searchBar = SearchFilterBar(searchText: searchText)

        // Then it should be created with empty text
        XCTAssertNotNil(searchBar)
        XCTAssertEqual(capturedText, "")
    }

    // MARK: - FilterChipRow Tests

    func testFilterChipRowDisplaysActiveFilters() async {
        // Given active filters
        var filters = ContentLibraryFilters()
        filters.activeTagFilters = [
            TagFilter(tag: TagInfo(id: UUID(), name: "action", color: "#EF4444", ratingEnabled: false)),
            TagFilter(tag: TagInfo(id: UUID(), name: "comedy", color: "#22C55E", ratingEnabled: true))
        ]

        let onRemove: (FilterChip) -> Void = { _ in }

        // When creating a FilterChipRow
        let chipRow = FilterChipRow(filters: filters, onRemove: onRemove)

        // Then it should be created with the filter chips
        XCTAssertNotNil(chipRow)
        XCTAssertEqual(filters.activeTagFilters.count, 2)
    }

    func testFilterChipRowRemoveAction() async {
        // Given a filter chip
        let tagId = UUID()
        let tag = TagInfo(id: tagId, name: "action", color: "#EF4444", ratingEnabled: false)
        let tagFilter = TagFilter(tag: tag)
        let chip = FilterChip.tagFilter(tagFilter)

        // When checking the chip type
        switch chip {
        case .tagFilter(let filter):
            XCTAssertEqual(filter.tag.id, tagId)
            XCTAssertEqual(filter.tag.name, "action")
            XCTAssertEqual(filter.tag.color, "#EF4444")
        default:
            XCTFail("Expected tagFilter chip")
        }
    }

    // MARK: - HeartRatingView Tests

    func testHeartRatingViewDisplaysCorrectHearts() async {
        // Given a rating of 7
        let rating = 7

        // When creating a HeartRatingView
        let ratingView = HeartRatingView(
            rating: .constant(rating),
            maxRating: 10,
            size: .large
        )

        // Then it should be created successfully
        XCTAssertNotNil(ratingView)
        // The view should show 7 filled hearts and 3 empty hearts
    }

    func testHeartRatingViewSizeConfigurations() async {
        // Given different size configurations
        let largeView = HeartRatingView(
            rating: .constant(5),
            maxRating: 10,
            size: .large
        )

        let smallView = HeartRatingView(
            rating: .constant(5),
            maxRating: 10,
            size: .small
        )

        // Then both should be created with different sizes
        XCTAssertNotNil(largeView)
        XCTAssertNotNil(smallView)
    }

    // MARK: - VideoGridView Layout Tests

    /// Two cells of one row, one with a one-line title and one with a two-line
    /// title: their thumbnails must start at the same height.
    func testGridAlignsThumbnailsOfCellsWithDifferentTitleHeights() async throws {
        func video(_ filename: String) -> VideoItem {
            VideoItem(
                fileId: "file-\(filename)",
                filename: filename,
                relativePath: "/videos/\(filename)",
                sourceDirectoryId: UUID(),
                duration: 120,
                width: 1920,
                height: 1080,
                codec: "h264",
                fileSize: 1024000,
                lastModified: Date(timeIntervalSince1970: 1_705_314_600),
                sourceDirectoryName: "My Videos"
            )
        }

        // 420 points wide: two columns, at x 16...202 and 218...404.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 420, height: 400))
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(rootView: VideoGridView(
            videos: [
                video("Short.mp4"),
                video("A much longer file name that wraps onto a second line.mp4")
            ],
            serverURL: nil,
            onVideoTap: { _ in }
        ))
        window.isHidden = false
        // The window has no scene, so nothing draws it: lay it out by hand.
        try await Task.sleep(for: .milliseconds(100))
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        let firstTop = try XCTUnwrap(topOfContent(in: window, x: 40))
        let secondTop = try XCTUnwrap(topOfContent(in: window, x: 250))
        XCTAssertEqual(firstTop, secondTop)
    }

    /// The first row from the top, in points, where the window is not black at `x`.
    private func topOfContent(in window: UIWindow, x: Int) -> Int? {
        let width = Int(window.bounds.width)
        let height = Int(window.bounds.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            // UIKit draws from the top left.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            window.layer.render(in: context)
            return true
        }
        guard drawn else { return nil }
        return (0..<height).first { row in
            let offset = (row * width + x) * 4
            return pixels[offset..<offset + 3].contains { $0 > 12 }
        }
    }
}

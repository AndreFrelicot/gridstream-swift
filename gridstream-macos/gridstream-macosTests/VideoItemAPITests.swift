//
//  VideoItemAPITests.swift
//  gridstream-macosTests
//
//  Tests for VideoItem fileId API functionality.
//

import GridStreamAPI
import XCTest
@testable import gridstream_macos

final class VideoItemAPITests: XCTestCase {

    // MARK: - Test VideoItem JSON Encoding includes fileId

    func testFileIdIsIncludedInVideoItemJSONEncoding() throws {
        let videoItem = VideoItem(
            id: UUID(),
            fileId: "abc123def456789a",
            filename: "test_video.mp4",
            relativePath: "subfolder/test_video.mp4",
            sourceDirectoryId: UUID(),
            duration: 120.5,
            width: 1920,
            height: 1080,
            codec: "h264",
            fileSize: 1024000,
            lastModified: Date()
        )

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(videoItem)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("\"fileId\""), "JSON should contain fileId key")
        XCTAssertTrue(jsonString.contains("abc123def456789a"), "JSON should contain fileId value")
    }

    // MARK: - Record → VideoItem mapping

    private func makeRecord() -> VideoFileRecord {
        VideoFileRecord(
            fileId: "f1",
            path: "/Volumes/Media/Clips/sub/a.mp4",
            sourceDirectoryId: UUID(),
            filename: "a.mp4",
            fileSize: 42,
            duration: 12.5,
            width: 640,
            height: 360,
            codec: "hvc1",
            lastModified: 1_000,
            rating: 7,
            playCount: 3,
            totalViewTime: 90,
            lastPlayedAt: 2_000,
            annotationCount: 4
        )
    }

    func testAPIMappingResolvesFolderAndVersionsTheThumbnail() {
        let record = makeRecord()
        let folder = SourceDirectory(id: record.sourceDirectoryId, path: "/Volumes/Media/Clips")
        let tags = [TagSummary(from: TagRecord(name: "keep", color: TagColorPalette.red), rating: 2)]

        let item = VideoItem.api(record: record, sourceDirectory: folder, tags: tags, thumbnailUpdatedAt: 1234.9)

        XCTAssertEqual(item.id, record.id)
        XCTAssertEqual(item.fileId, "f1")
        XCTAssertEqual(item.filename, "a.mp4")
        XCTAssertEqual(item.relativePath, "sub/a.mp4")
        XCTAssertEqual(item.sourceDirectoryName, "Clips")
        XCTAssertEqual(item.sourceDirectoryId, record.sourceDirectoryId)
        XCTAssertEqual(item.duration, 12.5)
        XCTAssertEqual(item.width, 640)
        XCTAssertEqual(item.height, 360)
        XCTAssertEqual(item.codec, "hvc1")
        XCTAssertEqual(item.fileSize, 42)
        XCTAssertEqual(item.lastModified, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(item.rating, 7)
        XCTAssertEqual(item.playCount, 3)
        XCTAssertEqual(item.totalViewTime, 90)
        XCTAssertEqual(item.lastPlayedAt, Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(item.annotationCount, 4)
        XCTAssertEqual(item.tags?.map(\.name), ["keep"])
        XCTAssertEqual(item.thumbnailUrl, "/api/v1/videos/f1/thumbnail?v=1234")
    }

    func testAPIMappingWithoutFolderFallsBackToTheFilename() {
        let item = VideoItem.api(record: makeRecord(), sourceDirectory: nil)

        XCTAssertEqual(item.relativePath, "a.mp4")
        XCTAssertNil(item.sourceDirectoryName)
        XCTAssertNil(item.tags)
        XCTAssertEqual(item.thumbnailUrl, "/api/v1/videos/f1/thumbnail")
    }

    func testCatalogEntryHasNoThumbnailURLOrTags() {
        let item = VideoItem.catalogEntry(record: makeRecord(), relativePath: "sub/a.mp4")

        XCTAssertEqual(item.relativePath, "sub/a.mp4")
        XCTAssertNil(item.thumbnailUrl)
        XCTAssertNil(item.tags)
        XCTAssertNil(item.sourceDirectoryName)
        XCTAssertEqual(item.rating, 7)
    }

    // MARK: - Test VideoCatalogProvider getVideoByFileId lookup

    func testGetVideoByFileIdReturnsMatchingVideo() {
        let fileId = "0123456789abcdef"
        let videoItem = VideoItem(
            id: UUID(),
            fileId: fileId,
            filename: "matched_video.mp4",
            relativePath: "matched_video.mp4",
            sourceDirectoryId: UUID(),
            duration: 60.0,
            width: 1920,
            height: 1080,
            codec: "h264",
            fileSize: 500000,
            lastModified: Date()
        )

        let catalog = MockVideoCatalogProvider(videos: [videoItem])

        let result = catalog.getVideoByFileId(fileId)

        XCTAssertNotNil(result, "Should return a video for matching fileId")
        XCTAssertEqual(result?.filename, "matched_video.mp4")
        XCTAssertEqual(result?.fileId, fileId)
    }

    func testGetVideoByFileIdReturnsNilForUnknownFileId() {
        let videoItem = VideoItem(
            id: UUID(),
            fileId: "existing_file_id_1",
            filename: "existing_video.mp4",
            relativePath: "existing_video.mp4",
            sourceDirectoryId: UUID(),
            duration: 60.0,
            width: 1920,
            height: 1080,
            codec: "h264",
            fileSize: 500000,
            lastModified: Date()
        )

        let catalog = MockVideoCatalogProvider(videos: [videoItem])

        let result = catalog.getVideoByFileId("nonexistent_file_id")

        XCTAssertNil(result, "Should return nil for unknown fileId")
    }

    // MARK: - Test existing video list works with fileId field

    func testExistingVideoListEndpointWorksWithFileIdField() {
        let video1 = VideoItem(
            id: UUID(),
            fileId: "file_id_1_abcdef",
            filename: "video1.mp4",
            relativePath: "video1.mp4",
            sourceDirectoryId: UUID(),
            duration: 120.0,
            width: 1920,
            height: 1080,
            codec: "h264",
            fileSize: 1000000,
            lastModified: Date()
        )

        let video2 = VideoItem(
            id: UUID(),
            fileId: "file_id_2_ghijkl",
            filename: "video2.mp4",
            relativePath: "video2.mp4",
            sourceDirectoryId: UUID(),
            duration: 180.0,
            width: 3840,
            height: 2160,
            codec: "hevc",
            fileSize: 2000000,
            lastModified: Date()
        )

        let catalog = MockVideoCatalogProvider(videos: [video1, video2])

        let videos = catalog.getVideos()

        XCTAssertEqual(videos.count, 2)
        XCTAssertEqual(videos[0].fileId, "file_id_1_abcdef")
        XCTAssertEqual(videos[1].fileId, "file_id_2_ghijkl")
    }
}

// MARK: - Mock VideoCatalogProvider for Testing

private final class MockVideoCatalogProvider: VideoCatalogProvider, @unchecked Sendable {
    private let videos: [VideoItem]
    private let sourceDirectories: [SourceDirectory]

    init(videos: [VideoItem], sourceDirectories: [SourceDirectory] = []) {
        self.videos = videos
        self.sourceDirectories = sourceDirectories
    }

    func getVideos() -> [VideoItem] {
        videos
    }

    func getSourceDirectories() -> [SourceDirectory] {
        sourceDirectories
    }

    func getVideoByFileId(_ fileId: String) -> VideoItem? {
        videos.first { $0.fileId == fileId }
    }
}

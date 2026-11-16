//
//  VideoGridView.swift
//  gridstream-ipad
//

import GridStreamAPI
import SwiftUI

/// A lazy loading grid view of video thumbnails for the Content Library.
/// Uses adaptive columns based on screen width and handles loading, empty, and error states.
/// Supports infinite scroll pagination via onLoadMore callback.
struct VideoGridView: View {
    let videos: [VideoItem]
    let serverURL: URL?
    let selectedVideoIds: Set<String>
    let videoRatings: [String: Int]
    let isLoading: Bool
    let errorMessage: String?
    let hasMoreVideos: Bool
    let onVideoTap: (VideoItem) -> Void
    let onRetry: (() -> Void)?
    let onLoadMore: (() -> Void)?

    private let minimumColumnWidth: CGFloat = 180
    private let spacing: CGFloat = 16

    init(
        videos: [VideoItem],
        serverURL: URL?,
        selectedVideoIds: Set<String> = [],
        videoRatings: [String: Int] = [:],
        isLoading: Bool = false,
        errorMessage: String? = nil,
        hasMoreVideos: Bool = false,
        onVideoTap: @escaping (VideoItem) -> Void,
        onRetry: (() -> Void)? = nil,
        onLoadMore: (() -> Void)? = nil
    ) {
        self.videos = videos
        self.serverURL = serverURL
        self.selectedVideoIds = selectedVideoIds
        self.videoRatings = videoRatings
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.hasMoreVideos = hasMoreVideos
        self.onVideoTap = onVideoTap
        self.onRetry = onRetry
        self.onLoadMore = onLoadMore
    }

    private var columns: [GridItem] {
        // Top-aligned: titles take one or two lines, and centred cells would
        // put the thumbnails of one row at different heights.
        [GridItem(.adaptive(minimum: minimumColumnWidth), spacing: spacing, alignment: .top)]
    }

    var body: some View {
        Group {
            if isLoading && videos.isEmpty {
                loadingView
            } else if let error = errorMessage {
                errorView(message: error)
            } else if videos.isEmpty {
                emptyView
            } else {
                gridContent
            }
        }
    }

    // MARK: - Grid Content

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(videos) { video in
                    VideoThumbnailCell(
                        video: video,
                        serverURL: serverURL,
                        isSelected: selectedVideoIds.contains(video.fileId),
                        globalRating: videoRatings[video.fileId] ?? 0,
                        onTap: {
                            onVideoTap(video)
                        }
                    )
                    .onAppear {
                        // Trigger load more when near the end (last 10 items)
                        if shouldLoadMore(for: video) {
                            onLoadMore?()
                        }
                    }
                }
            }
            .padding(spacing)

            // Loading indicator for pagination
            if isLoading && !videos.isEmpty {
                ProgressView()
                    .padding()
            }

            // Load more button as fallback
            if hasMoreVideos && !isLoading {
                Button {
                    onLoadMore?()
                } label: {
                    Text("Load More Videos")
                        .font(.subheadline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .padding(.bottom, 20)
            }
        }
    }

    private func shouldLoadMore(for video: VideoItem) -> Bool {
        guard hasMoreVideos, !isLoading, onLoadMore != nil else { return false }
        guard let index = videos.firstIndex(where: { $0.id == video.id }) else { return false }
        // Trigger when within last 10 items
        return index >= videos.count - 10
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Loading videos...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Failed to load videos")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let onRetry = onRetry {
                Button("Retry") {
                    onRetry()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Videos Found")
                .font(.headline)

            Text("No videos match your current filters.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Previews

#Preview("Loading") {
    VideoGridView(
        videos: [],
        serverURL: URL(string: "http://localhost:8080"),
        isLoading: true,
        onVideoTap: { _ in }
    )
}

#Preview("Error") {
    VideoGridView(
        videos: [],
        serverURL: URL(string: "http://localhost:8080"),
        errorMessage: "Unable to connect to server",
        onVideoTap: { _ in },
        onRetry: {}
    )
}

#Preview("Empty") {
    VideoGridView(
        videos: [],
        serverURL: URL(string: "http://localhost:8080"),
        onVideoTap: { _ in }
    )
}

#Preview("With Videos") {
    VideoGridView(
        videos: PreviewData.sampleVideos(count: 12),
        serverURL: URL(string: "http://localhost:8080"),
        selectedVideoIds: ["video-3", "video-7"],
        videoRatings: ["video-1": 8, "video-2": 5, "video-3": 10, "video-5": 3, "video-8": 7],
        onVideoTap: { video in
            print("Tapped: \(video.filename)")
        }
    )
}

#Preview("Loading More (Pagination)") {
    VideoGridView(
        videos: PreviewData.sampleVideos(count: 6),
        serverURL: URL(string: "http://localhost:8080"),
        isLoading: true,
        onVideoTap: { _ in }
    )
}

#Preview("iPad Landscape") {
    VideoGridView(
        videos: PreviewData.sampleVideos(count: 20),
        serverURL: URL(string: "http://localhost:8080"),
        selectedVideoIds: ["video-5"],
        videoRatings: ["video-5": 9, "video-10": 7, "video-15": 5],
        onVideoTap: { _ in }
    )
    .frame(width: 1024, height: 768)
}

// MARK: - Preview Helper

private enum PreviewData {
    static func sampleVideos(count: Int) -> [VideoItem] {
        (1...count).map { i in
            VideoItem(
                fileId: "file-\(i)",
                filename: "Sample Video \(i).mp4",
                relativePath: "/videos/sample\(i).mp4",
                sourceDirectoryId: UUID(),
                duration: Double(i * 60),
                width: 1920,
                height: 1080,
                codec: "h264",
                fileSize: Int64(i * 1024000),
                lastModified: Date(),
                sourceDirectoryName: ["Movies", "Clips", "Archives"][i % 3]
            )
        }
    }
}

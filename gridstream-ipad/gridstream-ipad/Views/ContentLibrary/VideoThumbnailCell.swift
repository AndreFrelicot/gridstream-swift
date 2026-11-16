//
//  VideoThumbnailCell.swift
//  gridstream-ipad
//

import GridStreamAPI
import SwiftUI

/// A grid cell that displays a video thumbnail with metadata for the Content Library.
/// Shows thumbnail image, video filename, source directory, rating overlay,
/// and selection indicator.
struct VideoThumbnailCell: View {
    let video: VideoItem
    let serverURL: URL?
    let isSelected: Bool
    let globalRating: Int
    let onTap: () -> Void

    @State private var thumbnailImage: UIImage?
    @State private var isLoading = true

    private let thumbnailAspectRatio: CGFloat = 16 / 9
    private let cornerRadius: CGFloat = 8

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                thumbnailView
                videoMetadata
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(video.filename), \(video.sourceDirectoryName ?? String(localized: "Unknown source"))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onAppear {
            loadThumbnail()
        }
        .onChange(of: video.fileId) { _, _ in
            loadThumbnail()
        }
        .onChange(of: video.thumbnailUrl) { _, _ in
            loadThumbnail()
        }
    }

    // MARK: - Thumbnail Loading

    private func loadThumbnail() {
        guard let serverURL = serverURL,
              let url = VideoURLBuilder.thumbnailURL(for: video, serverURL: serverURL) else {
            isLoading = false
            return
        }

        // Check cache first (keyed by the versioned URL, not the file ID,
        // so a regenerated thumbnail is picked up)
        if let cached = ThumbnailCache.shared.thumbnail(for: ThumbnailPrefetcher.cacheKey(for: url)) {
            thumbnailImage = cached
            isLoading = false
            return
        }

        // Request with high priority (visible cell)
        isLoading = true
        ThumbnailPrefetcher.shared.requestThumbnail(
            for: url,
            priority: .high
        ) { image in
            self.thumbnailImage = image
            self.isLoading = false
        }
    }

    // MARK: - Thumbnail View

    private var thumbnailView: some View {
        ZStack(alignment: .topTrailing) {
            thumbnailContent

            // Selection indicator
            if isSelected {
                selectionOverlay
            }

            // Rating overlay
            if globalRating > 0 {
                ratingOverlay
            }
        }
        .aspectRatio(thumbnailAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
        }
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let image = thumbnailImage {
            // The picture fills the cell without sizing it: a thumbnail wider
            // than the cell would otherwise spill over the next ones.
            Color.clear.overlay {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        } else if isLoading {
            thumbnailPlaceholder
                .overlay {
                    ProgressView()
                        .tint(.white)
                }
        } else {
            thumbnailPlaceholder
        }
    }

    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .overlay {
                Image(systemName: "film")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
    }

    private var selectionOverlay: some View {
        ZStack {
            Color.accentColor.opacity(0.3)

            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(.white)
                .background {
                    Circle()
                        .fill(Color.accentColor)
                        .padding(-4)
                }
        }
    }

    private var ratingOverlay: some View {
        VStack {
            HStack {
                Spacer()
                CompactHeartRatingView(rating: globalRating)
                    .padding(6)
            }
            Spacer()
        }
    }

    // MARK: - Video Metadata

    private var videoMetadata: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(video.filename)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .truncationMode(.middle)
                .foregroundStyle(.primary)

            if let directoryName = video.sourceDirectoryName {
                Text(directoryName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Previews

private enum ThumbnailPreviewData {
    static func sampleVideo(id: String = "test-123", filename: String = "Sample Video.mp4") -> VideoItem {
        VideoItem(
            fileId: "file-\(id)",
            filename: filename,
            relativePath: "/videos/\(id).mp4",
            sourceDirectoryId: UUID(),
            duration: 3725,
            width: 1920,
            height: 1080,
            codec: "h264",
            fileSize: 52428800,
            lastModified: Date(),
            sourceDirectoryName: "Videos"
        )
    }
}

#Preview("Single Cell") {
    VideoThumbnailCell(
        video: ThumbnailPreviewData.sampleVideo(filename: "Amazing Summer Vacation Video.mp4"),
        serverURL: URL(string: "http://localhost:8080"),
        isSelected: false,
        globalRating: 7,
        onTap: {}
    )
    .frame(width: 200)
    .padding()
}

#Preview("Selected Cell") {
    VideoThumbnailCell(
        video: ThumbnailPreviewData.sampleVideo(id: "test-456", filename: "Short Clip.mov"),
        serverURL: URL(string: "http://localhost:8080"),
        isSelected: true,
        globalRating: 10,
        onTap: {}
    )
    .frame(width: 200)
    .padding()
}

#Preview("No Rating") {
    VideoThumbnailCell(
        video: ThumbnailPreviewData.sampleVideo(id: "test-789", filename: "Unrated Video.mp4"),
        serverURL: URL(string: "http://localhost:8080"),
        isSelected: false,
        globalRating: 0,
        onTap: {}
    )
    .frame(width: 200)
    .padding()
}

#Preview("Grid of Cells") {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 16) {
        ForEach(1...4, id: \.self) { i in
            VideoThumbnailCell(
                video: ThumbnailPreviewData.sampleVideo(id: "\(i)", filename: "Video \(i).mp4"),
                serverURL: URL(string: "http://localhost:8080"),
                isSelected: i == 2,
                globalRating: i * 2,
                onTap: {}
            )
        }
    }
    .padding()
}

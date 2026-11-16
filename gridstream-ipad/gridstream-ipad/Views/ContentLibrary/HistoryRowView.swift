//
//  HistoryRowView.swift
//  gridstream-ipad
//

import GridStreamAPI
import SwiftUI

struct HistoryRowView: View {
    let video: VideoItem
    let serverURL: URL?

    @State private var thumbnailImage: UIImage?
    @State private var isLoadingThumbnail = true

    private var relativeTimeString: String {
        guard let lastPlayed = video.lastPlayedAt else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastPlayed, relativeTo: Date())
    }

    private var durationString: String {
        let totalSeconds = Int(video.duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        HStack(spacing: 12) {
            thumbnailView

            VStack(alignment: .leading, spacing: 4) {
                Text(video.filename)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if !relativeTimeString.isEmpty {
                        Label(relativeTimeString, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if video.playCount > 0 {
                        Label("\(video.playCount) plays", systemImage: "play.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(durationString)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if video.rating > 0 {
                        CompactHeartRatingView(rating: video.rating)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        Group {
            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 45)
                    .clipped()
                    .cornerRadius(6)
            } else {
                thumbnailPlaceholder
            }
        }
        .onAppear { loadThumbnail() }
        .onChange(of: video.fileId) { _, _ in loadThumbnail() }
        .onChange(of: video.thumbnailUrl) { _, _ in loadThumbnail() }
    }

    private func loadThumbnail() {
        guard let serverURL = serverURL,
              let url = VideoURLBuilder.thumbnailURL(for: video, serverURL: serverURL) else {
            isLoadingThumbnail = false
            return
        }

        // Check cache first (keyed by the versioned URL, not the file ID,
        // so a regenerated thumbnail is picked up)
        if let cached = ThumbnailCache.shared.thumbnail(for: ThumbnailPrefetcher.cacheKey(for: url)) {
            thumbnailImage = cached
            isLoadingThumbnail = false
            return
        }

        // Request with high priority (visible cell)
        isLoadingThumbnail = true
        ThumbnailPrefetcher.shared.requestThumbnail(
            for: url,
            priority: .high
        ) { image in
            self.thumbnailImage = image
            self.isLoadingThumbnail = false
        }
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 80, height: 45)
            .overlay {
                Image(systemName: "film")
                    .foregroundStyle(.secondary)
            }
    }
}

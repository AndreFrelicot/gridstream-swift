//
//  PlaybackRatingOverlay.swift
//  gridstream-ipad
//
//  Displays rating and play count information during video playback, appearing
//  alongside transport controls. Shows global rating using large hearts,
//  per-tag ratings underneath using smaller hearts, and play count.
//

import SwiftUI

/// Rating overlay for video playback, displaying global and per-tag ratings.
/// Designed to appear alongside TransportControlsView and match its visibility behavior.
/// Collapsed by default, showing a single heart + "X/10". Expands on tap.
struct PlaybackRatingOverlay: View {
    let videoId: String
    @Binding var ratingInfo: VideoRatingInfo
    let videoTags: [TagInfo]
    let serverURL: URL?
    let onGlobalRatingChanged: (Int) -> Void
    let onTagRatingChanged: (UUID, Int) -> Void

    /// Play count to display (0 means loaded but no plays yet)
    var playCount: Int = 0

    /// Total view time in seconds (0 means loaded but no view time yet)
    var viewTime: Int = 0

    /// Whether to show a compact version (for smaller tiles)
    var isCompact: Bool = false

    /// Called when rating expands (e.g. to suspend HUD auto-hide)
    var onExpand: (() -> Void)?

    /// Called when rating collapses (e.g. to resume HUD auto-hide)
    var onCollapse: (() -> Void)?

    /// Whether the rating hearts are expanded
    @State private var isRatingExpanded: Bool = false

    /// Tags that have rating enabled
    private var ratingEnabledTags: [TagInfo] {
        videoTags.filter { $0.ratingEnabled }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 8 : 12) {
            // Play count display (always shown)
            playCountSection(count: playCount)

            if isRatingExpanded {
                globalRatingSection

                if !ratingEnabledTags.isEmpty {
                    perTagRatingsSection
                }

                // Collapse button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isRatingExpanded = false
                    }
                    onCollapse?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.up")
                            .font(.caption2)
                        Text("Collapse")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                collapsedRatingSection
            }
        }
        .padding(isCompact ? 12 : 16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: videoId) { _, _ in
            if isRatingExpanded {
                isRatingExpanded = false
                onCollapse?()
            }
        }
    }

    // MARK: - Collapsed Rating Section

    private func expandRating() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isRatingExpanded = true
        }
        onExpand?()
    }

    private var collapsedRatingSection: some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : 6) {
            // Global rating - collapsed
            Button {
                expandRating()
            } label: {
                collapsedRatingRow(
                    rating: ratingInfo.globalRating,
                    label: nil,
                    color: nil
                )
            }
            .buttonStyle(.plain)

            // Per-tag ratings - collapsed
            if !ratingEnabledTags.isEmpty {
                ForEach(ratingEnabledTags) { tag in
                    Button {
                        expandRating()
                    } label: {
                        collapsedRatingRow(
                            rating: ratingInfo.tagRatings[tag.id] ?? 0,
                            label: tag.name,
                            color: tag.swiftUIColor
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func collapsedRatingRow(rating: Int, label: String?, color: Color?) -> some View {
        HStack(spacing: isCompact ? 4 : 6) {
            if let color, let label {
                Circle()
                    .fill(color)
                    .frame(width: isCompact ? 8 : 10, height: isCompact ? 8 : 10)

                Text(label)
                    .font(isCompact ? .caption2 : .caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Image(systemName: rating > 0 ? "heart.fill" : "heart")
                .font(.system(size: isCompact ? 12 : 14))
                .foregroundStyle(rating > 0 ? .red : .orange.opacity(0.7))

            Text("\(rating)/10")
                .font(isCompact ? .caption2 : .caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Play Count Section

    @ViewBuilder
    private func playCountSection(count: Int) -> some View {
        HStack(spacing: isCompact ? 8 : 12) {
            // Play count
            HStack(spacing: 4) {
                Image(systemName: "play.fill")
                    .font(isCompact ? .caption : .footnote)
                    .foregroundStyle(.secondary)

                Text("\(count)")
                    .font(isCompact ? .caption : .footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Played \(count) times")

            // View time (always shown)
            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(isCompact ? .caption : .footnote)
                    .foregroundStyle(.secondary)

                Text(formatViewTime(viewTime))
                    .font(isCompact ? .caption : .footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Total view time: \(formatViewTime(viewTime))")
        }
    }

    /// Formats view time in seconds to a human-readable string
    private func formatViewTime(_ seconds: Int) -> String {
        if seconds < 60 {
            return String(localized: "\(seconds)s")
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return String(localized: "\(minutes)m")
        } else {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            if minutes > 0 {
                return String(localized: "\(hours)h \(minutes)m")
            } else {
                return String(localized: "\(hours)h")
            }
        }
    }

    // MARK: - Global Rating Section

    private var globalRatingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !isCompact {
                Text("Rating")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }

            HeartRatingView(
                rating: $ratingInfo.globalRating,
                maxRating: 10,
                size: isCompact ? .small : .large,
                isEditable: true
            ) { newRating in
                onGlobalRatingChanged(newRating)
            }
        }
    }

    // MARK: - Per-Tag Ratings Section

    private var perTagRatingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !isCompact {
                Divider()
                    .padding(.vertical, 4)
            }

            ForEach(ratingEnabledTags) { tag in
                PlaybackTagRatingRow(
                    tag: tag,
                    rating: Binding(
                        get: { ratingInfo.tagRatings[tag.id] ?? 0 },
                        set: { ratingInfo.tagRatings[tag.id] = $0 }
                    ),
                    isCompact: isCompact,
                    onRatingChanged: { newRating in
                        onTagRatingChanged(tag.id, newRating)
                    }
                )
            }
        }
    }
}

// MARK: - Playback Tag Rating Row

/// A row displaying a tag's name and its rating hearts for the playback overlay.
private struct PlaybackTagRatingRow: View {
    let tag: TagInfo
    @Binding var rating: Int
    let isCompact: Bool
    let onRatingChanged: (Int) -> Void

    var body: some View {
        HStack(spacing: isCompact ? 8 : 12) {
            // Tag indicator with color and name
            HStack(spacing: 4) {
                Circle()
                    .fill(tag.swiftUIColor)
                    .frame(width: isCompact ? 8 : 10, height: isCompact ? 8 : 10)

                Text(tag.name)
                    .font(isCompact ? .caption2 : .caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(minWidth: isCompact ? 60 : 80, alignment: .leading)

            // Rating hearts
            HeartRatingView(
                rating: $rating,
                maxRating: 10,
                size: .small,
                isEditable: true
            ) { newRating in
                onRatingChanged(newRating)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tag.name) rating: \(rating) of 10")
    }
}

// MARK: - Compact Playback Rating View

// MARK: - Previews

#Preview("Full Rating Overlay") {
    struct PreviewWrapper: View {
        let tag1 = TagInfo(id: UUID(), name: "action", color: "#EF4444", ratingEnabled: true)
        let tag2 = TagInfo(id: UUID(), name: "comedy", color: "#22C55E", ratingEnabled: false)
        let tag3 = TagInfo(id: UUID(), name: "drama", color: "#3B82F6", ratingEnabled: true)

        @State private var ratingInfo: VideoRatingInfo

        init() {
            _ratingInfo = State(initialValue: VideoRatingInfo(
                globalRating: 7,
                tagRatings: [:]
            ))
        }

        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()

                PlaybackRatingOverlay(
                    videoId: "test-video",
                    ratingInfo: $ratingInfo,
                    videoTags: [tag1, tag2, tag3],
                    serverURL: URL(string: "http://localhost:8080"),
                    onGlobalRatingChanged: { rating in
                        print("Global rating changed to \(rating)")
                    },
                    onTagRatingChanged: { tagId, rating in
                        print("Tag \(tagId) rating changed to \(rating)")
                    },
                    playCount: 12
                )
            }
        }
    }

    return PreviewWrapper()
}

#Preview("Compact Rating Overlay") {
    struct PreviewWrapper: View {
        let tag1 = TagInfo(id: UUID(), name: "action", color: "#EF4444", ratingEnabled: true)

        @State private var ratingInfo = VideoRatingInfo(globalRating: 8, tagRatings: [:])

        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()

                PlaybackRatingOverlay(
                    videoId: "test-video",
                    ratingInfo: $ratingInfo,
                    videoTags: [tag1],
                    serverURL: URL(string: "http://localhost:8080"),
                    onGlobalRatingChanged: { _ in },
                    onTagRatingChanged: { _, _ in },
                    playCount: 5,
                    isCompact: true
                )
            }
        }
    }

    return PreviewWrapper()
}

#Preview("No Tags") {
    struct PreviewWrapper: View {
        @State private var ratingInfo = VideoRatingInfo(globalRating: 5, tagRatings: [:])

        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()

                PlaybackRatingOverlay(
                    videoId: "test-video",
                    ratingInfo: $ratingInfo,
                    videoTags: [],
                    serverURL: URL(string: "http://localhost:8080"),
                    onGlobalRatingChanged: { _ in },
                    onTagRatingChanged: { _, _ in }
                )
            }
        }
    }

    return PreviewWrapper()
}

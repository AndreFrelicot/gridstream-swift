import GridStreamAPI
import SwiftUI

struct TimeRangeEditorView: View {
    static let rangeColors: [Color] = [
        .red, .orange, .yellow, .green, .cyan,
        .blue, .purple, .pink, .mint, .indigo
    ]

    let timeRanges: [TimeRangeDTO]
    let currentTime: Double
    @Binding var pendingStart: Double?
    @Binding var editingRangeId: UUID?
    let serverURL: URL?
    let videoFileId: String?
    let frameRate: Double
    let onCreateRange: (Double, Double) -> Void
    let onUpdateRange: (UUID, Double, Double) -> Void
    let onDeleteRange: (UUID) -> Void
    let onSeek: (Double) -> Void
    let onDone: () -> Void

    private var isEditing: Bool {
        editingRangeId != nil
    }

    private var editingRange: TimeRangeDTO? {
        guard let id = editingRangeId else { return nil }
        return timeRanges.first { $0.id == id }
    }

    /// Whether the playhead has moved away from both range endpoints
    private var hasPlayheadMoved: Bool {
        guard let range = editingRange else { return false }
        let nearStart = abs(currentTime - range.startTime) < 0.05
        let nearEnd = abs(currentTime - range.endTime) < 0.05
        return !nearStart && !nearEnd
    }

    var body: some View {
        VStack(spacing: 8) {
            // Header row
            HStack {
                Text("Time Ranges")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("\(Int(frameRate)) fps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                if isEditing {
                    Button("Dismiss edit") {
                        editingRangeId = nil
                        pendingStart = nil
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                }
                Button("Done") {
                    onDone()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.teal)
            }

            // Action row: Set/Update Start & End
            if isEditing {
                editActionRow
            } else {
                createActionRow
            }

            // Range list (horizontally scrollable)
            if !timeRanges.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        let sortedRanges = timeRanges.sorted { $0.startTime < $1.startTime }
                        ForEach(Array(sortedRanges.enumerated()), id: \.element.id) { index, range in
                            TimeRangeCard(
                                range: range,
                                color: Self.rangeColors[index % Self.rangeColors.count],
                                isSelected: editingRangeId == range.id,
                                serverURL: serverURL,
                                videoFileId: videoFileId,
                                frameRate: frameRate,
                                onDelete: {
                                    // If deleting the editing range, exit edit mode
                                    if editingRangeId == range.id {
                                        editingRangeId = nil
                                    }
                                    onDeleteRange(range.id)
                                },
                                onTap: {
                                    if editingRangeId == range.id {
                                        // Deselect
                                        editingRangeId = nil
                                    } else {
                                        // Enter edit mode for this range
                                        editingRangeId = range.id
                                        pendingStart = nil
                                        onSeek(range.startTime)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Create Mode Action Row

    private var createActionRow: some View {
        HStack(spacing: 12) {
            Button(action: {
                pendingStart = currentTime
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right.to.line")
                        .font(.caption)
                    Text("Set Start")
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(pendingStart != nil ? Color.teal : Color.white.opacity(0.15))
                )
                .foregroundStyle(pendingStart != nil ? .black : .white)
            }
            .buttonStyle(.plain)

            if let start = pendingStart {
                Text("\(formatTimeWithFrames(start, frameRate: frameRate)) \u{2192} \(formatTimeWithFrames(currentTime, frameRate: frameRate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button(action: {
                guard let start = pendingStart else { return }
                let end = currentTime
                // Auto-swap if end is before start
                let lo = min(start, end)
                let hi = max(start, end)
                guard hi - lo > 0.01 else { return }
                onCreateRange(lo, hi)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.to.line")
                        .font(.caption)
                    Text("Set End")
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(pendingStart != nil ? Color.teal : Color.white.opacity(0.1))
                )
                .foregroundStyle(pendingStart != nil ? .black : .white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(pendingStart == nil)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Edit Mode Action Row

    private var editActionRow: some View {
        HStack(spacing: 12) {
            if let range = editingRange {
                // Update Start: immediately updates range start to current playhead
                Button(action: {
                    let newStart = currentTime
                    let existingEnd = range.endTime
                    let lo = min(newStart, existingEnd)
                    let hi = max(newStart, existingEnd)
                    guard hi - lo > 0.01 else { return }
                    onUpdateRange(range.id, lo, hi)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.to.line")
                            .font(.caption)
                        Text("Update Start")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hasPlayheadMoved ? Color.orange : Color.white.opacity(0.15))
                    )
                    .foregroundStyle(hasPlayheadMoved ? .black : .white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(!hasPlayheadMoved)

                // Show current range timecodes
                Text("\(formatTimeWithFrames(range.startTime, frameRate: frameRate)) \u{2192} \(formatTimeWithFrames(range.endTime, frameRate: frameRate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                // Update End: immediately updates range end to current playhead
                Button(action: {
                    let existingStart = range.startTime
                    let newEnd = currentTime
                    let lo = min(existingStart, newEnd)
                    let hi = max(existingStart, newEnd)
                    guard hi - lo > 0.01 else { return }
                    onUpdateRange(range.id, lo, hi)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.to.line")
                            .font(.caption)
                        Text("Update End")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(hasPlayheadMoved ? Color.orange : Color.white.opacity(0.15))
                    )
                    .foregroundStyle(hasPlayheadMoved ? .black : .white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(!hasPlayheadMoved)
            }

            Spacer(minLength: 0)
        }
    }

    private func formatTimeWithFrames(_ timeInSeconds: Double, frameRate: Double) -> String {
        guard timeInSeconds.isFinite && timeInSeconds >= 0 else {
            return "0:00:00"
        }

        let totalSeconds = Int(timeInSeconds)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let frame = Int((timeInSeconds - Double(totalSeconds)) * frameRate)

        return String(format: "%d:%02d:%02d", minutes, seconds, frame)
    }
}

// MARK: - Time Range Card

private struct TimeRangeCard: View {
    let range: TimeRangeDTO
    let color: Color
    let isSelected: Bool
    let serverURL: URL?
    let videoFileId: String?
    let frameRate: Double
    let onDelete: () -> Void
    let onTap: () -> Void

    @State private var marchingAntsPhase: CGFloat = 0

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                // Thumbnail
                thumbnailView
                    .frame(width: 80, height: 45)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(color, lineWidth: isSelected ? 3 : 2)
                    )
                    .overlay {
                        if isSelected {
                            // Animated marching ants on selected thumbnail border
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(style: StrokeStyle(
                                    lineWidth: 2,
                                    dash: [6, 4],
                                    dashPhase: marchingAntsPhase
                                ))
                                .foregroundStyle(.black)
                        }
                    }

                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white, .red)
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }
            .padding(6)

            // Timecodes
            Text("\(formatTimeWithFrames(range.startTime)) \u{2192} \(formatTimeWithFrames(range.endTime))")
                .font(.caption2)
                .foregroundStyle(isSelected ? .white : .secondary)
                .monospacedDigit()
                .lineLimit(1)

            // Duration
            Text(formatDuration(range.endTime - range.startTime))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1))
                : nil
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onChange(of: isSelected) { _, selected in
            if selected {
                marchingAntsPhase = 0
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    marchingAntsPhase = 10 // dash + gap = 6 + 4
                }
            } else {
                withAnimation(.default) {
                    marchingAntsPhase = 0
                }
            }
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let serverURL = serverURL, let videoId = videoFileId {
            let frameURL = VideoURLBuilder.buildScrubFrameURL(from: serverURL, videoId: videoId, time: range.startTime)
            AsyncImage(url: frameURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Color.gray.opacity(0.3)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                default:
                    Color.gray.opacity(0.2)
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.5)
                        }
                }
            }
        } else {
            Color.gray.opacity(0.3)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func formatTimeWithFrames(_ timeInSeconds: Double) -> String {
        guard timeInSeconds.isFinite && timeInSeconds >= 0 else {
            return "0:00:00"
        }

        let totalSeconds = Int(timeInSeconds)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let frame = Int((timeInSeconds - Double(totalSeconds)) * frameRate)

        return String(format: "%d:%02d:%02d", minutes, seconds, frame)
    }

    private func formatDuration(_ duration: Double) -> String {
        guard duration.isFinite && duration >= 0 else {
            return String(localized: "0s 0f")
        }

        let totalSeconds = Int(duration)
        let frames = Int((duration - Double(totalSeconds)) * frameRate)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if minutes > 0 {
            return String(localized: "\(minutes)m \(seconds)s \(frames)f")
        }
        return String(localized: "\(seconds)s \(frames)f")
    }
}

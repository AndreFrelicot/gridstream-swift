import SwiftUI

struct AnnotationEditorView: View {
    let annotationTimes: [Double]
    let currentTime: Double
    let frameRate: Double
    var serverURL: URL?
    var videoFileId: String?
    var onStepBackward: () -> Void
    var onStepForward: () -> Void
    var onSeekToFrame: (Double) -> Void
    var onDeleteAnnotation: (Double) -> Void
    var isCompact: Bool = false

    @State private var isFrameListExpanded = false

    var body: some View {
        VStack(spacing: 8) {
            // Header row: step buttons, current frame, frames toggle
            HStack(spacing: isCompact ? 8 : 12) {
                // Step backward button
                Button(action: onStepBackward) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: isCompact ? 12 : 14, weight: .semibold))
                        .frame(width: isCompact ? 24 : 28, height: isCompact ? 24 : 28)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                // Current frame timecode
                Text("Frame \(formatTimeWithFrames(currentTime))")
                    .font(isCompact ? .caption.monospacedDigit() : .subheadline.monospacedDigit())
                    .foregroundStyle(.white)

                // Step forward button
                Button(action: onStepForward) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: isCompact ? 12 : 14, weight: .semibold))
                        .frame(width: isCompact ? 24 : 28, height: isCompact ? 24 : 28)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                // Frames toggle button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isFrameListExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text("Frames")
                            .font(isCompact ? .caption.weight(.medium) : .subheadline.weight(.medium))
                        if !isFrameListExpanded {
                            Text("\(annotationTimes.count)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.orange))
                                .foregroundStyle(.white)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .rotationEffect(.degrees(isFrameListExpanded ? 90 : 0))
                    }
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            // Collapsible annotated frames list
            if isFrameListExpanded && !annotationTimes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(annotationTimes, id: \.self) { frameTime in
                            AnnotationFrameCard(
                                frameTime: frameTime,
                                isActive: isCurrentFrame(frameTime),
                                serverURL: serverURL,
                                videoFileId: videoFileId,
                                frameRate: frameRate,
                                isCompact: isCompact,
                                onTap: { onSeekToFrame(frameTime) },
                                onDelete: { onDeleteAnnotation(frameTime) }
                            )
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(isCompact ? 8 : 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func isCurrentFrame(_ frameTime: Double) -> Bool {
        guard frameRate > 0 else { return false }
        let frameDuration = 1.0 / frameRate
        return abs(currentTime - frameTime) < frameDuration * 0.5
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
}

// MARK: - Annotation Frame Card

private struct AnnotationFrameCard: View {
    let frameTime: Double
    let isActive: Bool
    let serverURL: URL?
    let videoFileId: String?
    let frameRate: Double
    let isCompact: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                thumbnailView
                    .frame(width: 80, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isActive ? Color.orange : Color.clear, lineWidth: 2)
                    )

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white, .red)
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
            }

            Text(formatTimeWithFrames(frameTime))
                .font(.caption2)
                .foregroundStyle(isActive ? .white : .secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(4)
        .background(
            isActive
                ? RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1))
                : nil
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let serverURL = serverURL, let videoId = videoFileId {
            let frameURL = VideoURLBuilder.buildScrubFrameURL(from: serverURL, videoId: videoId, time: frameTime)
            AsyncImage(url: frameURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    Color.gray.opacity(0.3)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                default:
                    Color.gray.opacity(0.2)
                        .overlay { ProgressView().scaleEffect(0.5) }
                }
            }
        } else {
            Color.gray.opacity(0.3)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                        .font(.caption)
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
}

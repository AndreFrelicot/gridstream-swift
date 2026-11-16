import GridStreamAPI
import SwiftUI

struct CaptureGalleryView: View {
    let captures: [FrameCaptureDTO]
    let currentTime: Double
    let serverURL: URL?
    let frameRate: Double
    let onSeek: (Double) -> Void
    let onDelete: (String) -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Header row
            HStack {
                Text("Captures")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("\(captures.count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.yellow))
                Spacer(minLength: 12)
                Button("Done") {
                    onDone()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.yellow)
            }

            // Capture cards (horizontally scrollable)
            if !captures.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        let sortedCaptures = captures.sorted { $0.timestamp < $1.timestamp }
                        ForEach(sortedCaptures) { capture in
                            CaptureCard(
                                capture: capture,
                                serverURL: serverURL,
                                frameRate: frameRate,
                                onDelete: { onDelete(capture.id) },
                                onTap: { onSeek(capture.timestamp) }
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
}

// MARK: - Capture Card

private struct CaptureCard: View {
    let capture: FrameCaptureDTO
    let serverURL: URL?
    let frameRate: Double
    let onDelete: () -> Void
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                // Thumbnail
                thumbnailView
                    .frame(width: 80, height: 45)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.yellow, lineWidth: 2)
                    )

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

            // Timecode
            Text(formatTimeWithFrames(capture.timestamp))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let serverURL = serverURL {
            let imageURL = VideoURLBuilder.buildCaptureImageURL(from: serverURL, captureId: capture.id)
            AsyncImage(url: imageURL) { phase in
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
}

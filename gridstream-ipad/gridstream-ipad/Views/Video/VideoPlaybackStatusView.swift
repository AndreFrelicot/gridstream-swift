//
//  VideoPlaybackStatusView.swift
//  gridstream-ipad
//

import SwiftUI

/// Shows `VideoPlaybackStatusView`, but withholds transient statuses
/// (preparing/seeking/buffering) until they have lasted `transientDelay`.
/// Short operations such as frame stepping in annotation mode complete in a few
/// milliseconds, and showing the overlay for them only produces flicker.
/// Actionable statuses (ended/interrupted) always appear immediately.
struct VideoPlaybackStatusOverlay: View {
    let status: VideoPlayerState.PlaybackStatus?
    var endActions: VideoEndActions?
    let onResume: () -> Void

    private static let transientDelay: Double = 1.0

    @State private var visibleStatus: VideoPlayerState.PlaybackStatus?
    @State private var transientStart: Date?

    var body: some View {
        ZStack {
            if let visibleStatus {
                VideoPlaybackStatusView(status: visibleStatus, endActions: endActions, onResume: onResume)
            }
        }
        .task(id: status) {
            guard let status else {
                transientStart = nil
                visibleStatus = nil
                return
            }

            guard Self.isTransient(status) else {
                transientStart = nil
                visibleStatus = status
                return
            }

            // Already on screen: swap the message without restarting the delay.
            guard visibleStatus == nil else {
                visibleStatus = status
                return
            }

            // Measure from the start of the transient run, not from this status,
            // so a seek that rolls into buffering still surfaces after 1 second.
            let start = transientStart ?? Date()
            transientStart = start
            let remaining = Self.transientDelay - Date().timeIntervalSince(start)
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled else { return }
            }
            visibleStatus = status
        }
    }

    private static func isTransient(_ status: VideoPlayerState.PlaybackStatus) -> Bool {
        switch status {
        case .preparing, .seeking, .buffering:
            return true
        case .ended, .interrupted:
            return false
        }
    }
}

/// The choices offered at the end of a video besides Replay.
struct VideoEndActions {
    let onNext: () -> Void
    let onRandom: () -> Void
    /// Name of the list the tile plays from; nil for the library.
    let sourceName: String?
}

struct VideoPlaybackStatusView: View {
    let status: VideoPlayerState.PlaybackStatus
    var endActions: VideoEndActions?
    let onResume: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)

            if status == .ended, let endActions {
                endChoices(endActions)
            } else {
                statusContent
            }
        }
        .allowsHitTesting(isActionable)
    }

    /// Replay, Next and Random. Labeled when the tile is big enough, icons
    /// only on small tiles.
    private func endChoices(_ actions: VideoEndActions) -> some View {
        ViewThatFits {
            VStack(spacing: 14) {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                HStack(spacing: 18) {
                    endChoices(actions, showsTitles: true)
                }
                if let sourceName = actions.sourceName {
                    Text("From “\(sourceName)”")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .padding(20)

            HStack(spacing: 10) {
                endChoices(actions, showsTitles: false)
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func endChoices(_ actions: VideoEndActions, showsTitles: Bool) -> some View {
        endChoice("Replay", systemImage: "arrow.counterclockwise", showsTitle: showsTitles, action: onResume)
        endChoice("Next", systemImage: "forward.end.fill", isPrimary: true, showsTitle: showsTitles, action: actions.onNext)
        endChoice("Random", systemImage: "shuffle", showsTitle: showsTitles, action: actions.onRandom)
    }

    private func endChoice(
        _ title: LocalizedStringResource,
        systemImage: String,
        isPrimary: Bool = false,
        showsTitle: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isPrimary ? .black : .white)
                    .frame(width: 48, height: 48)
                    .background(isPrimary ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.2)), in: Circle())
                if showsTitle {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var statusContent: some View {
        VStack(spacing: 12) {
            if showsProgress {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.5)
                    .tint(.white)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
            }

            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)

            if isActionable {
                Button(action: onResume) {
                    Label(actionTitle, systemImage: actionIconName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
    }

    private var showsProgress: Bool {
        switch status {
        case .preparing, .seeking, .buffering:
            return true
        case .ended, .interrupted:
            return false
        }
    }

    private var isActionable: Bool {
        status == .ended || status == .interrupted
    }

    private var message: LocalizedStringResource {
        switch status {
        case .preparing:
            return "Preparing video..."
        case .seeking:
            return "Seeking..."
        case .buffering:
            return "Waiting for video data..."
        case .ended:
            return "End of video"
        case .interrupted:
            return "Playback interrupted"
        }
    }

    private var iconName: String {
        status == .ended ? "checkmark.circle" : "exclamationmark.triangle"
    }

    private var actionTitle: LocalizedStringResource {
        status == .ended ? "Replay" : "Resume"
    }

    private var actionIconName: String {
        status == .ended ? "arrow.counterclockwise" : "play.fill"
    }
}

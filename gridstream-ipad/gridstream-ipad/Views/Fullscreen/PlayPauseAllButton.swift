//
//  PlayPauseAllButton.swift
//  gridstream-ipad
//
//  Toggle button to pause/resume all video playback in fullscreen mode.
//

import SwiftUI

struct PlayPauseAllButton: View {
    @Binding var isPaused: Bool
    let onPauseAll: () -> Void
    let onPlayAll: () -> Void

    private let buttonSize: CGFloat = 44
    private let iconSize: CGFloat = 18

    var body: some View {
        Button(action: togglePlayback) {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.5))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPaused ? "Play all" : "Pause all")
        .accessibilityHint(isPaused ? "Resumes all videos" : "Pauses all videos")
    }

    private func togglePlayback() {
        if isPaused {
            onPlayAll()
        } else {
            onPauseAll()
        }
        isPaused.toggle()
    }
}

#Preview("Paused State") {
    ZStack {
        Color.black

        PlayPauseAllButton(
            isPaused: .constant(true),
            onPauseAll: {},
            onPlayAll: {}
        )
    }
    .frame(width: 100, height: 100)
}

#Preview("Playing State") {
    ZStack {
        Color.black

        PlayPauseAllButton(
            isPaused: .constant(false),
            onPauseAll: {},
            onPlayAll: {}
        )
    }
    .frame(width: 100, height: 100)
}

//
//  GlobalPlaybackControls.swift
//  gridstream-ipad
//

import SwiftUI

struct GlobalPlaybackControls: View {
    let onPauseAll: () -> Void
    let onPlayAll: () -> Void

    var body: some View {
        TopBarGroup {
            Button(action: onPauseAll) {
                Image(systemName: "pause.fill")
            }
            .buttonStyle(TopBarGroupButtonStyle())
            .accessibilityLabel("Pause All")

            Button(action: onPlayAll) {
                Image(systemName: "play.fill")
            }
            .buttonStyle(TopBarGroupButtonStyle())
            .accessibilityLabel("Play All")
        }
    }
}

#Preview {
    GlobalPlaybackControls(
        onPauseAll: {},
        onPlayAll: {}
    )
    .padding()
    .background(Brand.barGradient)
}

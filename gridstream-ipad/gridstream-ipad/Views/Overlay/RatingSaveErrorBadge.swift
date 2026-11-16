//
//  RatingSaveErrorBadge.swift
//  gridstream-ipad
//

import SwiftUI

/// Shown briefly under the rating overlay when a rating could not be saved
/// and the optimistic change was rolled back.
struct RatingSaveErrorBadge: View {
    var body: some View {
        Label("Rating not saved", systemImage: "exclamationmark.triangle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.red.opacity(0.85), in: Capsule())
            .transition(.opacity)
            .accessibilityLabel("Rating could not be saved")
    }
}

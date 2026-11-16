//
//  HeartRatingView.swift
//  gridstream-ipad
//

import SwiftUI

/// Reusable heart rating view that displays 0-10 hearts with filled/empty states.
/// Used in Content Library for global ratings and per-tag ratings,
/// as well as in the playback overlay for rating during video playback.
struct HeartRatingView: View {
    @Binding var rating: Int
    let maxRating: Int
    let size: HeartRatingSize
    var isEditable: Bool = true
    var onRatingChanged: ((Int) -> Void)?

    init(
        rating: Binding<Int>,
        maxRating: Int = 10,
        size: HeartRatingSize = .large,
        isEditable: Bool = true,
        onRatingChanged: ((Int) -> Void)? = nil
    ) {
        self._rating = rating
        self.maxRating = maxRating
        self.size = size
        self.isEditable = isEditable
        self.onRatingChanged = onRatingChanged
    }

    var body: some View {
        HStack(spacing: size.spacing) {
            ForEach(1...maxRating, id: \.self) { index in
                heartButton(for: index)
            }
        }
    }

    @ViewBuilder
    private func heartButton(for index: Int) -> some View {
        let isFilled = index <= rating

        Button {
            if isEditable {
                setRating(index)
            }
        } label: {
            Image(systemName: isFilled ? "heart.fill" : "heart")
                .font(.system(size: size.heartSize))
                .foregroundStyle(isFilled ? .red : .orange.opacity(0.7))
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
        .accessibilityLabel("Rate \(index) of \(maxRating) hearts")
        .accessibilityAddTraits(isFilled ? .isSelected : [])
    }

    private func setRating(_ newRating: Int) {
        // Tapping the same rating toggles it off (sets to 0)
        let effectiveRating = (rating == newRating) ? 0 : newRating
        rating = effectiveRating
        onRatingChanged?(effectiveRating)
    }
}

// MARK: - Compact Heart Rating View

/// A more compact version that shows filled hearts only with a count,
/// suitable for use in thumbnail overlays.
struct CompactHeartRatingView: View {
    let rating: Int
    let maxRating: Int

    init(rating: Int, maxRating: Int = 10) {
        self.rating = rating
        self.maxRating = maxRating
    }

    var body: some View {
        if rating > 0 {
            HStack(spacing: 2) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
                Text("\(rating)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.6))
            .clipShape(Capsule())
        }
    }
}

// MARK: - Previews

#Preview("Large Rating - 7/10") {
    struct PreviewWrapper: View {
        @State private var rating = 7

        var body: some View {
            VStack(spacing: 20) {
                Text("Rating: \(rating)/10")
                    .font(.headline)

                HeartRatingView(
                    rating: $rating,
                    maxRating: 10,
                    size: .large
                )
            }
            .padding()
        }
    }

    return PreviewWrapper()
}

#Preview("Small Rating - 5/10") {
    struct PreviewWrapper: View {
        @State private var rating = 5

        var body: some View {
            VStack(spacing: 20) {
                Text("Per-tag Rating: \(rating)/10")
                    .font(.subheadline)

                HeartRatingView(
                    rating: $rating,
                    maxRating: 10,
                    size: .small
                )
            }
            .padding()
        }
    }

    return PreviewWrapper()
}

#Preview("Read-only Rating") {
    struct PreviewWrapper: View {
        @State private var rating = 8

        var body: some View {
            HeartRatingView(
                rating: $rating,
                maxRating: 10,
                size: .large,
                isEditable: false
            )
            .padding()
        }
    }

    return PreviewWrapper()
}

#Preview("Compact Rating") {
    VStack(spacing: 20) {
        CompactHeartRatingView(rating: 8)
        CompactHeartRatingView(rating: 0)
        CompactHeartRatingView(rating: 10)
    }
    .padding()
    .background(.gray)
}

#Preview("Empty Rating") {
    struct PreviewWrapper: View {
        @State private var rating = 0

        var body: some View {
            VStack(spacing: 20) {
                Text("No rating yet")
                    .font(.headline)

                HeartRatingView(
                    rating: $rating,
                    maxRating: 10,
                    size: .large
                )
            }
            .padding()
        }
    }

    return PreviewWrapper()
}

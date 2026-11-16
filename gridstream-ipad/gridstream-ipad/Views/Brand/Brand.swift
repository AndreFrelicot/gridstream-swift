//
//  Brand.swift
//  gridstream-ipad
//
//  The app icon's colours and mark, shared by the onboarding, the top bar
//  and the empty tile.
//

import SwiftUI

enum Brand {
    static let amber = Color(red: 0.96, green: 0.62, blue: 0.04)
    static let orange = Color(red: 0.92, green: 0.35, blue: 0.05)
    static let ember = Color(red: 0.70, green: 0.14, blue: 0.12)
    /// Orange dark enough for text on white.
    static let deep = Color(red: 0.78, green: 0.25, blue: 0.05)

    /// The icon's background.
    static let gradient = LinearGradient(
        colors: [amber, orange],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// A deeper run of the same colours for surfaces carrying white text.
    static let barGradient = LinearGradient(
        colors: [
            Color(red: 0.95, green: 0.50, blue: 0.05),
            orange,
            Color(red: 0.82, green: 0.22, blue: 0.09)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

/// The icon's mark: four tiles with a play triangle cut through them,
/// drawn in the current foreground style.
struct GridStreamGlyph: View {
    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            let gap = side * 0.07
            let cell = (side - gap) / 2
            let radius = cell * 0.2

            for row in 0..<2 {
                for column in 0..<2 {
                    let rect = CGRect(
                        x: origin.x + CGFloat(column) * (cell + gap),
                        y: origin.y + CGFloat(row) * (cell + gap),
                        width: cell,
                        height: cell
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: radius, style: .continuous),
                        with: .foreground
                    )
                }
            }

            var triangle = Path()
            triangle.move(to: CGPoint(x: origin.x + side * 0.33, y: origin.y + side * 0.21))
            triangle.addLine(to: CGPoint(x: origin.x + side * 0.81, y: origin.y + side * 0.5))
            triangle.addLine(to: CGPoint(x: origin.x + side * 0.33, y: origin.y + side * 0.79))
            triangle.closeSubpath()

            context.blendMode = .destinationOut
            context.fill(triangle, with: .color(.black))
            context.stroke(
                triangle,
                with: .color(.black),
                style: StrokeStyle(lineWidth: side * 0.06, lineJoin: .round)
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The app icon: the mark in white on the warm gradient.
struct BrandIcon: View {
    var size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(Brand.gradient)
            .overlay {
                GridStreamGlyph()
                    .foregroundStyle(.white)
                    .padding(size * 0.18)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 24) {
        BrandIcon(size: 120)
        BrandIcon(size: 44)
        GridStreamGlyph()
            .foregroundStyle(Brand.orange)
            .frame(width: 80)
    }
    .padding()
}

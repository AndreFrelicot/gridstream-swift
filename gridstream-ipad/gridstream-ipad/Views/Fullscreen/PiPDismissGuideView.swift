//
//  PiPDismissGuideView.swift
//  gridstream-ipad
//
//  Subtle visual guide overlay shown during the 2-finger diagonal dismiss gesture.
//  Displays a corner chevron and directional gradient to indicate swipe direction.
//

import SwiftUI

struct PiPDismissGuideView: View {
    let progress: CGFloat       // 0 = not started, 1 = fully dismissed
    let corner: DiagonalCorner  // which corner the gesture is heading toward
    let isDismissed: Bool       // true if PiPs are already dismissed (showing restore guide)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Edge gradient from target corner
                cornerGradient(size: geometry.size)
                    .opacity(Double(min(progress, 1.0)) * 0.15)

                // Corner chevron indicator
                cornerChevron
                    .position(chevronPosition(size: geometry.size))
                    .opacity(Double(min(progress, 1.0)) * 0.4)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Corner Gradient

    private func cornerGradient(size: CGSize) -> some View {
        let startPoint = gradientStartPoint
        let endPoint = gradientEndPoint

        return Rectangle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.3),
                        Color.clear
                    ]),
                    startPoint: startPoint,
                    endPoint: endPoint
                )
            )
    }

    private var gradientStartPoint: UnitPoint {
        switch corner {
        case .topLeft:     return .topLeading
        case .topRight:    return .topTrailing
        case .bottomLeft:  return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }

    private var gradientEndPoint: UnitPoint {
        switch corner {
        case .topLeft:     return .bottomTrailing
        case .topRight:    return .bottomLeading
        case .bottomLeft:  return .topTrailing
        case .bottomRight: return .topLeading
        }
    }

    // MARK: - Corner Chevron

    private var cornerChevron: some View {
        let rotation = chevronRotation

        return Image(systemName: isDismissed ? "chevron.compact.backward.2" : "chevron.compact.forward.2")
            .font(.system(size: 28, weight: .semibold))
            .foregroundColor(.white)
            .rotationEffect(.degrees(rotation))
    }

    private var chevronRotation: Double {
        switch corner {
        case .topLeft:     return -135
        case .topRight:    return -45
        case .bottomLeft:  return 135
        case .bottomRight: return 45
        }
    }

    private func chevronPosition(size: CGSize) -> CGPoint {
        let inset: CGFloat = 40
        switch corner {
        case .topLeft:     return CGPoint(x: inset, y: inset)
        case .topRight:    return CGPoint(x: size.width - inset, y: inset)
        case .bottomLeft:  return CGPoint(x: inset, y: size.height - inset)
        case .bottomRight: return CGPoint(x: size.width - inset, y: size.height - inset)
        }
    }
}

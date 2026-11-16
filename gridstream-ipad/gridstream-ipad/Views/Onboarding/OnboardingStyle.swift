//
//  OnboardingStyle.swift
//  gridstream-ipad
//
//  Shared look of the onboarding, demo, "Connect my Mac" and PIN screens:
//  the warm gradient of the app icon, a card, and the two button styles.
//

import SwiftUI

struct OnboardingBackground: View {
    var body: some View {
        // The icon's amber-to-red gradient, deepened toward the bottom so
        // white text stays readable.
        LinearGradient(
            colors: [Brand.amber, Brand.orange, Brand.ember],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

/// Error and warning text on the warm background.
extension Color {
    static let onboardingAlert = Color(red: 1, green: 0.95, blue: 0.75)
}

/// A rounded translucent panel holding a screen's content.
struct OnboardingCard<Content: View>: View {
    var maxWidth: CGFloat = 560
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(32)
            .frame(maxWidth: maxWidth)
            .background(.black.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
    }
}

/// White filled button, the main action of a screen.
struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(configuration.isPressed ? 0.8 : 1))
            .foregroundStyle(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Translucent button, the secondary action of a screen.
struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(configuration.isPressed ? 0.2 : 0.12))
            .foregroundStyle(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension View {
    /// Small uppercase caption above a screen title.
    func onboardingEyebrow() -> some View {
        font(.caption)
            .foregroundStyle(.white.opacity(0.7))
            .textCase(.uppercase)
    }

    func onboardingTitle() -> some View {
        font(.system(size: 34, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
    }

    func onboardingBody() -> some View {
        font(.body)
            .foregroundStyle(.white.opacity(0.78))
    }
}

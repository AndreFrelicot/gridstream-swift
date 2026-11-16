//
//  TopBarStyle.swift
//  gridstream-ipad
//
//  The pieces of the orange top bar: white capsule buttons, groups of
//  icon buttons sharing one capsule, and the bar's background.
//

import SwiftUI

/// A white-on-orange capsule button. The prominent one is filled white and
/// marks the bar's main action.
struct TopBarButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        TopBarButtonBody(configuration: configuration, prominent: prominent)
    }
}

private struct TopBarButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(prominent ? Brand.deep : Color.white)
            .padding(.horizontal, 14)
            .frame(minWidth: 44, minHeight: 42)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var fill: Color {
        if prominent {
            return .white.opacity(configuration.isPressed ? 0.8 : 1)
        }
        return .white.opacity(configuration.isPressed ? 0.3 : 0.17)
    }
}

/// Several icon buttons sharing one capsule.
struct TopBarGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 2) {
            content
        }
        .padding(3)
        .background(Capsule().fill(.white.opacity(0.17)))
        .fixedSize()
    }
}

/// An icon button inside a `TopBarGroup`; a selected one is filled white.
struct TopBarGroupButtonStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        TopBarGroupButtonBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct TopBarGroupButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isSelected ? Brand.deep : Color.white)
            .frame(width: 40, height: 36)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    private var fill: Color {
        if isSelected { return .white }
        return .white.opacity(configuration.isPressed ? 0.2 : 0)
    }
}

/// The bar's rounded orange panel.
struct TopBarBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Brand.barGradient)
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: Brand.ember.opacity(0.35), radius: 18, y: 8)
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
}

#Preview {
    HStack(spacing: 10) {
        Button {} label: { Label("Library", systemImage: "rectangle.stack") }
            .buttonStyle(TopBarButtonStyle(prominent: true))
        Button {} label: { Label("Shuffle All", systemImage: "shuffle") }
            .buttonStyle(TopBarButtonStyle())
        TopBarGroup {
            Button {} label: { Image(systemName: "pause.fill") }
                .buttonStyle(TopBarGroupButtonStyle())
            Button {} label: { Image(systemName: "play.fill") }
                .buttonStyle(TopBarGroupButtonStyle(isSelected: true))
        }
    }
    .padding(8)
    .background(TopBarBackground())
    .padding()
}

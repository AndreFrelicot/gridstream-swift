//
//  PiPLayoutMemoryButton.swift
//  gridstream-ipad
//

import SwiftUI
import UIKit

/// Tap to turn layout memory on or off; press and hold for a menu that puts
/// the floating windows back in their default place, for this video or for
/// all of them.
struct PiPLayoutMemoryButton: View {
    @Binding var isActive: Bool
    var action: () -> Void
    var onResetCurrentLayout: () -> Void = {}
    var onResetAllLayouts: () -> Void = {}
    /// Called while the reset menu is open, so the controls holding the
    /// button stay on screen instead of auto-hiding and closing it.
    var onMenuOpen: (() -> Void)? = nil
    var onMenuClose: (() -> Void)? = nil

    private let buttonSize: CGFloat = 44
    private let iconSize: CGFloat = 18

    private var menu: UIMenu {
        let actions: [UIAction]
        if isActive {
            actions = [
                UIAction(
                    title: String(localized: "Reset This Video's Layout"),
                    image: UIImage(systemName: "arrow.counterclockwise"),
                    attributes: .destructive
                ) { _ in onResetCurrentLayout() },
                UIAction(
                    title: String(localized: "Reset All Videos' Layouts"),
                    image: UIImage(systemName: "arrow.counterclockwise.circle"),
                    attributes: .destructive
                ) { _ in onResetAllLayouts() }
            ]
        } else {
            actions = [
                UIAction(
                    title: String(localized: "Reset Window Positions"),
                    image: UIImage(systemName: "arrow.counterclockwise"),
                    attributes: .destructive
                ) { _ in onResetCurrentLayout() }
            ]
        }
        return UIMenu(title: String(localized: "Reset Window Positions"), options: .displayInline, children: actions)
    }

    var body: some View {
        MenuCircleButton(
            systemImage: isActive ? "rectangle.on.rectangle.circle.fill" : "rectangle.on.rectangle.circle",
            iconSize: iconSize,
            foregroundColor: isActive ? .black : .white,
            backgroundColor: isActive ? .systemCyan : UIColor.black.withAlphaComponent(0.5),
            menu: menu,
            primaryAction: action,
            accessibilityLabel: String(localized: "PiP Layout Memory"),
            accessibilityValue: isActive ? String(localized: "On") : String(localized: "Off"),
            accessibilityHint: String(localized: "Tap to remember window positions for each fullscreen video. Long press to reset window positions."),
            onMenuOpen: onMenuOpen,
            onMenuClose: onMenuClose
        )
        .frame(width: buttonSize, height: buttonSize)
    }
}

#Preview("Inactive") {
    ZStack {
        Color.black

        PiPLayoutMemoryButton(isActive: .constant(false), action: {})
    }
    .frame(width: 100, height: 100)
}

#Preview("Active") {
    ZStack {
        Color.black

        PiPLayoutMemoryButton(isActive: .constant(true), action: {})
    }
    .frame(width: 100, height: 100)
}

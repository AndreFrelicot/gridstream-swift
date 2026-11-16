//
//  MenuCircleButton.swift
//  gridstream-ipad
//

import SwiftUI
import UIKit

/// A round icon button with a native menu that reports when the menu opens
/// and closes. The controls holding these buttons auto-hide, which removes
/// the button and closes its menu, so they must be held while it is open; a
/// SwiftUI `Menu` cannot tell (its content's onAppear fires only the first
/// time, onDisappear never), UIButton can.
struct MenuCircleButton: UIViewRepresentable {
    var systemImage: String
    var iconSize: CGFloat
    var foregroundColor: UIColor
    var backgroundColor: UIColor
    var menu: UIMenu
    /// Run by a tap. Without it a tap opens the menu; with it the menu opens
    /// on a long press.
    var primaryAction: (() -> Void)?
    var accessibilityLabel: String
    var accessibilityValue: String?
    var accessibilityHint: String?
    var onMenuOpen: (() -> Void)?
    var onMenuClose: (() -> Void)?

    func makeUIView(context: Context) -> MenuButton {
        let button = MenuButton(configuration: .plain())
        button.addAction(UIAction { [weak button] _ in button?.primaryAction?() }, for: .primaryActionTriggered)
        return button
    }

    func updateUIView(_ button: MenuButton, context: Context) {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: systemImage)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)
        configuration.baseForegroundColor = foregroundColor
        configuration.background.backgroundColor = backgroundColor
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero
        button.configuration = configuration

        button.menu = menu
        button.showsMenuAsPrimaryAction = primaryAction == nil
        button.primaryAction = primaryAction
        button.onMenuOpen = onMenuOpen
        button.onMenuClose = onMenuClose

        button.accessibilityLabel = accessibilityLabel
        button.accessibilityValue = accessibilityValue
        button.accessibilityHint = accessibilityHint
    }

    final class MenuButton: UIButton {
        var primaryAction: (() -> Void)?
        var onMenuOpen: (() -> Void)?
        var onMenuClose: (() -> Void)?

        override func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            willDisplayMenuFor configuration: UIContextMenuConfiguration,
            animator: (any UIContextMenuInteractionAnimating)?
        ) {
            super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
            onMenuOpen?()
        }

        override func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            willEndFor configuration: UIContextMenuConfiguration,
            animator: (any UIContextMenuInteractionAnimating)?
        ) {
            super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
            onMenuClose?()
        }
    }
}

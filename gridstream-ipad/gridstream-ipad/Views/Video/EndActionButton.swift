//
//  EndActionButton.swift
//  gridstream-ipad
//

import SwiftUI
import UIKit

/// Chooses what the tile does when its video ends: stop, loop, play the next
/// video or a random one. Highlighted when it is not the default (stop).
struct EndActionButton: View {
    let endAction: TileEndAction
    let onChange: (TileEndAction) -> Void
    var isCompact: Bool = false
    /// Called while the menu is open, so the controls holding the button
    /// stay on screen instead of auto-hiding and closing it.
    var onMenuOpen: (() -> Void)? = nil
    var onMenuClose: (() -> Void)? = nil

    private var buttonSize: CGFloat { isCompact ? 32 : 44 }
    private var iconSize: CGFloat { isCompact ? 14 : 18 }

    private var menu: UIMenu {
        let actions = TileEndAction.allCases.map { action in
            UIAction(
                title: String(localized: action.title),
                image: UIImage(systemName: action.systemImage),
                state: action == endAction ? .on : .off
            ) { _ in onChange(action) }
        }
        return UIMenu(title: String(localized: "When This Video Ends"), options: .displayInline, children: actions)
    }

    var body: some View {
        MenuCircleButton(
            systemImage: endAction.systemImage,
            iconSize: iconSize,
            foregroundColor: .white,
            backgroundColor: endAction == .stop ? UIColor.black.withAlphaComponent(0.5) : .systemOrange,
            menu: menu,
            accessibilityLabel: String(localized: "When this video ends"),
            accessibilityValue: String(localized: endAction.title),
            onMenuOpen: onMenuOpen,
            onMenuClose: onMenuClose
        )
        .frame(width: buttonSize, height: buttonSize)
    }
}

#Preview {
    HStack {
        EndActionButton(endAction: .stop, onChange: { _ in })
        EndActionButton(endAction: .next, onChange: { _ in })
        EndActionButton(endAction: .shuffle, onChange: { _ in }, isCompact: true)
    }
    .padding()
    .background(Color.gray)
}

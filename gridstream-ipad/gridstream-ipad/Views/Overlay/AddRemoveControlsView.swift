//
//  AddRemoveControlsView.swift
//  gridstream-ipad
//

import SwiftUI

/// The tile count between a remove and an add button.
struct AddRemoveControlsView: View {
    let tileCount: Int
    let canAdd: Bool
    let canRemove: Bool
    let onAdd: () -> Void
    let onRemove: () -> Void

    var body: some View {
        TopBarGroup {
            Button(action: onRemove) {
                Image(systemName: "minus")
            }
            .buttonStyle(TopBarGroupButtonStyle())
            .disabled(!canRemove)
            .accessibilityLabel("Remove Tile")

            HStack(spacing: 5) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(0.75)
                Text(verbatim: "\(tileCount)")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(.white)
            .frame(minWidth: 34)
            .accessibilityHidden(true)

            Button(action: onAdd) {
                Image(systemName: "plus")
            }
            .buttonStyle(TopBarGroupButtonStyle())
            .disabled(!canAdd)
            .accessibilityLabel("Add Tile")
        }
        .animation(.snappy, value: tileCount)
    }
}

#Preview {
    VStack(spacing: 16) {
        AddRemoveControlsView(tileCount: 4, canAdd: true, canRemove: true, onAdd: {}, onRemove: {})
        AddRemoveControlsView(tileCount: 1, canAdd: true, canRemove: false, onAdd: {}, onRemove: {})
        AddRemoveControlsView(tileCount: 12, canAdd: false, canRemove: true, onAdd: {}, onRemove: {})
    }
    .padding()
    .background(Brand.barGradient)
}

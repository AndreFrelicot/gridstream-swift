//
//  OrientationToggle.swift
//  gridstream-ipad
//

import SwiftUI

struct OrientationToggle: View {
    @Bindable var gridState: GridState

    var body: some View {
        TopBarGroup {
            ForEach(LayoutOrientation.allCases, id: \.self) { orientation in
                Button {
                    gridState.setOrientation(orientation)
                } label: {
                    Image(systemName: orientation.sfSymbolName)
                }
                .buttonStyle(TopBarGroupButtonStyle(isSelected: gridState.orientation == orientation))
                .accessibilityLabel(orientation.accessibilityName)
                .accessibilityAddTraits(gridState.orientation == orientation ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Layout Orientation")
        .accessibilityHint("Switch between horizontal and vertical layout orientation")
    }
}

private extension LayoutOrientation {
    var accessibilityName: LocalizedStringKey {
        switch self {
        case .horizontal: "Horizontal"
        case .vertical: "Vertical"
        }
    }
}

#Preview {
    let gridState = GridState()
    return OrientationToggle(gridState: gridState)
        .padding()
        .background(Brand.barGradient)
}

#Preview("Vertical Selected") {
    let gridState = GridState()
    gridState.setOrientation(.vertical)
    return OrientationToggle(gridState: gridState)
        .padding()
        .background(Brand.barGradient)
}

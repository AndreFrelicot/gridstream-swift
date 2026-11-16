//
//  DividerOverlayView.swift
//  gridstream-ipad
//

import SwiftUI

struct DividerOverlayView: View {
    let dividers: [DividerPosition]
    let containerSize: CGSize
    let onDividerDrag: (Int, CGFloat) -> Void

    @State private var draggingDividerIndex: Int?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(dividers.enumerated()), id: \.element.id) { index, divider in
                DividerView(
                    divider: divider,
                    onDrag: { delta in
                        onDividerDrag(index, delta)
                    },
                    isDragging: isDraggingBinding(for: index)
                )
                .position(dividerCenterPosition(for: divider))
                .allowsHitTesting(draggingDividerIndex == nil || draggingDividerIndex == index)
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
    }

    // MARK: - Position Calculation

    private func dividerCenterPosition(for divider: DividerPosition) -> CGPoint {
        switch divider.axis {
        case .vertical:
            // Vertical divider: position at x = divider.position, centered vertically
            return CGPoint(x: divider.position, y: divider.length / 2)
        case .horizontal:
            // Horizontal divider: position at y = divider.position, centered horizontally
            return CGPoint(x: divider.length / 2, y: divider.position)
        }
    }

    // MARK: - Dragging State Binding

    private func isDraggingBinding(for index: Int) -> Binding<Bool> {
        Binding<Bool>(
            get: { draggingDividerIndex == index },
            set: { isDragging in
                if isDragging {
                    draggingDividerIndex = index
                } else if draggingDividerIndex == index {
                    draggingDividerIndex = nil
                }
            }
        )
    }
}

// MARK: - Previews

#Preview("Single Vertical Divider") {
    let dividers = [
        DividerPosition(
            axis: .vertical,
            position: 300,
            affectedTileIndices: [0, 1],
            length: 400
        )
    ]

    return DividerOverlayView(
        dividers: dividers,
        containerSize: CGSize(width: 600, height: 400),
        onDividerDrag: { index, delta in
            print("Divider \(index) dragged by \(delta)")
        }
    )
    .background(Color.gray.opacity(0.1))
}

#Preview("Single Horizontal Divider") {
    let dividers = [
        DividerPosition(
            axis: .horizontal,
            position: 200,
            affectedTileIndices: [0, 2],
            length: 600
        )
    ]

    return DividerOverlayView(
        dividers: dividers,
        containerSize: CGSize(width: 600, height: 400),
        onDividerDrag: { index, delta in
            print("Divider \(index) dragged by \(delta)")
        }
    )
    .background(Color.gray.opacity(0.1))
}

#Preview("Multiple Dividers (1+2 Layout)") {
    // Simulating a 1+2 layout with one vertical and one horizontal divider
    let dividers = [
        DividerPosition(
            axis: .vertical,
            position: 400,
            affectedTileIndices: [0, 1, 2],
            length: 400
        ),
        DividerPosition(
            axis: .horizontal,
            position: 200,
            affectedTileIndices: [1, 2],
            length: 200
        )
    ]

    return DividerOverlayView(
        dividers: dividers,
        containerSize: CGSize(width: 600, height: 400),
        onDividerDrag: { index, delta in
            print("Divider \(index) dragged by \(delta)")
        }
    )
    .background(Color.gray.opacity(0.1))
}

#Preview("Grid Layout Dividers (2x2)") {
    // Simulating a 2x2 grid with one vertical and one horizontal divider
    let dividers = [
        DividerPosition(
            axis: .vertical,
            position: 300,
            affectedTileIndices: [0, 1, 2, 3],
            length: 400
        ),
        DividerPosition(
            axis: .horizontal,
            position: 200,
            affectedTileIndices: [0, 1, 2, 3],
            length: 600
        )
    ]

    return DividerOverlayView(
        dividers: dividers,
        containerSize: CGSize(width: 600, height: 400),
        onDividerDrag: { index, delta in
            print("Divider \(index) dragged by \(delta)")
        }
    )
    .background(Color.gray.opacity(0.1))
}

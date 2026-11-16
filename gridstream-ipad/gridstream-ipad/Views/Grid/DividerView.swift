//
//  DividerView.swift
//  gridstream-ipad
//

import SwiftUI

struct DividerView: View {
    let divider: DividerPosition
    let onDrag: (CGFloat) -> Void
    @Binding var isDragging: Bool

    // Visual constants
    private let normalLineWidth: CGFloat = 2
    private let draggingLineWidth: CGFloat = 4
    private let normalOpacity: Double = 0.3
    private let draggingOpacity: Double = 0.6
    private let hitAreaSize: CGFloat = 44

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            dividerLine
                .position(dividerPosition(in: geometry.size))
                .gesture(dragGesture)
                .contentShape(hitAreaShape)
        }
        .frame(
            width: divider.axis == .vertical ? hitAreaSize : nil,
            height: divider.axis == .horizontal ? hitAreaSize : nil
        )
    }

    // MARK: - Divider Line

    private var dividerLine: some View {
        Group {
            switch divider.axis {
            case .vertical:
                Rectangle()
                    .fill(Color.secondary.opacity(isDragging ? draggingOpacity : normalOpacity))
                    .frame(width: isDragging ? draggingLineWidth : normalLineWidth, height: divider.length)
            case .horizontal:
                Rectangle()
                    .fill(Color.secondary.opacity(isDragging ? draggingOpacity : normalOpacity))
                    .frame(width: divider.length, height: isDragging ? draggingLineWidth : normalLineWidth)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isDragging)
    }

    // MARK: - Hit Area Shape

    private var hitAreaShape: some Shape {
        Rectangle()
    }

    // MARK: - Position Calculation

    private func dividerPosition(in size: CGSize) -> CGPoint {
        switch divider.axis {
        case .vertical:
            return CGPoint(x: hitAreaSize / 2, y: divider.length / 2)
        case .horizontal:
            return CGPoint(x: divider.length / 2, y: hitAreaSize / 2)
        }
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isDragging = true
                let delta: CGFloat
                switch divider.axis {
                case .vertical:
                    delta = value.translation.width
                case .horizontal:
                    delta = value.translation.height
                }
                // Call onDrag with the delta for real-time updates
                onDrag(delta - dragOffset)
                dragOffset = delta
            }
            .onEnded { _ in
                isDragging = false
                dragOffset = 0
            }
    }
}

// MARK: - Previews

#Preview("Vertical Divider - Normal") {
    DividerView(
        divider: DividerPosition(
            axis: .vertical,
            position: 200,
            affectedTileIndices: [0, 1],
            length: 400
        ),
        onDrag: { delta in
            print("Drag delta: \(delta)")
        },
        isDragging: .constant(false)
    )
    .frame(width: 44, height: 400)
    .background(Color.gray.opacity(0.1))
}

#Preview("Vertical Divider - Dragging") {
    DividerView(
        divider: DividerPosition(
            axis: .vertical,
            position: 200,
            affectedTileIndices: [0, 1],
            length: 400
        ),
        onDrag: { delta in
            print("Drag delta: \(delta)")
        },
        isDragging: .constant(true)
    )
    .frame(width: 44, height: 400)
    .background(Color.gray.opacity(0.1))
}

#Preview("Horizontal Divider - Normal") {
    DividerView(
        divider: DividerPosition(
            axis: .horizontal,
            position: 150,
            affectedTileIndices: [0, 2],
            length: 600
        ),
        onDrag: { delta in
            print("Drag delta: \(delta)")
        },
        isDragging: .constant(false)
    )
    .frame(width: 600, height: 44)
    .background(Color.gray.opacity(0.1))
}

#Preview("Horizontal Divider - Dragging") {
    DividerView(
        divider: DividerPosition(
            axis: .horizontal,
            position: 150,
            affectedTileIndices: [0, 2],
            length: 600
        ),
        onDrag: { delta in
            print("Drag delta: \(delta)")
        },
        isDragging: .constant(true)
    )
    .frame(width: 600, height: 44)
    .background(Color.gray.opacity(0.1))
}

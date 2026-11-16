//
//  ListMembershipChips.swift
//  gridstream-ipad
//

import GridStreamAPI
import SwiftUI

/// A wrapping row of chips showing every smart list and simple list the current
/// video belongs to. Mirrors the membership chips on the web app's video cards.
/// Reuses `SmartListBadge` for styling (its icon already distinguishes smart vs
/// simple lists). Both membership arrays are expected to be pre-filtered to the
/// lists that actually contain the video.
struct ListMembershipChips: View {
    let smartLists: [SmartListInfo]
    let simpleLists: [SimpleListDTO]
    var isCompact: Bool = false

    var body: some View {
        FlowLayout(spacing: isCompact ? 4 : 6) {
            ForEach(smartLists, id: \.id) { list in
                SmartListBadge(name: list.name, isSmartList: true)
            }
            ForEach(simpleLists, id: \.id) { list in
                SmartListBadge(name: list.name, isSmartList: false)
            }
        }
    }
}

/// Minimal left-aligned flow layout that wraps its subviews onto new rows when
/// they would overflow the proposed width. Used for the membership chip row so a
/// video in many lists never spills outside the tile.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                maxRowWidth = max(maxRowWidth, x - spacing)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        maxRowWidth = max(maxRowWidth, x - spacing)
        return CGSize(width: maxRowWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

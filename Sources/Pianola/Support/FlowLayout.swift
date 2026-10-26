import SwiftUI

/// Lays views out left to right and wraps them onto new rows, like words.
/// Each view can ask for its own gap before it with `.flowGap(_:)`, so notes
/// that were written together stay close and spaced notes stay apart.
struct FlowLayout: Layout {
    var rowSpacing: CGFloat = 8
    var defaultGap: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            for item in row.items {
                let size = subviews[item.index].sizeThatFits(.unspecified)
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size))
            }
        }
    }

    private struct Row {
        var y: CGFloat
        var height: CGFloat = 0
        var width: CGFloat = 0
        var items: [(index: Int, x: CGFloat)] = []
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row(y: 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let gap = row.items.isEmpty ? 0 : (subviews[index][FlowGapKey.self] ?? defaultGap)
            if !row.items.isEmpty && row.width + gap + size.width > width {
                let nextY = row.y + row.height + rowSpacing
                rows.append(row)
                row = Row(y: nextY)
            }
            let x = row.items.isEmpty ? 0 : row.width + gap
            row.items.append((index, x))
            row.width = x + size.width
            row.height = max(row.height, size.height)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}

private struct FlowGapKey: LayoutValueKey {
    static let defaultValue: CGFloat? = nil
}

extension View {
    /// Space before this view inside a `FlowLayout`.
    func flowGap(_ gap: CGFloat) -> some View {
        layoutValue(key: FlowGapKey.self, value: gap)
    }
}

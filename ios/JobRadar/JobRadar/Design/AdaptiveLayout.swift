import SwiftUI

// MARK: - Columns

/// Where a section goes when `OrbitColumns` has room for two columns.
enum OrbitColumn {
    /// Spans both columns, below everything placed before it.
    case full
    case leading
    case trailing
    /// Whichever column is shorter when this section is placed.
    case shorter
}

extension View {
    /// Places this section in `column` when its `OrbitColumns` shows two
    /// columns. In one column, sections keep their written order.
    func orbitColumn(_ column: OrbitColumn) -> some View {
        layoutValue(key: OrbitColumnKey.self, value: column)
    }
}

private struct OrbitColumnKey: LayoutValueKey {
    static let defaultValue = OrbitColumn.full
}

/// Stacks a screen's sections like a leading-aligned `VStack` on iPhone and in
/// narrow iPad windows. Once there's room for two phone-width columns, it lays
/// them out side by side so a large iPad's screen is put to use.
struct OrbitColumns: Layout {
    var spacing: CGFloat = AppTheme.Spacing.xl

    /// The narrowest width that gets two columns: two phone-width columns.
    static let twoColumnWidth: CGFloat = 700

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let placements = placements(for: subviews, width: proposal.width)
        return CGSize(
            width: proposal.width ?? placements.map(\.frame.maxX).max() ?? 0,
            height: placements.map(\.frame.maxY).max() ?? 0
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, placement) in zip(subviews, placements(for: subviews, width: bounds.width)) {
            subview.place(
                at: CGPoint(x: bounds.minX + placement.frame.minX, y: bounds.minY + placement.frame.minY),
                proposal: placement.proposal
            )
        }
    }

    private struct Placement {
        var frame: CGRect
        var proposal: ProposedViewSize
    }

    private func placements(for subviews: Subviews, width: CGFloat?) -> [Placement] {
        let columnCount = (width ?? 0) >= Self.twoColumnWidth ? 2 : 1
        let columnWidth = width.map { ($0 - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount) }
        // Where the next section starts in each column.
        var nextY = Array(repeating: CGFloat.zero, count: columnCount)
        var placements: [Placement] = []

        for subview in subviews {
            let column: Int?
            if columnCount == 1 {
                column = nil
            } else {
                switch subview[OrbitColumnKey.self] {
                case .full: column = nil
                case .leading: column = 0
                case .trailing: column = 1
                case .shorter: column = nextY[1] < nextY[0] ? 1 : 0
                }
            }

            if let column {
                let proposal = ProposedViewSize(width: columnWidth, height: nil)
                let size = subview.sizeThatFits(proposal)
                let x = CGFloat(column) * ((columnWidth ?? 0) + spacing)
                placements.append(Placement(
                    frame: CGRect(origin: CGPoint(x: x, y: nextY[column]), size: size),
                    proposal: proposal
                ))
                nextY[column] += size.height + spacing
            } else {
                let proposal = ProposedViewSize(width: width, height: nil)
                let size = subview.sizeThatFits(proposal)
                let y = nextY.max() ?? 0
                placements.append(Placement(frame: CGRect(origin: CGPoint(x: 0, y: y), size: size), proposal: proposal))
                nextY = nextY.map { _ in y + size.height + spacing }
            }
        }
        return placements
    }
}

// MARK: - Environment

private struct OrbitWideLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

private struct OrbitOpenSettingsKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// True when a screen fills a wide iPad area, so it can show more at once,
    /// such as extra tasks or events.
    var orbitWideLayout: Bool {
        get { self[OrbitWideLayoutKey.self] }
        set { self[OrbitWideLayoutKey.self] = newValue }
    }

    /// Opens Settings beside the iPad sidebar. `nil` where Settings opens as a
    /// sheet instead.
    var orbitOpenSettings: (() -> Void)? {
        get { self[OrbitOpenSettingsKey.self] }
        set { self[OrbitOpenSettingsKey.self] = newValue }
    }
}

// MARK: - Sheets

extension View {
    /// On iPad, sizes a short sheet to its content instead of a tall form
    /// sheet with empty space below. iPhone sheets are unaffected.
    @ViewBuilder
    func orbitFittedSheet() -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(.form.fitted(horizontal: false, vertical: true))
        } else {
            self
        }
    }
}

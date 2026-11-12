import Domain
import SwiftUI

/// Today's tracked time as one bar split by category share (spec 5.2). The
/// category list under it is its legend; small categories outside the top
/// three still get a sliver.
struct CategorySplitBar: View {
    var rails: [DaySummary.Rail]

    private let height: CGFloat = 8
    private let gap: CGFloat = 2
    /// So a minute of something still shows next to hours of something else.
    private let minWidth: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: gap) {
                ForEach(Array(zip(rails, widths(geo.size.width))), id: \.0.category) { rail, width in
                    Rectangle().fill(Color(hexString: rail.category.color)).frame(width: width)
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: height / 2))
        .accessibilityHidden(true)
    }

    /// Proportional widths with a floor, the floor's extra taken from the others.
    private func widths(_ total: CGFloat) -> [CGFloat] {
        let available = total - gap * CGFloat(max(0, rails.count - 1))
        let sum = CGFloat(rails.reduce(0) { $0 + $1.total })
        guard sum > 0, available > 0 else { return rails.map { _ in 0 } }
        let raw = rails.map { CGFloat($0.total) / sum * available }
        let small = raw.filter { $0 < minWidth }
        let floorExtra = small.reduce(0) { $0 + (minWidth - $1) }
        let large = raw.filter { $0 >= minWidth }.reduce(0, +)
        return raw.map { $0 < minWidth ? minWidth : $0 - floorExtra * ($0 / max(large, 1)) }
    }
}

import Domain
import SwiftUI

/// One thin rail per category present today, with untracked time hatched and
/// a lime now-line (spec 5.2).
struct DayBarcode: View {
    var summary: DaySummary
    /// Shown only while tracking.
    var nowLine: Int64?

    private let railHeight: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 3) {
                ForEach(summary.rails, id: \.category) { rail in
                    GeometryReader { geo in
                        railView(rail, width: geo.size.width)
                    }
                    .frame(height: railHeight)
                }
            }
            HStack {
                Text(hourLabel(summary.axis.lowerBound))
                Spacer()
                Text(hourLabel(summary.axis.upperBound))
            }
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(Theme.textMuted)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func railView(_ rail: DaySummary.Rail, width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4).fill(Theme.railFill)
            ForEach(Array(rail.bars.enumerated()), id: \.offset) { _, bar in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hexString: rail.category.color))
                    .frame(width: max(x(bar.upperBound, width) - x(bar.lowerBound, width), 6))
                    .offset(x: x(bar.lowerBound, width))
            }
            ForEach(Array(summary.untracked.enumerated()), id: \.offset) { _, gap in
                Hatch(color: Theme.border, stripe: 2, period: 5)
                    .frame(width: max(x(gap.upperBound, width) - x(gap.lowerBound, width), 2))
                    .offset(x: x(gap.lowerBound, width))
            }
            if let now = nowLine {
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: 2, height: railHeight + 4)
                    .offset(x: x(now, width) - 1)
            }
        }
    }

    private func x(_ t: Int64, _ width: CGFloat) -> CGFloat {
        let span = Double(summary.axis.upperBound - summary.axis.lowerBound)
        let f = Double(min(max(t, summary.axis.lowerBound), summary.axis.upperBound) - summary.axis.lowerBound) / span
        return CGFloat(f) * width
    }

    private func hourLabel(_ t: Int64) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(t)))
        let h = c.hour == 0 && t > summary.axis.lowerBound ? 24 : c.hour ?? 0
        return "\(h):\(String(format: "%02d", c.minute ?? 0))"
    }

    /// Spec 6: charts expose a text summary to VoiceOver.
    private var accessibilitySummary: String {
        "Today by category: " + summary.rails.map { "\($0.category.name) \(Durations.format($0.total))" }.joined(separator: ", ")
    }
}

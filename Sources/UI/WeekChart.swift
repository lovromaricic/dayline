import Domain
import SwiftUI

/// Week view body (spec 5.3): a row per day, its bar split by category in the
/// week's order and as long as the day; then the week's category totals.
struct WeekChart: View {
    @ObservedObject var vm: HomeViewModel
    let week: WeekReport

    private let labelWidth: CGFloat = 64
    private let totalWidth: CGFloat = 64

    /// The scale reaches at least 10 h, so a short week does not fill the width.
    private var scale: Int64 { max(10 * 3600, week.days.map(\.tracked).max() ?? 0) }
    private var hourMarks: [Int] { Array(stride(from: 0, through: Int(scale / 3600), by: 2)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("BY DAY").eyebrow().frame(height: 26)
            VStack(spacing: 0) {
                ForEach(week.days, id: \.dayStart) { day in row(day) }
                axis
            }
            totals
        }
    }

    private func row(_ day: WeekReport.Day) -> some View {
        Button(action: { vm.openDay(day.dayStart) }) {
            HStack(spacing: 12) {
                Text(Fmt.date(day.dayStart).formatted(.dateTime.weekday(.abbreviated)))
                    .font(.system(size: 13))
                    // Today in lime, like the NOW line in the day view.
                    .foregroundStyle(day.isToday ? Theme.accent : day.tracked > 0 ? Theme.textSecondary : Theme.textFaint)
                    .frame(width: labelWidth, alignment: .leading)
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(day.categories, id: \.category) { c in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hexString: c.category.color))
                                .frame(width: max(2, geo.size.width * Double(c.total) / Double(scale)))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(alignment: .leading) {
                        if day.tracked == 0 { RoundedRectangle(cornerRadius: 3).fill(Theme.railFill) }
                    }
                }
                .frame(height: 14)
                Text(day.tracked > 0 ? Durations.format(day.tracked) : "–")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(totalColor(day))
                    .frame(width: totalWidth, alignment: .trailing)
            }
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(day.isFuture)
        .help(day.isFuture ? "" : "Open this day")
        .accessibilityLabel(accessibilityLabel(day))
    }

    private func totalColor(_ day: WeekReport.Day) -> Color {
        guard day.tracked > 0 else { return Theme.textFaint }
        return switch day.length {
        case .normal: Theme.textMuted
        case .long: Theme.long
        case .veryLong: Theme.veryLong
        }
    }

    private func accessibilityLabel(_ day: WeekReport.Day) -> String {
        let name = Fmt.date(day.dayStart).formatted(.dateTime.weekday(.wide))
        let today = day.isToday ? ", today" : ""
        guard day.tracked > 0 else { return "\(name)\(today), nothing tracked" }
        let top = day.categories.max { $0.total < $1.total }.map { ", mostly \($0.category.name)" } ?? ""
        return "\(name)\(today), \(Durations.format(day.tracked))\(top)"
    }

    private var axis: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: labelWidth, height: 1)
            GeometryReader { geo in
                ForEach(hourMarks, id: \.self) { h in
                    Text("\(h)h").font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textFaint)
                        .fixedSize()
                        .offset(x: geo.size.width * Double(h * 3600) / Double(scale) - (h == 0 ? 0 : 8))
                }
            }
            .frame(height: 16)
            Color.clear.frame(width: totalWidth, height: 1)
        }
        .padding(.top, 6)
        .accessibilityHidden(true)
    }

    private var totals: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 32), count: 3), alignment: .leading, spacing: 12) {
            ForEach(week.categories, id: \.category) { c in
                HStack {
                    HStack(spacing: 8) {
                        Circle().fill(Color(hexString: c.category.color)).frame(width: 8, height: 8)
                        Text(c.category.name).lineLimit(1)
                    }
                    Spacer()
                    Text(Durations.format(c.total)).monospacedDigit().foregroundStyle(Theme.textMuted)
                }
                .font(.system(size: 13))
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 16)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

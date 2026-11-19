import Domain
import SwiftUI

/// Month view body: a calendar, a cell per day, brighter the more you worked,
/// with a thin bar of the day's categories; each week's total at the end of
/// its row; then the month's category totals, as in the week view.
struct MonthChart: View {
    @ObservedObject var vm: HomeViewModel
    let month: WeekReport

    private let totalWidth: CGFloat = 64
    private let cellHeight: CGFloat = 62
    private let gap: CGFloat = 5

    @State private var revealed = true
    @State private var hovered: Int64?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cal: Calendar { .current }

    /// Blank cells before the 1st, so it sits under its weekday.
    private var lead: Int {
        guard let first = month.days.first else { return 0 }
        let weekday = cal.component(.weekday, from: Fmt.date(first.dayStart))
        return (weekday - cal.firstWeekday + 7) % 7
    }

    /// The month in calendar rows of seven; nil pads the first and last.
    private var weeks: [[WeekReport.Day?]] {
        var cells: [WeekReport.Day?] = Array(repeating: nil, count: lead) + month.days.map { $0 }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    private var weekdaySymbols: [String] {
        let s = cal.shortWeekdaySymbols
        return (0..<7).map { s[(cal.firstWeekday - 1 + $0) % 7] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("BY DAY").eyebrow().frame(height: 26)
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    ForEach(weekdaySymbols, id: \.self) { d in
                        Text(d).font(.system(size: 11)).foregroundStyle(Theme.textFaint)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 2)
                    }
                    Color.clear.frame(width: totalWidth, height: 1)
                }
                .accessibilityHidden(true)
                ForEach(Array(weeks.enumerated()), id: \.offset) { i, week in
                    HStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { j in
                            if let day = week[j] { cell(day, index: i * 7 + j) } else { Color.clear.frame(height: cellHeight).frame(maxWidth: .infinity) }
                        }
                        let total = week.reduce(Int64(0)) { $0 + ($1?.tracked ?? 0) }
                        Text(total > 0 ? Durations.format(total) : "–")
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(total > 0 ? Theme.textMuted : Theme.textFaint)
                            .lineLimit(1).fixedSize()
                            .frame(width: totalWidth, alignment: .trailing)
                            .accessibilityLabel(total > 0 ? "Week total \(Durations.format(total))" : "Nothing tracked this week")
                    }
                }
            }
            totals
        }
        .onAppear(perform: grow)
        .onChange(of: vm.replay) { grow() }
    }

    /// As in the week view: only after the app has loaded something.
    private func grow() {
        guard !reduceMotion, vm.replay > 0 else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { revealed = false }
        DispatchQueue.main.async { revealed = true }
    }

    /// Brighter the more you worked, up to 8 h.
    private func fill(_ day: WeekReport.Day) -> Color {
        guard day.tracked > 0 else { return Color.white.opacity(0.025) }
        return Color.white.opacity(0.035 + min(Double(day.tracked) / (8 * 3600), 1) * 0.11)
    }

    private func cell(_ day: WeekReport.Day, index: Int) -> some View {
        let hot = hovered == day.dayStart && !day.isFuture
        let number = cal.component(.day, from: Fmt.date(day.dayStart))
        return Button(action: { vm.openDay(day.dayStart) }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(number)")
                        .foregroundStyle(day.isToday ? Theme.accent : day.isFuture ? Theme.textFaint.opacity(0.6) : Theme.textMuted)
                    Spacer(minLength: 4)
                    if day.tracked > 0 {
                        Text(Durations.format(day.tracked)).monospacedDigit()
                            .foregroundStyle(totalColor(day))
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 11))
                Spacer(minLength: 0)
                if day.tracked > 0 {
                    GeometryReader { geo in
                        HStack(spacing: 1) {
                            ForEach(day.categories, id: \.category) { c in
                                Rectangle().fill(Color(hexString: c.category.color))
                                    .frame(width: max(1, (geo.size.width - CGFloat(day.categories.count - 1)) * Double(c.total) / Double(day.tracked)))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 1.5))
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: revealed ? geo.size.width : 0)
                                .animation(.smooth(duration: 0.45).delay(Double(index) * 0.012), value: revealed)
                        }
                    }
                    .frame(height: 3)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: cellHeight, maxHeight: cellHeight, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 6).fill(day.isFuture ? .clear : fill(day)))
            .overlay {
                if day.isToday {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.accent)
                } else if day.isFuture {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                } else if hot {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.18))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { hovered = inside ? day.dayStart : (hovered == day.dayStart ? nil : hovered) }
        }
        .disabled(day.isFuture)
        .help(day.isFuture ? "" : "Open this day")
        .accessibilityLabel(accessibilityLabel(day))
    }

    private func totalColor(_ day: WeekReport.Day) -> Color {
        switch day.length {
        case .normal: Theme.textSecondary
        case .long: Theme.long
        case .veryLong: Theme.veryLong
        }
    }

    private func accessibilityLabel(_ day: WeekReport.Day) -> String {
        let name = Fmt.date(day.dayStart).formatted(.dateTime.weekday(.wide).day().month(.wide))
        let today = day.isToday ? ", today" : ""
        guard day.tracked > 0 else { return "\(name)\(today), nothing tracked" }
        let top = day.categories.max { $0.total < $1.total }.map { ", mostly \($0.category.name)" } ?? ""
        return "\(name)\(today), \(Durations.format(day.tracked))\(top)"
    }

    private var totals: some View { CategoryTotals(categories: month.categories) }
}

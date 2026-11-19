import Foundation

/// The week view (spec 5.3): one row per day, split by category, plus the
/// week's totals. Built from the same DayReports as the day view, so a day
/// adds up to the same number in both. The month view uses it too, with a
/// month of days.
public struct WeekReport: Equatable, Sendable {
    public struct CategoryTotal: Equatable, Sendable {
        public var category: ActivityCategory
        public var total: Int64
    }

    public struct Day: Equatable, Sendable {
        public var dayStart: Int64
        public var isToday: Bool
        /// After today: nothing can be tracked yet.
        public var isFuture: Bool
        public var tracked: Int64
        /// In the week's category order, so every row stacks the same way.
        public var categories: [CategoryTotal]
        public var length: DayLength
    }

    public var weekStart: Int64
    /// A calendar month rather than a week.
    public var isMonth: Bool
    /// Seven days (or a month of them), in calendar order.
    public var days: [Day]
    /// Largest first.
    public var categories: [CategoryTotal]
    public var tracked: Int64
    /// Days with anything tracked, for the average.
    public var trackedDays: Int
    public var topApps: [DayReport.AppTotal]
    public var longestFocus: DayReport.Focus?

    public var containsToday: Bool { days.contains(where: \.isToday) }
    public var average: Int64 { trackedDays == 0 ? 0 : tracked / Int64(trackedDays) }

    /// `reports` are the week's days in order; days after today may be absent.
    public init(weekStart: Int64, reports: [DayReport], dayStarts: [Int64], today: Int64, isMonth: Bool = false) {
        self.weekStart = weekStart
        self.isMonth = isMonth
        var byCategory: [ActivityCategory: Int64] = [:]
        var byApp: [String: Int64] = [:]
        for r in reports {
            for lane in r.lanes { byCategory[lane.category, default: 0] += lane.total }
            for app in r.topApps { byApp[app.appName, default: 0] += app.total }
        }
        categories = byCategory.map { CategoryTotal(category: $0.key, total: $0.value) }
            .sorted { $0.total != $1.total ? $0.total > $1.total : $0.category.id < $1.category.id }
        topApps = byApp.map { DayReport.AppTotal(appName: $0.key, total: $0.value) }
            .sorted { $0.total != $1.total ? $0.total > $1.total : $0.appName < $1.appName }
        longestFocus = reports.compactMap(\.longestFocus).max { $0.duration < $1.duration }
        let order = categories.map(\.category)
        let reportByDay = Dictionary(reports.map { ($0.dayStart, $0) }, uniquingKeysWith: { a, _ in a })
        days = dayStarts.map { start in
            let r = reportByDay[start]
            let totals = Dictionary((r?.lanes ?? []).map { ($0.category, $0.total) }, uniquingKeysWith: +)
            let tracked = r?.tracked ?? 0
            let entertainment = totals[.entertainment] ?? 0
            return Day(dayStart: start, isToday: start == today, isFuture: start > today, tracked: tracked,
                       categories: order.compactMap { c in totals[c].map { CategoryTotal(category: c, total: $0) } },
                       length: DayLength(tracked: tracked - entertainment))
        }
        tracked = days.reduce(0) { $0 + $1.tracked }
        trackedDays = days.filter { $0.tracked > 0 }.count
    }

    /// "Mostly Meetings this week," / "Thursday was the longest day."
    /// A month names the date instead: "the 16th was the longest day."
    public func headline(calendar: Calendar = .current) -> (String, String) {
        let span = isMonth ? "month" : "week"
        let when = containsToday ? " this \(span)" : ""
        guard tracked > 0, let top = categories.first else {
            return containsToday ? ("Nothing tracked yet this \(span).", "Your days fill in here as you go.")
                : ("Nothing was tracked this \(span).", "Dayline was off, paused or away.")
        }
        let first = Double(top.total) >= 0.4 * Double(tracked) || categories.count == 1
            ? "Mostly \(top.category.shortName)\(when),"
            : "A mix of \(categories[0].category.shortName) and \(categories[1].category.shortName)\(when),"
        let longest = days.max { $0.tracked < $1.tracked }!
        let date = Date(timeIntervalSince1970: TimeInterval(longest.dayStart))
        let weekday = isMonth ? "the \(Self.ordinal(calendar.component(.day, from: date)))"
            : date.formatted(.dateTime.weekday(.wide))
        if trackedDays == 1 { return (first, containsToday ? "only \(weekday) so far." : "only \(weekday) was tracked.") }
        return (first, "\(weekday) was the longest day.")
    }

    /// 1st, 2nd, 3rd, 16th, 22nd.
    static func ordinal(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        f.locale = Locale(identifier: "en")
        return f.string(from: n as NSNumber) ?? "\(n)"
    }
}

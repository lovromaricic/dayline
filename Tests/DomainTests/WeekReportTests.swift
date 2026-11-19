import Foundation
import Testing
@testable import Domain

@Suite struct WeekReportTests {
    let monday: Int64 = 1_794_441_600
    func dayStart(_ i: Int) -> Int64 { monday + Int64(i) * 86_400 }
    var starts: [Int64] { (0..<7).map(dayStart) }

    func report(_ i: Int, _ parts: [(String, Int64)], today: Int) -> DayReport {
        var t = dayStart(i) + 9 * 3600
        let segs = parts.enumerated().map { n, p in
            defer { t += p.1 }
            return Segment(id: Int64(i * 100 + n), start: t, end: t + p.1, kind: .active, appBundleID: p.0, appName: p.0)
        }
        let cats: [String: ActivityCategory] = ["xcode": .development, "zoom": .meetings, "tv": .entertainment]
        return DayReport(segments: segs, dayStart: dayStart(i), now: i == today ? t : dayStart(i) + 86_399) { cats[$0.appBundleID]! }
    }

    @Test func totalsDaysAndOrder() {
        let reports = [report(0, [("xcode", 3 * 3600), ("zoom", 3600)], today: 2),
                       report(1, [("zoom", 2 * 3600)], today: 2),
                       report(2, [("xcode", 9 * 3600), ("tv", 2 * 3600)], today: 2)]
        let w = WeekReport(weekStart: monday, reports: reports, dayStarts: starts, today: dayStart(2))
        #expect(w.days.count == 7)
        #expect(w.tracked == 17 * 3600)
        #expect(w.trackedDays == 3)
        #expect(w.categories.map(\.category) == [.development, .meetings, .entertainment])
        // Every row stacks in the week's order.
        #expect(w.days[0].categories.map(\.category) == [.development, .meetings])
        #expect(w.days[2].isToday && w.days[3].isFuture && !w.days[1].isFuture)
        // 9 h of work plus a film: long, not very long.
        #expect(w.days[2].length == .long)
        #expect(w.topApps.first?.appName == "xcode")
        #expect(w.containsToday)
    }

    @Test func headlines() {
        let one = WeekReport(weekStart: monday, reports: [report(0, [("zoom", 3600)], today: 0)], dayStarts: starts, today: dayStart(0))
        #expect(one.headline().0 == "Mostly Meetings this week,")
        #expect(one.headline().1.hasPrefix("only "))
        let empty = WeekReport(weekStart: monday, reports: [], dayStarts: starts, today: dayStart(9))
        #expect(!empty.containsToday)
        #expect(empty.headline().0 == "Nothing was tracked this week.")
    }

    @Test func monthHeadlineNamesTheDate() {
        let reports = [report(0, [("zoom", 3600)], today: 2), report(2, [("xcode", 5 * 3600)], today: 2)]
        let m = WeekReport(weekStart: monday, reports: reports, dayStarts: (0..<30).map(dayStart), today: dayStart(2), isMonth: true)
        #expect(m.days.count == 30)
        #expect(m.headline().0 == "Mostly Development this month,")
        let day = Calendar.current.component(.day, from: Date(timeIntervalSince1970: TimeInterval(dayStart(2))))
        #expect(m.headline().1 == "the \(WeekReport.ordinal(day)) was the longest day.")
        #expect(WeekReport.ordinal(22) == "22nd")
    }
}

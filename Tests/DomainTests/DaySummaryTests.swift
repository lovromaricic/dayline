import Foundation
import Testing
@testable import Domain

@Suite struct DaySummaryTests {
    let day: Int64 = 1_794_441_600  // a local midnight is not needed; offsets are relative
    func at(_ h: Int, _ m: Int = 0) -> Int64 { day + Int64(h * 3600 + m * 60) }

    func seg(_ s: Int64, _ e: Int64, _ kind: SegmentKind = .active, app: String = "x", domain: String? = nil, title: String? = nil) -> Segment {
        Segment(id: s, start: s, end: e, kind: kind, appBundleID: app, appName: app, title: title, domain: domain)
    }

    func cat(_ s: Segment) -> ActivityCategory { s.appBundleID == "xcode" ? .development : .browsing }

    @Test func totalsRailsAndMerge() {
        let segs = [
            seg(at(9), at(9, 30), app: "xcode"),
            seg(at(9, 30), at(9, 30) + 40, app: "chrome"),
            seg(at(9, 30) + 40, at(10), app: "xcode"),   // 40 s gap in the Development rail: merged
            seg(at(10), at(10, 15), .away),
            seg(at(10, 15), at(10, 20), .untracked),
        ]
        let d = DaySummary(segments: segs, dayStart: day, now: at(10, 20), category: cat)
        #expect(d.tracked == 3600)
        #expect(d.away == 900)
        #expect(d.rails.map(\.category) == [.development])  // 40 s of browsing gets no rail, as in the timeline
        #expect(d.rails[0].bars == [at(9)...at(10)])
        #expect(d.untracked == [at(10, 15)...at(10, 20)])
        #expect(d.axis == at(8)...at(17))
    }

    @Test func currentBlockSpansSameAppAndSite() {
        let segs = [
            seg(at(9), at(9, 10), app: "chrome", domain: "github.com", title: "Issues"),
            seg(at(9, 10), at(9, 25), app: "chrome", domain: "github.com", title: "PR #42"),
        ]
        let d = DaySummary(segments: segs, dayStart: day, now: at(9, 25), category: cat)
        #expect(d.current?.title == "PR #42")
        #expect(d.current?.since == at(9))
    }

    @Test func noCurrentWhenAwayOrStale() {
        let away = DaySummary(segments: [seg(at(9), at(9, 5)), seg(at(9, 5), at(9, 9), .away)], dayStart: day, now: at(9, 9), category: cat)
        #expect(away.current == nil)
        let stale = DaySummary(segments: [seg(at(9), at(9, 5))], dayStart: day, now: at(11), category: cat)
        #expect(stale.current == nil)
    }

    @Test func axisWidensToFitData() {
        let d = DaySummary(segments: [seg(at(6, 30), at(7)), seg(at(18), at(19, 10))], dayStart: day, now: at(19, 10), category: cat)
        #expect(d.axis == at(6)...at(20))
    }

    @Test(arguments: [(0, "0m"), (59, "0m"), (3120, "52m"), (7200, "2h 00m"), (24300, "6h 45m")])
    func durations(seconds: Int64, text: String) {
        #expect(Durations.format(seconds) == text)
    }
}

extension DaySummaryTests {
    /// The popover and the timeline must agree on lanes and totals.
    @Test func longDayLeavesOutEntertainment() {
        #expect(DayLength(tracked: 9 * 3600 - 60) == .normal)
        #expect(DayLength(tracked: 9 * 3600) == .long)
        #expect(DayLength(tracked: 10 * 3600) == .veryLong)
        // 9 h 30 m of Xcode plus a 1 h film: still only a long day.
        let segs = [seg(at(8), at(17, 30), app: "xcode"), seg(at(19), at(20), app: "tv")]
        let summary = DaySummary(segments: segs, dayStart: day, now: at(20)) { $0.appBundleID == "tv" ? .entertainment : .development }
        #expect(summary.tracked == 10 * 3600 + 30 * 60)
        #expect(summary.length == .long)
    }

    @Test func popoverMatchesTimeline() {
        let segs = [
            seg(at(9), at(9, 30), app: "xcode"),
            seg(at(9, 30), at(9, 30) + 20, app: "chrome"),   // a 20 s glance
            seg(at(9, 30) + 20, at(10), app: "xcode"),
            seg(at(10), at(10, 20), app: "chrome"),
        ]
        let report = DayReport(segments: segs, dayStart: day, now: at(10, 20), category: cat)
        let summary = DaySummary(report: report)
        #expect(summary.rails.map(\.category) == report.lanes.map(\.category))
        #expect(summary.rails.map(\.total) == report.lanes.map(\.total))
        #expect(summary.rails.flatMap(\.bars) == report.lanes.flatMap { $0.blocks.map { $0.start...$0.end } })
        #expect(summary.tracked == report.tracked)
        #expect(summary.axis == report.axis)
    }
}

extension DaySummaryTests {
    /// The first minute in an app has no block yet, but the popover still says what is in front.
    @Test func currentBeforeTheFirstMinute() {
        let segs = [
            seg(at(9), at(9, 20), app: "xcode", title: "a.swift"),
            seg(at(9, 20), at(9, 20) + 25, app: "chrome", domain: "github.com", title: "PR #42"),
        ]
        let d = DaySummary(segments: segs, dayStart: day, now: at(9, 20) + 25, category: cat)
        #expect(d.current?.title == "PR #42")
        #expect(d.current?.appName == "chrome")
        #expect(d.current?.since == at(9, 20))
    }
}

extension DaySummaryTests {
    /// Right after resuming or switching, the open segment is zero seconds long.
    @Test func currentRightAfterSwitching() {
        let segs = [
            seg(at(9), at(9, 20), app: "xcode", title: "a.swift"),
            seg(at(9, 20), at(9, 20), app: "chrome", domain: "github.com", title: "PR #42"),
        ]
        let d = DaySummary(segments: segs, dayStart: day, now: at(9, 20) + 2, category: cat)
        #expect(d.current?.title == "PR #42")
        #expect(d.current?.since == at(9, 20))
    }
}

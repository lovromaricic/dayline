import Foundation
import Testing
@testable import Domain

@Suite struct DayRecapTests {
    let day: Int64 = 1_794_441_600

    /// Back-to-back blocks from 8:00, one per (app, length).
    func recap(_ parts: [(String, Int64)]) -> DayRecap? {
        var t = day + 8 * 3600
        let segs = parts.enumerated().map { n, p in
            defer { t += p.1 }
            return Segment(id: Int64(n), start: t, end: t + p.1, kind: .active, appBundleID: p.0, appName: p.0)
        }
        let cats: [String: ActivityCategory] = ["xcode": .development, "zoom": .meetings, "figma": .design, "tv": .entertainment]
        return DayRecap(report: DayReport(segments: segs, dayStart: day, now: day + 86_399) { cats[$0.appBundleID]! })
    }

    @Test func tooLittleSendsNothing() {
        #expect(recap([("xcode", 20 * 60)]) == nil)
    }

    @Test func ordinaryDay() {
        let r = recap([("xcode", 2 * 3600), ("zoom", 1800), ("xcode", 3 * 3600)])!
        #expect(r.title == "Your day: 5h 30m")
        #expect(r.body == "Mostly Development. Longest focus 3h 00m in xcode.")
    }

    @Test func longDaysComeFirst() {
        let r = recap([("zoom", 6 * 3600), ("xcode", 4 * 3600 + 600)])!
        #expect(r.body == "Over 10 hours. A mix of Meetings and Development. Time to stop?")
        #expect(recap([("xcode", 9 * 3600 + 600)])!.body == "Over 9 hours. Mostly Development.")
        // A film does not make a long working day.
        #expect(recap([("xcode", 8 * 3600), ("tv", 2 * 3600)])!.body.hasPrefix("Mostly Development."))
    }

    @Test func meetingHeavyDay() {
        let r = recap([("zoom", 4 * 3600), ("xcode", 3 * 3600)])!
        #expect(r.body == "Half your day was meetings: 4h 00m.")
    }

    @Test func shortAndUnfocusedDays() {
        #expect(recap([("figma", 3600), ("xcode", 3600)])!.body == "A short day. A mix of Development and Design.")
        let choppy = Array(repeating: [("xcode", Int64(20 * 60)), ("figma", Int64(20 * 60))], count: 5).flatMap { $0 }
        #expect(recap(choppy)!.body == "A mix of Development and Design. No focus block over 25 minutes.")
    }
}

import Foundation
import Testing
@testable import Domain

@Suite struct BreakReminderTests {
    func seg(_ start: Int64, _ end: Int64, _ kind: SegmentKind = .active) -> Segment {
        Segment(id: start, start: start, end: end, kind: kind, appBundleID: "a", appName: "A")
    }

    @Test func shortPausesDontResetTheClock() {
        // Work from 0, a 1-minute idle at 600, a 20-minute lunch at 1200, then work again.
        let segs = [seg(0, 600), seg(600, 660, .away), seg(660, 1200), seg(1200, 2400, .away), seg(2400, 6000)]
        #expect(BreakReminder.stretchStart(segments: segs, now: 6000) == 2400)
        #expect(BreakReminder.stretchStart(segments: Array(segs.prefix(3)), now: 1200) == 0)
    }

    @Test func awayNowOrAGapEndsTheStretch() {
        #expect(BreakReminder.stretchStart(segments: [seg(0, 600), seg(600, 900, .away)], now: 900) == nil)
        // Dayline saw nothing for 5 minutes (asleep): that was a break.
        #expect(BreakReminder.stretchStart(segments: [seg(0, 600), seg(900, 4000)], now: 4000) == 900)
        // The last segment ended a while ago: you're not at the Mac.
        #expect(BreakReminder.stretchStart(segments: [seg(0, 600)], now: 1000) == nil)
    }
}

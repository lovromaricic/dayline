import Foundation
import Testing
@testable import Domain

@Suite struct DayReportTests {
    let day: Int64 = 1_794_441_600
    func at(_ h: Int, _ m: Int = 0, _ s: Int = 0) -> Int64 { day + Int64(h * 3600 + m * 60 + s) }

    var nextID: Int64 = 0
    mutating func seg(_ s: Int64, _ e: Int64, _ app: String = "xcode", domain: String? = nil, title: String? = nil,
                      _ kind: SegmentKind = .active) -> Segment {
        nextID += 1
        return Segment(id: nextID, start: s, end: e, kind: kind, appBundleID: app, appName: app, title: title, domain: domain)
    }

    func cat(_ s: Segment) -> ActivityCategory {
        switch s.appBundleID {
        case "xcode", "terminal": .development
        case "slack": .communication
        default: s.domain == "github.com" ? .development : .browsing
        }
    }

    func report(_ segs: [Segment], now: Int64? = nil) -> DayReport {
        DayReport(segments: segs, dayStart: day, now: now ?? at(23) + 2 * 86_400, category: cat)
    }

    @Test mutating func mergesSameAppSiteAndCategory() {
        let r = report([
            seg(at(9), at(9, 10), title: "a.swift"),
            seg(at(9, 10, 30), at(9, 40), title: "b.swift"),       // 30 s gap: same block
            seg(at(9, 40), at(9, 50), "chrome", domain: "github.com", title: "PR"),
        ])
        #expect(r.blocks.count == 2)
        #expect(r.blocks[0].start == at(9) && r.blocks[0].end == at(9, 40))
        #expect(r.blocks[0].duration == 39 * 60)      // whole minutes
        #expect(r.blocks[0].title == "b.swift")  // the longest segment's title
    }

    @Test mutating func shortInterruptionIsDroppedAndHalvesRejoin() {
        let r = report([
            seg(at(9), at(9, 20)),
            seg(at(9, 20), at(9, 20, 20), "slack"),   // 20 s glance at Slack
            seg(at(9, 20, 20), at(9, 40)),
        ])
        #expect(r.blocks.count == 1)
        #expect(r.blocks[0].end == at(9, 40))
        #expect(r.tracked == 39 * 60)                 // Slack has no lane: out of the total; whole minutes
        #expect(r.lanes.map(\.category) == [.development])   // 20 s of Slack gets no lane
        #expect(r.lanes.reduce(0) { $0 + $1.total } == r.tracked)  // the rows add up to the total
    }

    @Test mutating func shortBlockIsAbsorbedBySameCategoryNeighbour() {
        let r = report([
            seg(at(9), at(9, 20)),
            seg(at(9, 20), at(9, 20, 30), "terminal"),  // 30 s in Terminal, also Development
            seg(at(9, 20, 30), at(9, 30), "chrome", domain: "github.com"),
        ])
        #expect(r.blocks.count == 2)
        #expect(r.blocks[0].end == at(9, 20, 30))
    }

    @Test mutating func shortBlockAbsorbedForwardWhenNothingBefore() {
        let r = report([
            seg(at(9), at(9, 0, 20), "terminal"),
            seg(at(9, 0, 20), at(9, 30)),
        ])
        #expect(r.blocks.count == 1)
        #expect(r.blocks[0].start == at(9))
        #expect(r.blocks[0].duration == 30 * 60)
    }

    @Test mutating func everythingAddsUpInWholeMinutes() {
        let r = report([
            seg(at(9), at(9, 10, 50)),                       // 10m 50s
            seg(at(9, 10, 50), at(9, 20, 40), "slack"),      // 9m 50s
            seg(at(9, 20, 40), at(9, 25, 50), "chrome"),     // 5m 10s
        ])
        // 25m 50s: three blocks rounded down would show 24m.
        let minutes = r.blocks.map(\.duration)
        #expect(minutes.allSatisfy { $0 % 60 == 0 })
        #expect(minutes.reduce(0, +) == r.tracked)
        #expect(r.lanes.reduce(0) { $0 + $1.total } == r.tracked)
        #expect(r.topApps.reduce(0) { $0 + $1.total } == r.tracked)
        #expect(r.tracked == 25 * 60)
    }

    @Test mutating func shortStartJoinsItsBlockPastAGlance() {
        let r = report([
            seg(at(9), at(9, 0, 30)),                        // the first 30 s
            seg(at(9, 0, 30), at(9, 0, 40), "slack"),        // a 10 s glance elsewhere
            seg(at(9, 0, 40), at(9, 30)),
        ])
        #expect(r.blocks.count == 1)
        #expect(r.blocks[0].start == at(9))
        #expect(r.blocks[0].duration == r.lanes[0].total)    // the block and its row agree
    }

    @Test mutating func awayTotalLeavesOutTheNight() {
        let r = report([
            seg(at(0), at(7), "", .away),          // asleep, Mac on
            seg(at(7), at(8)),
            seg(at(8), at(8, 30), "", .away),      // a real break
            seg(at(8, 30), at(9)),
            seg(at(9), at(23), "", .away),         // evening
        ])
        #expect(r.awayTotal == 30 * 60)
        #expect(r.away.count == 3)                 // the chart still shows all of it
    }

    @Test mutating func awayBreaksBlocks() {
        let r = report([
            seg(at(9), at(9, 20)),
            seg(at(9, 20), at(9, 50), "", .away),
            seg(at(9, 50), at(10, 10)),
        ])
        #expect(r.blocks.count == 2)
        #expect(r.awayTotal == 30 * 60)
        #expect(r.away == [at(9, 20)...at(9, 50)])
    }

    @Test mutating func longestFocusSpansBlocksInOneApp() {
        let r = report([
            seg(at(12, 50), at(13, 30), title: "CaptureService.swift"),
            seg(at(13, 30), at(14, 40), "chrome", domain: "github.com", title: "PR"),
            seg(at(15), at(15, 10), "slack"),
        ])
        #expect(r.longestFocus?.appName == "chrome")
        #expect(r.longestFocus?.duration == Int64(70 * 60))
        #expect(r.headline().1 == "with a long focus block after lunch.")
    }

    @Test mutating func noFocusUnder25Minutes() {
        let r = report([seg(at(9), at(9, 20)), seg(at(9, 30), at(9, 50), "slack")])
        #expect(r.longestFocus == nil)
    }

    @Test mutating func headlines() {
        let dev = report([seg(at(9), at(11)), seg(at(11), at(11, 30), "slack")])
        #expect(dev.headline().0 == "Mostly Development,")  // a past day
        let mix = report([seg(at(9), at(10)), seg(at(10), at(10, 50), "slack"), seg(at(11), at(11, 50), "chrome")])
        #expect(mix.headline().0.hasPrefix("A mix of Development and"))
        let fresh = report([seg(at(9), at(9, 10))], now: at(9, 10))
        #expect(fresh.headline() == ("Tracking is on.", "Your first blocks are already forming."))
        let today = report([seg(at(9), at(11))], now: at(11))
        #expect(today.headline().0 == "Mostly Development so far,")
        #expect(report([]).headline().0 == "Nothing was tracked this day.")
    }

    @Test mutating func topAppsAndOpenBlock() {
        let r = report([seg(at(9), at(10), "chrome"), seg(at(10), at(10, 30))], now: at(10, 30))
        #expect(r.topApps.map(\.appName) == ["chrome", "xcode"])
        #expect(r.blocks.last?.isOpen == true)
        #expect(r.blocks.first?.isOpen == false)
    }
}

extension DayReportTests {
    @Test mutating func onlyShortMomentsHasNoLanesAndNoCrash() {
        let r = report([seg(at(9), at(9, 0, 40)), seg(at(9, 0, 40), at(9, 1, 10), "slack")])
        #expect(r.lanes.isEmpty)
        #expect(r.topApps.isEmpty)
        #expect(r.tracked == 0)                       // the total is what the lanes show
        #expect(r.headline().0 == "Only short moments.")
    }

    @Test mutating func notTrackingSkipsTrackingIsOn() {
        let r = report([seg(at(9), at(9, 10))], now: at(9, 10))
        #expect(r.headline(trackingNow: false).0 == "Mostly Development so far,")
    }
}

extension DayReportTests {
    @Test mutating func shortBreaksAreJoinedOrHidden() {
        let r = report([
            seg(at(9), at(9, 10)),
            seg(at(9, 10), at(9, 10, 30), "", .away),      // 30 s: too short to draw
            seg(at(9, 10, 30), at(9, 20)),
            seg(at(9, 20), at(9, 21, 30), "", .away),      // 90 s, then 60 s later another 90 s:
            seg(at(9, 21, 30), at(9, 22, 30)),
            seg(at(9, 22, 30), at(9, 24), "", .away),      // joined into one 4-minute break
            seg(at(9, 24), at(9, 40)),
        ])
        #expect(r.away == [at(9, 20)...at(9, 24)])
        #expect(r.awayTotal == 30 + 90 + 90)               // totals still count every second
    }
}

extension DayReportTests {
    @Test mutating func glancesAddingUpToAMinuteGetNoLane() {
        let r = report([
            seg(at(9), at(9, 10)),
            seg(at(9, 10), at(9, 10, 40), "slack"),
            seg(at(9, 10, 40), at(9, 20)),
            seg(at(9, 20), at(9, 20, 40), "slack"),   // 80 s of Slack in total, never a minute at once
            seg(at(9, 20, 40), at(9, 30)),
        ])
        #expect(r.lanes.map(\.category) == [.development])
        #expect(r.tracked == 28 * 60)                 // 30 min less the glances, in whole minutes
    }
}

import Foundation
import Testing
@testable import Domain

@Suite struct DayReportTests {
    let day: Int64 = 1_794_441_600
    func at(_ h: Int, _ m: Int = 0, _ s: Int = 0) -> Int64 { day + Int64(h * 3600 + m * 60 + s) }

    var nextID: Int64 = 0
    mutating func seg(_ s: Int64, _ e: Int64, _ app: String = "xcode", domain: String? = nil, title: String? = nil,
                      _ kind: SegmentKind = .active, call: Bool = false) -> Segment {
        nextID += 1
        return Segment(id: nextID, start: s, end: e, kind: kind, appBundleID: app, appName: app, title: title, domain: domain,
                       call: call)
    }

    func cat(_ s: Segment) -> ActivityCategory {
        let base: ActivityCategory = switch s.appBundleID {
        case "xcode", "terminal": .development
        case "slack": .communication
        case "zoom": .meetings
        default: s.domain == "github.com" ? .development : .browsing
        }
        // A whole call is Meetings; split, only browsing where it took place is (as in Categorizer).
        return s.wholeCall || (s.call && base == .browsing) ? .meetings : base
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

extension DayReportTests {
    @Test mutating func aCallIsNeverFocus() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!   // `day` is a UTC midnight
        let call = report([seg(at(9, 30), at(10, 40), "zoom"), seg(at(10, 40), at(10, 50))])
        #expect(call.longestFocus == nil)
        #expect(call.longCalls.count == 1)
        #expect(call.headline(calendar: utc).1 == "with one long call first thing.")

        let both = report([seg(at(9), at(10), "zoom"), seg(at(13), at(14))])
        #expect(both.longestFocus?.appName == "xcode")
        #expect(both.headline(calendar: utc).1 == "with a long focus block after lunch.")

        let many = report([seg(at(9), at(9, 30), "zoom"), seg(at(11), at(11, 30), "zoom"), seg(at(14), at(14, 30), "zoom")])
        #expect(many.headline(calendar: utc).1 == "with long calls all day.")
    }
}

extension DayReportTests {
    @Test mutating func aWholeCallIsOneMeetingsBlockWithItsProof() {
        let huddle = "Alex - Acme - Slack"
        let r = report([
            seg(at(14), at(14, 23)),                                                   // coding, no call
            seg(at(14, 23), at(14, 27), "chrome", title: huddle, call: true),          // the huddle window
            seg(at(14, 27), at(14, 50), "figma", title: "Onboarding – Figma", call: true),
            seg(at(14, 50), at(14, 50, 30), "chrome", domain: "amazon.de", call: true), // a glance
            seg(at(14, 50, 30), at(15, 13), "figma", title: "Onboarding – Figma", call: true),
            seg(at(15, 13), at(15, 16), "chrome", title: huddle, call: true),
            seg(at(15, 16), at(15, 30)),
        ])
        #expect(r.calls.count == 1 && r.calls[0].name == "Slack huddle")
        let call = r.blocks.filter { $0.call != nil }
        #expect(call.count == 1)
        #expect(call[0].start == at(14, 23) && call[0].end == at(15, 16))
        #expect(call[0].category == .meetings && call[0].duration == 53 * 60)
        #expect(call[0].title == "Slack huddle with Alex")
        // The proof: what was in front, adding up to the block.
        #expect(call[0].call?.totals.map(\.label) == ["Onboarding", "Slack huddle window"])   // the 30 s glance is under a minute
        #expect(call[0].call?.totals.first?.source == "figma")
        #expect(call[0].call?.parts.map(\.label) == ["Slack huddle window", "Onboarding", "amazon.de", "Onboarding", "Slack huddle window"])
        #expect(call[0].call?.totals.reduce(0) { $0 + $1.duration } == call[0].duration)
        #expect(call[0].call?.parts.first?.label == "Slack huddle window")
        #expect(r.lanes.map(\.category) == [.meetings, .development])  // Figma's time is the call's
        #expect(r.lanes.reduce(0) { $0 + $1.total } == r.tracked)
        #expect(r.tracked == 90 * 60)
    }

    @Test mutating func aShortMicRunIsNotACall() {
        let r = report([seg(at(9), at(9, 10)), seg(at(9, 10), at(9, 11, 30), call: true), seg(at(9, 11, 30), at(9, 20))])
        #expect(r.calls.isEmpty)
        #expect(r.blocks.count == 1 && r.blocks[0].call == nil)
    }
}

extension DayReportTests {
    @Test mutating func hidingTitlesKeepsTimesAndApps() {
        let huddle = "Alex - Acme - Slack"
        let r = report([
            seg(at(9), at(9, 30), title: "Secret.swift"),
            seg(at(9, 30), at(9, 35), "chrome", title: huddle, call: true),
            seg(at(9, 35), at(9, 50), "figma", title: "Enes Projekt – Figma", call: true),
        ]).hidingTitles()
        #expect(r.blocks[0].title == nil && r.blocks[0].appName == "xcode")
        #expect(r.blocks[1].title == "Slack huddle")                 // not who it was with
        #expect(r.blocks[1].call?.totals.map(\.label).contains("figma") == true)
        #expect(r.blocks[1].call?.totals.contains { $0.label.contains("Enes") } == false)
        #expect(r.calls.first?.people == nil)
        #expect(r.tracked == 50 * 60)
    }
}

extension DayReportTests {
    @Test mutating func aCallIsNamedAfterWhereMostOfItWas() {
        // A huddle with the mic still on as you join a Teams meeting.
        var teams = seg(at(13, 1), at(13, 30), "chrome", title: "Planning | Microsoft Teams", call: true)
        teams.host = "teams.microsoft.com"
        let r = report([seg(at(12, 58), at(13, 1), "chrome", title: "Enes - Acme - Slack", call: true), teams])
        #expect(r.calls.first?.name == "Teams call")
        #expect(r.calls.first?.people == nil)
        #expect(r.blocks.count == 1 && r.blocks[0].title == "Teams call")
    }
}

extension DayReportTests {
    @Test mutating func aBlockShowsItsNote() {
        var segs = [seg(at(9), at(9, 20)), seg(at(9, 20), at(9, 40)), seg(at(10), at(10, 20), "figma")]
        segs[1].note = "Loan flow errors"
        let r = report(segs)
        #expect(r.blocks.map(\.note) == ["Loan flow errors", nil])
    }
}

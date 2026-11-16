import Foundation
import Testing
@testable import Domain

/// Applies segment changes the way the store does, so tests can assert on
/// the resulting rows.
private struct Recorder {
    struct Row: Equatable, CustomStringConvertible {
        var start: Int64, end: Int64, kind: SegmentKind, title: String?, call: Bool
        var description: String { "\(kind)[\(start)-\(end)] \(title ?? "-")\(call ? " call" : "")" }
    }

    var seg = Segmenter()
    var rows: [Row] = []
    var open = false

    mutating func send(_ e: CaptureEvent, at t: Int64) {
        for change in seg.handle(e, at: t) {
            switch change {
            case .begin(let d):
                rows.append(Row(start: d.start, end: d.start, kind: d.kind, title: d.activity?.title, call: d.call))
                open = true
            case .end(let at):
                rows[rows.count - 1].end = at
                open = false
            case .discard:
                rows.removeLast()
                open = false
            case .extend(let to):
                rows[rows.count - 1].end = to
            }
        }
    }

    /// Simulates the 5 s idle poll from `from` to `to` with the given last-input time.
    mutating func poll(from: Int64, to: Int64, lastInput: Int64) {
        var t = from
        while t <= to {
            send(.idle(seconds: Double(t - lastInput)), at: t)
            t += 5
        }
    }

    func total(_ kind: SegmentKind) -> Int64 {
        rows.filter { $0.kind == kind }.reduce(0) { $0 + $1.end - $1.start }
    }
}

private func chrome(_ title: String, _ url: String) -> Activity {
    .browser(appBundleID: "com.google.Chrome", appName: "Google Chrome", title: title, url: URL(string: url))
}

private let xcode = Activity(appBundleID: "com.apple.dt.Xcode", appName: "Xcode", title: "CaptureService.swift")

@Suite struct SegmenterTests {
    @Test func tabSwitchesMakeOneSegmentEach() {
        var r = Recorder()
        r.send(.startTracking, at: 0)
        r.send(.activity(chrome("Swift Concurrency", "https://developer.apple.com/x")), at: 0)
        r.send(.activity(chrome("Pull requests", "https://github.com/pulls")), at: 40)
        r.send(.activity(xcode), at: 95)
        r.send(.tick, at: 100)
        #expect(r.rows == [
            .init(start: 0, end: 40, kind: .active, title: "Swift Concurrency", call: false),
            .init(start: 40, end: 95, kind: .active, title: "Pull requests", call: false),
            .init(start: 95, end: 100, kind: .active, title: "CaptureService.swift", call: false),
        ])
    }

    @Test func badgeFlapsDoNotSplit() {
        var r = Recorder()
        r.send(.startTracking, at: 0)
        r.send(.activity(chrome("Alex (DM) - Acme - Slack", "https://app.slack.com/client/1")), at: 0)
        r.send(.activity(chrome("! Alex (DM) - Acme - 1 new item - Slack", "https://app.slack.com/client/1")), at: 10)
        r.send(.activity(chrome("Alex (DM) - Acme - Slack", "https://app.slack.com/client/1")), at: 12)
        r.send(.tick, at: 30)
        #expect(r.rows.count == 1)
        #expect(r.rows[0].end == 30)
    }

    @Test func idleCutsAtLastInputAndResumes() {
        var r = Recorder()
        r.send(.startTracking, at: 0)
        r.send(.activity(xcode), at: 0)
        // Last input at 50, then nothing for 2 min 10 s.
        r.poll(from: 5, to: 180, lastInput: 50)
        #expect(r.seg.isAway)
        // Back at 300.
        r.send(.idle(seconds: 0), at: 300)
        r.send(.tick, at: 310)
        #expect(r.rows.map(\.kind) == [.active, .away, .active])
        #expect(r.rows[0].end == 50)
        #expect(r.rows[1].start == 50 && r.rows[1].end == 300)
        #expect(r.rows[2].start == 300 && r.rows[2].end == 310)
    }

    @Test func shortIdleIsNotAway() {
        var r = Recorder()
        r.send(.startTracking, at: 0)
        r.send(.activity(xcode), at: 0)
        r.poll(from: 5, to: 115, lastInput: 0)  // 1 min 55 s
        #expect(!r.seg.isAway)
        #expect(r.rows.count == 1)
    }

    @Test func appSwitchWhileAwayRecordsNothingNew() {
        var r = Recorder()
        r.send(.startTracking, at: 0)
        r.send(.activity(xcode), at: 0)
        r.poll(from: 5, to: 160, lastInput: 30)
        // A calendar alert brings another app forward with nobody there.
        r.send(.activity(Activity(appBundleID: "com.apple.iCal", appName: "Calendar")), at: 165)
        r.send(.tick, at: 170)
        #expect(r.rows.map(\.kind) == [.active, .away])
    }

    @Test func callKeepsYouActiveAndIsFlagged() {
        var r = Recorder()
        r.send(.startTracking, at: 0)
        r.send(.activity(chrome("Meet - abc-defg-hij", "https://meet.google.com/abc-defg-hij")), at: 0)
        r.send(.call(true), at: 10)
        r.poll(from: 15, to: 600, lastInput: 10)  // 10 minutes without typing
        #expect(!r.seg.isAway)
        #expect(r.rows.map(\.kind) == [.active, .active])
        #expect(r.rows[1].call && r.rows[1].start == 10)
        #expect(r.total(.away) == 0)
    }

    @Test func everySegmentDuringACallIsFlagged() {
        var r = Recorder()
        r.send(.startTracking, at: 0)
        let teams = chrome("Chat | Microsoft Teams", "https://teams.microsoft.com/v2/")
        r.send(.activity(teams), at: 0)
        r.send(.call(true), at: 10)
        r.send(.activity(chrome("Sam - Slack", "https://app.slack.com/client/T1")), at: 60)
        r.send(.activity(chrome("Week of 8 November - Google Calendar", "https://calendar.google.com/")), at: 90)
        r.send(.activity(teams), at: 120)
        r.send(.call(false), at: 300)
        r.send(.tick, at: 400)
        // The whole span is the call; narrowing finds where it took place:
        // Teams is the call, Slack and the calendar during it are not.
        #expect(r.rows.map(\.call) == [false, true, true, true, true, false])
        let segs = r.rows.enumerated().map { i, row in
            Segment(id: Int64(i), start: row.start, end: row.end, kind: row.kind, appBundleID: "com.google.Chrome",
                    appName: "Google Chrome", title: row.title, host: [0, 4].contains(i) ? "teams.microsoft.com"
                        : i == 1 ? "teams.microsoft.com" : i == 2 ? "app.slack.com" : "calendar.google.com", call: row.call)
        }
        #expect(Segment.narrowingCalls(segs).map(\.call) == [false, true, false, false, true, false])
    }

    @Test func oldCallFlagsNarrowToWhereTheCallStarted() {
        func seg(_ id: Int64, _ host: String?, title: String? = nil, call: Bool) -> Segment {
            Segment(id: id, start: id * 10, end: id * 10 + 10, kind: .active, appBundleID: "com.google.Chrome",
                    appName: "Google Chrome", title: title, host: host, call: call)
        }
        let old = [
            seg(0, "app.slack.com", call: false),
            seg(1, "teams.microsoft.com", call: true),        // the call starts here
            seg(2, "app.slack.com", title: "Alex (DM) - Acme - Slack", call: true),
            seg(3, "figma.com", call: true),
            seg(4, "teams.microsoft.com", call: true),
            seg(5, "app.slack.com", call: false),
        ]
        #expect(Segment.narrowingCalls(old).map(\.call) == [false, true, false, false, true, false])
        // A Slack huddle right after a Teams call (one mic run): the huddle
        // window is a call wherever the call started.
        let huddle = [seg(1, "teams.microsoft.com", call: true), seg(2, "app.slack.com", call: true),
                      seg(3, nil, title: "Alex, Sam - Acme - Slack", call: true)]
        #expect(Segment.narrowingCalls(huddle).map(\.call) == [true, false, true])
        // Already narrow data stays as it is.
        let new = Segment.narrowingCalls(old)
        #expect(Segment.narrowingCalls(new).map(\.call) == new.map(\.call))
    }

    @Test func webAppHostsFromTitles() {
        #expect(Titles.webAppHost("Alex, Sam - Acme - Slack") == "app.slack.com")
        #expect(Titles.webAppHost("(2) Chat | Microsoft Teams") == "teams.microsoft.com")
        #expect(Titles.webAppHost("Choose what to share with teams.microsoft.com") == "teams.microsoft.com")
        #expect(Titles.webAppHost("teams.microsoft.com is sharing your screen.") == "teams.microsoft.com")
        #expect(Titles.webAppHost("New Tab") == nil)
    }

    @Test func untouchedCallStopsCountingAfterAnHour() {
        var r = Recorder()
        r.send(.startTracking, at: 0)
        r.send(.activity(chrome("Meet - abc-defg-hij", "https://meet.google.com/abc-defg-hij")), at: 0)
        r.send(.call(true), at: 0)
        r.poll(from: 5, to: 3 * 3600, lastInput: 0)   // mic left on, nobody there
        r.send(.call(true), at: 3 * 3600)             // the mic reports "on" again
        #expect(r.seg.isAway)
        #expect(r.rows.last?.kind == .away && r.rows.last?.start == 3600)
        #expect(r.total(.away) == 2 * 3600)
    }

    @Test func callGraceBridgesMeetPreviewGap() {
        var r = Recorder()
        r.send(.startTracking, at: 0)
        r.send(.activity(chrome("Meet", "https://meet.google.com/x")), at: 0)
        r.send(.call(true), at: 0)
        r.send(.call(false), at: 20)
        r.send(.tick, at: 25)
        r.send(.call(true), at: 31)  // 11 s gap
        r.send(.tick, at: 100)
        #expect(r.rows.count == 1)
        #expect(r.rows[0].call)
    }

    @Test func callEndsWhenMicWentOffNotWhenGraceRanOut() {
        var r = Recorder()
        r.send(.startTracking, at: 0)
        r.send(.activity(chrome("Meet", "https://meet.google.com/x")), at: 0)
        r.send(.call(true), at: 0)
        r.send(.call(false), at: 300)
        r.send(.tick, at: 360)
        #expect(r.rows.count == 2)
        #expect(r.rows[0].call && r.rows[0].end == 300)
        #expect(!r.rows[1].call && r.rows[1].start == 300)
    }

    @Test func idleAfterCallCountsFromCallEnd() {
        var r = Recorder()
        r.send(.startTracking, at: 0)
        r.send(.activity(xcode), at: 0)
        r.send(.call(true), at: 0)
        r.send(.call(false), at: 600)  // no input during the whole call
        r.poll(from: 605, to: 760, lastInput: 0)
        #expect(r.seg.isAway)
        let away = r.rows.first { $0.kind == .away }
        #expect(away?.start == 600)
    }

    @Test func lockIsAwayAndExcludedFromActive() {
        var r = Recorder()
        r.send(.startTracking, at: 0)
        r.send(.activity(xcode), at: 0)
        r.send(.suspend(.lock), at: 100)
        r.send(.tick, at: 200)
        r.send(.resume(.lock), at: 400)
        r.send(.tick, at: 410)
        #expect(r.rows.map(\.kind) == [.active, .away, .active])
        #expect(r.total(.away) == 300)
        #expect(r.total(.active) == 110)
    }

    @Test func sleepWhileLockedNeedsBothToResume() {
        var r = Recorder()
        r.send(.startTracking, at: 0)
        r.send(.activity(xcode), at: 0)
        r.send(.suspend(.lock), at: 10)
        r.send(.suspend(.sleep), at: 20)
        r.send(.resume(.sleep), at: 500)
        #expect(r.seg.isAway)
        r.send(.resume(.lock), at: 520)
        #expect(!r.seg.isAway)
        #expect(r.rows.map(\.kind) == [.active, .away, .active])
        #expect(r.rows[1].start == 10 && r.rows[1].end == 520)
    }

    @Test func privateWindowRecordsNothingNotEvenAway() {
        var r = Recorder()
        r.send(.startTracking, at: 0)
        r.send(.activity(xcode), at: 0)
        r.send(.activity(nil), at: 60)
        r.poll(from: 65, to: 400, lastInput: 60)
        r.send(.activity(xcode), at: 410)
        r.send(.tick, at: 420)
        #expect(r.rows.map(\.kind) == [.active, .active])
        #expect(r.rows[0].end == 60 && r.rows[1].start == 410)
    }

    @Test func pauseRecordsUntrackedGap() {
        var r = Recorder()
        r.send(.startTracking, at: 0)
        r.send(.activity(xcode), at: 0)
        r.send(.stopTracking, at: 100)
        r.send(.tick, at: 500)
        r.send(.startTracking, at: 900)
        r.send(.tick, at: 910)
        #expect(r.rows.map(\.kind) == [.active, .untracked, .active])
        #expect(r.rows[1].start == 100 && r.rows[1].end == 900)
    }

    @Test func idleIsIgnoredWhilePaused() {
        var r = Recorder()
        r.send(.startTracking, at: 0)
        r.send(.activity(xcode), at: 0)
        r.send(.stopTracking, at: 10)
        r.poll(from: 15, to: 400, lastInput: 10)
        #expect(r.rows.map(\.kind) == [.active, .untracked])
    }

    @Test func resumingAfterLongPauseDoesNotStartAway() {
        var r = Recorder()
        r.send(.startTracking, at: 0)
        r.send(.activity(xcode), at: 0)
        r.send(.stopTracking, at: 10)
        r.send(.startTracking, at: 1000)
        r.send(.idle(seconds: 990), at: 1000)  // no input since the pause began
        #expect(!r.seg.isAway)
    }

    @Test func shutdownClosesOpenSegment() {
        var r = Recorder()
        r.send(.startTracking, at: 0)
        r.send(.activity(xcode), at: 0)
        r.send(.shutdown, at: 50)
        r.send(.tick, at: 60)
        #expect(r.rows == [.init(start: 0, end: 50, kind: .active, title: "CaptureService.swift", call: false)])
        #expect(!r.open)
    }

    @Test func idleCutBeforeOpenSegmentDiscardsIt() {
        var r = Recorder()
        r.send(.startTracking, at: 0)
        r.send(.activity(xcode), at: 0)
        // A window comes forward on its own at 100; the last input was at 30.
        r.send(.activity(Activity(appBundleID: "com.apple.iCal", appName: "Calendar")), at: 100)
        r.poll(from: 105, to: 160, lastInput: 30)
        #expect(r.rows.map(\.kind) == [.active, .away])
        // Known limitation: the cut cannot reach into the closed segment.
        #expect(r.rows[0].end == 100)
        #expect(r.rows[1].start == 100)
    }

    @Test func noSegmentsBeforeTrackingStarts() {
        var r = Recorder()
        r.send(.activity(xcode), at: 0)
        r.send(.tick, at: 10)
        #expect(r.rows.isEmpty)
    }
}

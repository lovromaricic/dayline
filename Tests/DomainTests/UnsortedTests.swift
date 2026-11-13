import Foundation
import Testing
@testable import Domain

@Suite struct UnsortedTests {
    let day: Int64 = 1_794_441_600

    func report(_ segs: [Segment], day d: Int64) -> DayReport {
        let known: Set<String> = ["xcode"]
        return DayReport(segments: segs, dayStart: d, now: d + 86_399) { s in
            let c: ActivityCategory = known.contains(s.appBundleID) ? .development : .uncategorized
            // A manual pick of Uncategorized is the user's choice, not a gap.
            if let m = s.manualCategoryID { return CategoryResolution(category: m == 7 ? .uncategorized : c, guess: .development, edited: true) }
            return CategoryResolution(category: c, guess: c, edited: false)
        }
    }

    @Test func groupsByAppAndSiteAcrossDays() {
        let t = day + 9 * 3600
        let d1 = [
            Segment(id: 1, start: t, end: t + 1800, kind: .active, appBundleID: "chrome", appName: "Google Chrome",
                    host: "www.notion.so", domain: "notion.so"),
            Segment(id: 2, start: t + 1800, end: t + 3600, kind: .active, appBundleID: "xcode", appName: "Xcode"),
            Segment(id: 3, start: t + 3600, end: t + 4800, kind: .active, appBundleID: "linear", appName: "Linear"),
            Segment(id: 4, start: t + 4800, end: t + 4830, kind: .active, appBundleID: "raycast", appName: "Raycast"),
        ]
        let t2 = t + 86_400
        let d2 = [
            Segment(id: 5, start: t2, end: t2 + 2400, kind: .active, appBundleID: "chrome", appName: "Google Chrome",
                    host: "acme.notion.so", domain: "notion.so"),
            Segment(id: 6, start: t2 + 2400, end: t2 + 4200, kind: .active, appBundleID: "notes", appName: "Notes",
                    manualCategoryID: 7),
        ]
        let u = Unsorted.collect([report(d1, day: day), report(d2, day: day + 86_400)])
        #expect(u.map(\.name) == ["notion.so", "Linear"])
        #expect(u[0].kind == .site && u[0].pattern == "notion.so" && u[0].via == "Google Chrome")
        #expect(u[0].blocks == 2 && u[0].total == 4200)
        #expect(u[1].kind == .app && u[1].pattern == "linear" && u[1].via == nil)
        // Raycast's 30 s is under the minimum; Notes was put in Uncategorized by hand.
    }
}

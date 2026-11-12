import Domain
import Foundation
import Store

// Usage: dayline-report [YYYY-MM-DD]   (default: today)
// Prints the day's raw segments and totals from the Dayline database.

let cal = Calendar.current
var day = cal.startOfDay(for: Date())
if CommandLine.arguments.count > 1 {
    guard let d = try? Date(CommandLine.arguments[1], strategy: .iso8601.year().month().day()) else {
        print("usage: dayline-report [YYYY-MM-DD]")
        exit(2)
    }
    day = cal.startOfDay(for: d)
}
let from = Int64(day.timeIntervalSince1970)
let to = Int64(cal.date(byAdding: .day, value: 1, to: day)!.timeIntervalSince1970)

let segments: [Segment]
do {
    segments = try SegmentStore(database: DaylineDatabase()).segments(from: from, to: to)
} catch {
    print("cannot read \(DaylineDatabase.defaultURL.path): \(error)")
    exit(1)
}

let time = Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute().second()
func clock(_ t: Int64) -> String { Date(timeIntervalSince1970: TimeInterval(t)).formatted(time) }
func duration(_ s: Int64) -> String {
    s >= 3600 ? "\(s / 3600)h \(String(format: "%02d", s % 3600 / 60))m"
        : s >= 60 ? "\(s / 60)m \(String(format: "%02d", s % 60))s" : "\(s)s"
}
func pad(_ s: String, _ n: Int) -> String { s.count >= n ? String(s.prefix(n)) : s + String(repeating: " ", count: n - s.count) }

for s in segments {
    let what: String
    switch s.kind {
    case .active: what = "\(pad(s.appName, 16)) \(pad(s.host ?? "", 24)) \(s.title ?? "")"
    case .away: what = "AWAY"
    case .untracked: what = "NOT TRACKED"
    }
    print("\(clock(s.start))–\(clock(s.end))  \(pad(duration(s.end - s.start), 8)) \(s.call ? "☎ " : "  ")\(what.prefix(110))")
}

var totals: [SegmentKind: Int64] = [:]
var byApp: [String: Int64] = [:]
for s in segments {
    let len = min(s.end, to) - max(s.start, from)
    totals[s.kind, default: 0] += len
    if s.kind == .active { byApp[s.appName, default: 0] += len }
}
print("\n\(segments.count) segments · active \(duration(totals[.active] ?? 0)) · away \(duration(totals[.away] ?? 0)) · not tracked \(duration(totals[.untracked] ?? 0))")
for (app, secs) in byApp.sorted(by: { $0.value > $1.value }).prefix(8) {
    print("  \(pad(app, 20)) \(duration(secs))")
}

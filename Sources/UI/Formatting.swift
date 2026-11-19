import Domain
import Foundation

enum Fmt {
    static func date(_ t: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(t)) }

    /// "9:05", "14:40": no leading zero, as in the designs; 12 h locales get "2:40 PM".
    static func clock(_ t: Int64) -> String {
        clockFormatter.string(from: date(t))
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        let uses12h = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false
        f.dateFormat = uses12h ? "h:mm a" : "H:mm"
        return f
    }()

    /// "14:40 – 15:00", or "15:35 – now" for an open block.
    static func range(_ start: Int64, _ end: Int64, open: Bool = false) -> String {
        "\(clock(start)) – \(open ? "now" : clock(end))"
    }

    /// "THURSDAY · 12 NOVEMBER"
    static func dayEyebrow(_ dayStart: Int64) -> String {
        let d = date(dayStart)
        let weekday = d.formatted(.dateTime.weekday(.wide))
        let dayMonth = d.formatted(.dateTime.day().month(.wide))
        return "\(weekday) · \(dayMonth)".uppercased()
    }

    /// "NOVEMBER 2026".
    static func monthEyebrow(_ monthStart: Int64) -> String {
        date(monthStart).formatted(.dateTime.month(.wide).year()).uppercased()
    }

    /// "9 – 15 NOVEMBER", or "27 OCTOBER – 2 NOVEMBER" across months.
    static func weekEyebrow(_ weekStart: Int64) -> String {
        let start = date(weekStart)
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start)!
        let sameMonth = Calendar.current.isDate(start, equalTo: end, toGranularity: .month)
        let first = sameMonth ? start.formatted(.dateTime.day()) : start.formatted(.dateTime.day().month(.wide))
        return "\(first) – \(end.formatted(.dateTime.day().month(.wide)))".uppercased()
    }

    /// "20 minutes", "1 hour 5 minutes" (inspector subtitle).
    static func longDuration(_ seconds: Int64) -> String {
        let m = max(0, seconds) / 60
        let h = m / 60, r = m % 60
        let mins = "\(r) minute\(r == 1 ? "" : "s")"
        guard h > 0 else { return m == 0 ? "Under a minute" : mins }
        let hours = "\(h) hour\(h == 1 ? "" : "s")"
        return r == 0 ? hours : "\(hours) \(mins)"
    }

    /// "50 min", "1h 05m" (popover card, total subtitle).
    static func minutes(_ seconds: Int64) -> String {
        seconds >= 3600 ? Durations.format(seconds) : "\(max(0, seconds) / 60) min"
    }
}


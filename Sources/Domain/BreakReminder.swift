import Foundation

/// "Time for a break": how long you've been at your Mac since your last
/// break. A break is time away (idle, locked, asleep, or Dayline off) of at
/// least `minimumBreak`; shorter pauses don't reset the clock.
public enum BreakReminder {
    public static let minimumBreak: Int64 = 2 * 60
    public static let choices = [30, 45, 60, 90]

    /// When the current stretch at the Mac began, or nil when you're away
    /// right now. `segments` are in time order.
    public static func stretchStart(segments: [Segment], now: Int64) -> Int64? {
        guard let last = segments.last, last.kind == .active, now - last.end < minimumBreak else { return nil }
        var start = last.start
        for s in segments.reversed() {
            // A gap between segments is time Dayline didn't see you either.
            if start - s.end >= minimumBreak { break }
            if s.kind != .active {
                if s.end - s.start >= minimumBreak { break }
            }
            start = min(start, s.start)
        }
        return start
    }

    /// "Time for a break" / "62 minutes at your Mac. …"
    public static func text(minutes: Int64) -> (title: String, body: String) {
        ("Time for a break", "\(minutes) minutes at your Mac. Stand up, stretch or walk for a few minutes.")
    }
}

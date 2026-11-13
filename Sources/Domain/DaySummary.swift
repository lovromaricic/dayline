import Foundation

/// Everything the popover shows about one day. Derived from the same blocks
/// as the timeline window (DayReport), so the two always agree.
public struct DaySummary: Equatable, Sendable {
    public struct Rail: Equatable, Sendable {
        public var category: ActivityCategory
        public var total: Int64
        /// The category's blocks, as time ranges.
        public var bars: [ClosedRange<Int64>]
    }

    /// What the user is in right now (see DayReport.current).
    public struct Current: Equatable, Sendable {
        public var title: String
        public var appName: String
        public var category: ActivityCategory
        public var since: Int64
    }

    public var tracked: Int64
    public var away: Int64
    /// Past 9 h or 10 h, for the menu bar ring and the popover note.
    public var length: DayLength
    /// One rail per timeline lane (categories with a minute or more), largest first.
    public var rails: [Rail]
    public var untracked: [ClosedRange<Int64>]
    public var current: Current?
    /// Same axis as the timeline: 8:00–17:00, widened to whole hours to fit the data.
    public var axis: ClosedRange<Int64>

    public init(report r: DayReport) {
        tracked = r.tracked
        away = r.awayTotal
        rails = r.lanes.map { Rail(category: $0.category, total: $0.total, bars: $0.blocks.map { $0.start...$0.end }) }
        untracked = r.untracked
        axis = r.axis
        current = r.current
        // Films and music in the evening do not make a long working day.
        let entertainment = rails.first { $0.category.id == ActivityCategory.entertainment.id }?.total ?? 0
        length = DayLength(tracked: tracked - entertainment)
    }

    public init(segments: [Segment], dayStart: Int64, now: Int64, category: (Segment) -> ActivityCategory) {
        self.init(report: DayReport(segments: segments, dayStart: dayStart, now: now, category: category))
    }

    public init(segments: [Segment], dayStart: Int64, now: Int64, resolve: (Segment) -> CategoryResolution) {
        self.init(report: DayReport(segments: segments, dayStart: dayStart, now: now, resolve: resolve))
    }
}

/// Spec 5.1: the ring stays lime up to 9 h, turns amber for a long day and
/// red past 10 h. Entertainment does not count.
public enum DayLength: Equatable, Sendable {
    case normal, long, veryLong

    public static let longAfter: Int64 = 9 * 3600
    public static let veryLongAfter: Int64 = 10 * 3600

    public init(tracked: Int64) {
        self = tracked >= Self.veryLongAfter ? .veryLong : tracked >= Self.longAfter ? .long : .normal
    }
}

public enum Durations {
    /// Spec 7: "6h 45m", "52m", "2h 00m"; no seconds.
    public static func format(_ seconds: Int64) -> String {
        let m = max(0, seconds) / 60
        return m >= 60 ? "\(m / 60)h \(String(format: "%02d", m % 60))m" : "\(m)m"
    }
}

import Foundation

/// Everything the popover shows about one day, derived from raw segments.
public struct DaySummary: Equatable, Sendable {
    public struct Rail: Equatable, Sendable {
        public var category: ActivityCategory
        public var total: Int64
        /// Merged bars; gaps under 60 s are bridged (spec 3.1).
        public var bars: [ClosedRange<Int64>]
    }

    /// The block the user is in right now.
    public struct Current: Equatable, Sendable {
        public var title: String
        public var appName: String
        public var category: ActivityCategory
        public var since: Int64
    }

    public var tracked: Int64 = 0
    public var away: Int64 = 0
    /// One rail per category with time today, largest first.
    public var rails: [Rail] = []
    public var untracked: [ClosedRange<Int64>] = []
    public var current: Current?
    /// Axis: the workday 8:00–17:00, widened to whole hours to fit the data.
    public var axis: ClosedRange<Int64>

    static let mergeGap: Int64 = 60

    public init(segments: [Segment], dayStart: Int64, now: Int64, category: (Segment) -> ActivityCategory) {
        let dayEnd = dayStart + 86_400
        var lo = dayStart + 8 * 3600, hi = dayStart + 17 * 3600
        let clipped = segments.compactMap { s -> Segment? in
            var s = s
            s.start = max(s.start, dayStart)
            s.end = min(s.end, dayEnd)
            return s.end > s.start ? s : nil
        }
        if let first = clipped.first { lo = min(lo, dayStart + (first.start - dayStart) / 3600 * 3600) }
        let last = max(clipped.last?.end ?? 0, min(now, dayEnd))
        if last > hi { hi = min(dayEnd, dayStart + ((last - dayStart) + 3599) / 3600 * 3600) }
        axis = lo...hi

        var order: [ActivityCategory] = []
        var totals: [ActivityCategory: Int64] = [:]
        var bars: [ActivityCategory: [ClosedRange<Int64>]] = [:]
        for s in clipped {
            switch s.kind {
            case .away:
                away += s.duration
            case .untracked:
                untracked.append(s.start...s.end)
            case .active:
                let c = category(s)
                tracked += s.duration
                if totals[c] == nil { order.append(c) }
                totals[c, default: 0] += s.duration
                var list = bars[c, default: []]
                if let prev = list.last, s.start - prev.upperBound < Self.mergeGap {
                    list[list.count - 1] = prev.lowerBound...max(prev.upperBound, s.end)
                } else {
                    list.append(s.start...s.end)
                }
                bars[c] = list
            }
        }
        rails = order.map { Rail(category: $0, total: totals[$0]!, bars: bars[$0]!) }
            .sorted { $0.total > $1.total }

        // The current block: the open active segment plus earlier ones with the
        // same app, site and category and gaps under 60 s.
        if let open = clipped.last, open.kind == .active, now - open.end <= 15 {
            let c = category(open)
            var since = open.start
            var next = open
            for s in clipped.dropLast().reversed() {
                guard s.kind == .active, next.start - s.end < Self.mergeGap, s.appBundleID == open.appBundleID,
                      s.domain == open.domain, category(s) == c else { break }
                since = s.start
                next = s
            }
            current = Current(title: open.title ?? open.appName, appName: open.appName, category: c, since: since)
        }
    }
}

public enum Durations {
    /// Spec 7: "6h 45m", "52m", "2h 00m"; no seconds.
    public static func format(_ seconds: Int64) -> String {
        let m = max(0, seconds) / 60
        return m >= 60 ? "\(m / 60)h \(String(format: "%02d", m % 60))m" : "\(m)m"
    }
}

import Foundation

/// A run of consecutive active segments with the same app, site and category
/// (spec 3.1). Derived at read time, never stored.
public struct Block: Equatable, Identifiable, Sendable {
    /// The first segment's id; stable while the block grows.
    public var id: Int64
    public var start: Int64
    public var end: Int64
    /// Active seconds (gaps under 60 s are bridged visually but not counted).
    public var duration: Int64
    public var appBundleID: String
    public var appName: String
    /// Title of the block's longest segment.
    public var title: String?
    public var host: String?
    public var domain: String?
    public var category: ActivityCategory
    /// What Dayline guessed before your rules or corrections.
    public var guess: ActivityCategory
    /// Your rule or correction decided the category ("· edited").
    public var edited: Bool
    public var segmentIDs: [Int64]
    /// The block is still growing (today, open segment).
    public var isOpen = false
}

/// Everything the main window shows about one day.
public struct DayReport: Equatable, Sendable {
    public struct Lane: Equatable, Sendable {
        public var category: ActivityCategory
        public var total: Int64
        public var blocks: [Block]
    }

    public struct AppTotal: Equatable, Sendable {
        public var appName: String
        public var total: Int64
    }

    /// The longest stretch in one app (blocks of that app with gaps < 60 s).
    public struct Focus: Equatable, Sendable {
        public var appName: String
        public var start: Int64
        public var end: Int64
        public var duration: Int64
        public var title: String?
    }

    public var dayStart: Int64
    public var isToday: Bool
    public var now: Int64
    /// Oldest first.
    public var blocks: [Block] = []
    /// One lane per category with time, largest first.
    public var lanes: [Lane] = []
    /// Breaks to hatch in charts: AWAY and not-tracked periods, with ones
    /// under 2 minutes apart joined and anything shorter than 2 minutes left
    /// out (a few idle seconds are not a break worth drawing).
    public var away: [ClosedRange<Int64>] = []
    public var untracked: [ClosedRange<Int64>] = []
    static let minBreak: Int64 = 120
    public var tracked: Int64 = 0
    public var awayTotal: Int64 = 0
    public var firstActivity: Int64?
    public var topApps: [AppTotal] = []
    public var longestFocus: Focus?
    public var axis: ClosedRange<Int64>
    /// What you are in right now, from the raw segments: blocks need a
    /// minute and may absorb a short visit into a neighbour, so they cannot
    /// say what is in front during the first minute in an app.
    public var current: DaySummary.Current?

    static let mergeGap: Int64 = 60
    static let minBlock: Int64 = 60
    /// "Stretches of 25 minutes or more in one app" (screen 05).
    public static let focusMinimum: Int64 = 25 * 60

    public init(segments: [Segment], dayStart: Int64, now: Int64, category: (Segment) -> ActivityCategory) {
        self.init(segments: segments, dayStart: dayStart, now: now) {
            let c = category($0)
            return CategoryResolution(category: c, guess: c, edited: false)
        }
    }

    public init(segments: [Segment], dayStart: Int64, now: Int64, resolve: (Segment) -> CategoryResolution) {
        self.dayStart = dayStart
        self.now = now
        let dayEnd = dayStart + 86_400
        isToday = now >= dayStart && now < dayEnd
        axis = DayReport.axis(dayStart: dayStart, segments: segments, now: isToday ? now : nil)

        let clipped = segments.compactMap { s -> Segment? in
            var s = s
            s.start = max(s.start, dayStart)
            s.end = min(s.end, dayEnd)
            return s.end > s.start ? s : nil
        }
        var appTotals: [String: Int64] = [:]
        for s in clipped {
            switch s.kind {
            case .away:
                awayTotal += s.duration
                append(&away, s.start...s.end)
            case .untracked:
                append(&untracked, s.start...s.end)
            case .active:
                tracked += s.duration
                appTotals[s.appName, default: 0] += s.duration
                firstActivity = firstActivity ?? s.start
            }
        }
        var cache: [Int64: CategoryResolution] = [:]
        for s in clipped where s.kind == .active { cache[s.id] = resolve(s) }
        let category: (Segment) -> ActivityCategory = { cache[$0.id]?.category ?? .uncategorized }
        away = DayReport.visibleBreaks(away)
        untracked = DayReport.visibleBreaks(untracked)
        blocks = DayReport.blocks(from: clipped, resolution: { cache[$0.id]! })
        // The open segment can still be zero seconds long (just resumed, just
        // switched), which clipping drops; it is still what is in front.
        if isToday, var open = segments.last, open.kind == .active, open.end >= dayStart, now - open.end <= 15 {
            open.start = max(open.start, dayStart)
            if let last = blocks.last, last.segmentIDs.contains(open.id) { blocks[blocks.count - 1].isOpen = true }
            // Since: back through segments of the same app, site and category with gaps under a minute.
            let c = cache[open.id]?.category ?? resolve(open).category
            var since = open.start
            for s in clipped.reversed() where s.id != open.id {
                guard s.kind == .active, s.appBundleID == open.appBundleID, s.domain == open.domain,
                      category(s) == c, since - s.end < DayReport.mergeGap else { break }
                since = s.start
            }
            current = DaySummary.Current(title: open.title ?? open.appName, appName: open.appName, category: c, since: since)
        }

        var order: [ActivityCategory] = []
        var laneBlocks: [ActivityCategory: [Block]] = [:]
        var laneTotals: [ActivityCategory: Int64] = [:]
        for s in clipped where s.kind == .active {
            let c = category(s)
            if laneTotals[c] == nil { order.append(c) }
            laneTotals[c, default: 0] += s.duration
        }
        for b in blocks { laneBlocks[b.category, default: []].append(b) }
        // A category needs at least one block (a minute or more in one go) to
        // get a lane; a few glances still count in `tracked`.
        lanes = order.filter { laneBlocks[$0] != nil }
            .map { Lane(category: $0, total: laneTotals[$0]!, blocks: laneBlocks[$0] ?? []) }
            .sorted { $0.total > $1.total }

        topApps = appTotals.filter { $0.value >= DayReport.minBlock }.map { AppTotal(appName: $0.key, total: $0.value) }
            .sorted { $0.total != $1.total ? $0.total > $1.total : $0.appName < $1.appName }
        longestFocus = DayReport.longestFocus(blocks)
    }

    /// The workday 8:00–17:00, widened to whole hours to fit the data.
    public static func axis(dayStart: Int64, segments: [Segment], now: Int64?) -> ClosedRange<Int64> {
        let dayEnd = dayStart + 86_400
        var lo = dayStart + 8 * 3600, hi = dayStart + 17 * 3600
        if let first = segments.map({ max($0.start, dayStart) }).min(), first < dayEnd {
            lo = min(lo, dayStart + (first - dayStart) / 3600 * 3600)
        }
        let last = max(segments.map { min($0.end, dayEnd) }.max() ?? 0, now.map { min($0, dayEnd) } ?? 0)
        if last > hi { hi = min(dayEnd, dayStart + ((last - dayStart) + 3599) / 3600 * 3600) }
        return lo...hi
    }

    /// Spec 3.1: merge same app + site + category with gaps < 60 s; blocks
    /// under a minute are absorbed into a touching block of the same category,
    /// otherwise dropped from the list (they still count in totals).
    static func blocks(from segments: [Segment], resolution: (Segment) -> CategoryResolution) -> [Block] {
        var runs: [Block] = []
        var longest: [Int64: Int64] = [:]  // block id -> longest segment duration
        var lastKind: SegmentKind?
        for s in segments {
            defer { lastKind = s.kind }
            guard s.kind == .active else { continue }
            let res = resolution(s)
            let c = res.category
            if var last = runs.last, lastKind == .active, last.appBundleID == s.appBundleID, last.domain == s.domain,
               last.category == c, s.start - last.end < mergeGap {
                last.end = max(last.end, s.end)
                last.duration += s.duration
                last.segmentIDs.append(s.id)
                last.edited = last.edited || res.edited
                if s.duration > longest[last.id, default: 0] {
                    longest[last.id] = s.duration
                    last.title = s.title
                }
                runs[runs.count - 1] = last
            } else {
                runs.append(Block(id: s.id, start: s.start, end: s.end, duration: s.duration, appBundleID: s.appBundleID,
                                  appName: s.appName, title: s.title, host: s.host, domain: s.domain, category: c,
                                  guess: res.guess, edited: res.edited, segmentIDs: [s.id]))
                longest[s.id] = s.duration
            }
        }

        // Absorb or drop short runs.
        var kept: [Block] = []
        for i in runs.indices {
            let run = runs[i]  // may have absorbed a short run just before it
            if run.duration >= minBlock { kept.append(run); continue }
            if var prev = kept.last, prev.category == run.category, run.start - prev.end < mergeGap {
                prev.end = max(prev.end, run.end)
                prev.duration += run.duration
                prev.segmentIDs += run.segmentIDs
                prev.edited = prev.edited || run.edited
                kept[kept.count - 1] = prev
            } else if i + 1 < runs.count, runs[i + 1].category == run.category, runs[i + 1].start - run.end < mergeGap {
                runs[i + 1].start = run.start
                runs[i + 1].duration += run.duration
                runs[i + 1].segmentIDs = run.segmentIDs + runs[i + 1].segmentIDs
                runs[i + 1].edited = runs[i + 1].edited || run.edited
                runs[i + 1].id = run.id
            }
        }
        // Dropping a short interruption leaves two halves of the same block; join them.
        var merged: [Block] = []
        for b in kept {
            if var last = merged.last, last.appBundleID == b.appBundleID, last.domain == b.domain,
               last.category == b.category, b.start - last.end < mergeGap {
                last.end = b.end
                last.duration += b.duration
                last.segmentIDs += b.segmentIDs
                last.edited = last.edited || b.edited
                if b.duration > last.duration - b.duration { last.title = b.title }
                merged[merged.count - 1] = last
            } else {
                merged.append(b)
            }
        }
        return merged
    }

    static func longestFocus(_ blocks: [Block]) -> Focus? {
        var best: Focus?
        var cur: Focus?
        var curTitleLen: Int64 = 0
        for b in blocks {
            if var c = cur, c.appName == b.appName, b.start - c.end < mergeGap {
                c.end = b.end
                c.duration += b.duration
                if b.duration > curTitleLen { c.title = b.title; curTitleLen = b.duration }
                cur = c
            } else {
                cur = Focus(appName: b.appName, start: b.start, end: b.end, duration: b.duration, title: b.title)
                curTitleLen = b.duration
            }
            if let c = cur, c.duration > (best?.duration ?? 0) { best = c }
        }
        return best.flatMap { $0.duration >= focusMinimum ? $0 : nil }
    }

    static func visibleBreaks(_ list: [ClosedRange<Int64>]) -> [ClosedRange<Int64>] {
        var joined: [ClosedRange<Int64>] = []
        for r in list {
            if let last = joined.last, r.lowerBound - last.upperBound < minBreak {
                joined[joined.count - 1] = last.lowerBound...max(last.upperBound, r.upperBound)
            } else {
                joined.append(r)
            }
        }
        return joined.filter { $0.upperBound - $0.lowerBound >= minBreak }
    }

    private func append(_ list: inout [ClosedRange<Int64>], _ r: ClosedRange<Int64>) {
        if let last = list.last, r.lowerBound <= last.upperBound {
            list[list.count - 1] = last.lowerBound...max(last.upperBound, r.upperBound)
        } else {
            list.append(r)
        }
    }

    // MARK: - Words

    /// The two-line generated summary (spec 5.3): bold first line, muted second.
    /// `trackingNow`: false while paused or without permission, so a fresh
    /// day does not claim "Tracking is on."
    public func headline(trackingNow: Bool = true, calendar: Calendar = .current) -> (String, String) {
        guard tracked > 0 else {
            return isToday ? ("Nothing tracked yet today.", "Your first blocks appear within a minute.")
                : ("Nothing was tracked this day.", "Dayline was off, paused or away.")
        }
        if isToday && tracked < 30 * 60 && trackingNow { return ("Tracking is on.", "Your first blocks are already forming.") }
        let when = isToday ? (now - dayStart < 17 * 3600 ? " so far" : " today") : ""
        let first: String
        guard let top = lanes.first else { return ("Only short moments\(when).", "Blocks appear once something lasts a minute.") }
        if Double(top.total) >= 0.4 * Double(tracked) || lanes.count == 1 {
            first = "Mostly \(top.category.name)\(when),"
        } else {
            first = "A mix of \(lanes[0].category.name) and \(lanes[1].category.name)\(when),"
        }
        guard let focus = longestFocus else { return (first, "in short stretches.") }
        let hour = calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(focus.start)))
        let part = switch hour {
        case ..<10: "first thing"
        case ..<12: "in the morning"
        case ..<15: "after lunch"
        case ..<18: "in the afternoon"
        default: "in the evening"
        }
        return (first, "with a long focus block \(part).")
    }
}

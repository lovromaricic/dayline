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
    /// Set when the block is a whole call: what was in front during it.
    public var call: CallDetail?
}

/// A call that counts as one Meetings block, and the proof of what you did on it.
public struct CallDetail: Equatable, Sendable {
    /// "Slack huddle with Alex", "Google Meet", "Zoom call"…
    public var name: String
    /// What was in front, in time order: the strip inside the call's bar.
    public var parts: [Part] = []
    /// The same by app or site, largest first, in whole minutes adding up to the block.
    public var totals: [Part] = []

    public struct Part: Equatable, Sendable {
        public var start: Int64
        public var end: Int64
        /// Active seconds; whole minutes in `totals`.
        public var duration: Int64
        /// The window or tab title ("Novi kreditni accounti"), else the site or
        /// app; "Slack huddle window" for the call's own window (the call is
        /// the whole block, not just this part).
        public var label: String
        /// Where the title is from ("figma.com", "Figma"); nil when the label says it.
        public var source: String?
        /// What it is outside the call: Figma stays Design here.
        public var category: ActivityCategory

        init(start: Int64, end: Int64, duration: Int64, label: String, source: String? = nil, category: ActivityCategory) {
            self.start = start
            self.end = end
            self.duration = duration
            self.label = label
            self.source = source
            self.category = category
        }
    }

    mutating func add(_ p: Part) {
        if let last = parts.last, last.label == p.label, last.category == p.category, p.start - last.end < DayReport.mergeGap {
            parts[parts.count - 1].end = p.end
            parts[parts.count - 1].duration += p.duration
        } else {
            parts.append(p)
        }
    }

    /// `totals` from `parts`, rounded so they add up to the block's minutes.
    mutating func total(to minutes: Int64) {
        var keys: [String] = []
        var sums: [String: Part] = [:]
        for p in parts {
            let key = "\(p.label)|\(p.category.id)"
            if sums[key] == nil { keys.append(key); sums[key] = p } else { sums[key]!.duration += p.duration }
        }
        var list = keys.map { sums[$0]! }
        for (i, m) in DayReport.wholeMinutes(list.map(\.duration)).enumerated() { list[i].duration = m }
        list.sort { $0.duration > $1.duration }
        // Gaps under a minute are bridged in the block but not here; settle the difference on the largest.
        if !list.isEmpty { list[0].duration = max(0, list[0].duration + minutes - list.reduce(0) { $0 + $1.duration }) }
        totals = list.filter { $0.duration > 0 }
    }
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
    /// Never a call: Meetings blocks are left out.
    public var longestFocus: Focus?
    /// Calls of 25 minutes or more, oldest first, for the headline.
    public var longCalls: [Focus] = []
    public var axis: ClosedRange<Int64>
    /// Calls of 2 minutes or more, oldest first, whether they count as a
    /// whole (one Meetings block) or were split into what you were doing.
    public var calls: [Call] = []

    public struct Call: Equatable, Sendable {
        public var start: Int64
        public var end: Int64
        /// "Slack huddle", "Google Meet"…
        public var name: String
        /// Who was on it, where the window says: "Alex, Sam".
        public var people: String?
        public var segmentIDs: [Int64]
        /// "Slack huddle with Alex, Sam".
        public var title: String { people.map { "\(name) with \($0)" } ?? name }
        /// You split it into what you were doing ("What I was doing").
        public var split = false
    }
    /// What you are in right now, from the raw segments: blocks need a
    /// minute and may absorb a short visit into a neighbour, so they cannot
    /// say what is in front during the first minute in an app.
    public var current: DaySummary.Current?

    static let mergeGap: Int64 = 60
    static let minBlock: Int64 = 60
    /// A shorter mic run (dictation, a quick voice note) is not a call.
    static let minCall: Int64 = 120
    /// "Stretches of 25 minutes or more in one app" (screen 05).
    public static let focusMinimum: Int64 = 25 * 60

    public init(segments: [Segment], dayStart: Int64, now: Int64, category: (Segment) -> ActivityCategory) {
        self.init(segments: segments, dayStart: dayStart, now: now) {
            let c = category($0)
            return CategoryResolution(category: c, guess: c, edited: false,
                                      wholeCall: $0.wholeCall && c.id == ActivityCategory.meetings.id)
        }
    }

    public init(segments: [Segment], dayStart: Int64, now: Int64, resolve: (Segment) -> CategoryResolution) {
        self.dayStart = dayStart
        self.now = now
        let dayEnd = dayStart + 86_400
        isToday = now >= dayStart && now < dayEnd
        axis = DayReport.axis(dayStart: dayStart, segments: segments, now: isToday ? now : nil)

        var raw = segments.compactMap { s -> Segment? in
            var s = s
            s.start = max(s.start, dayStart)
            s.end = min(s.end, dayEnd)
            return s.end > s.start ? s : nil
        }
        // Calls from the raw flags, which cover every segment while the mic
        // was on; then the flags narrow to where each call took place.
        calls = DayReport.calls(in: raw)
        let inCall = Set(calls.flatMap(\.segmentIDs))
        for i in raw.indices where inCall.contains(raw[i].id) { raw[i].wholeCall = true }
        let clipped = Segment.narrowingCalls(raw)
        let callNames = Dictionary(calls.flatMap { c in c.segmentIDs.map { ($0, c) } }, uniquingKeysWith: { a, _ in a })
        for s in clipped {
            switch s.kind {
            case .away:
                append(&away, s.start...s.end)
            case .untracked:
                append(&untracked, s.start...s.end)
            case .active:
                firstActivity = firstActivity ?? s.start
            }
        }
        // Breaks while you were working, not the night: away time from the
        // first activity to the last (to now, today, so a break you are on counts).
        let active = clipped.filter { $0.kind == .active }
        if let first = active.first?.start, let lastActive = active.map(\.end).max() {
            let last = isToday ? max(lastActive, now) : lastActive
            awayTotal = clipped.filter { $0.kind == .away }
                .reduce(0) { $0 + max(0, min($1.end, last) - max($1.start, first)) }
        }
        var cache: [Int64: CategoryResolution] = [:]
        for s in clipped where s.kind == .active { cache[s.id] = resolve(s) }
        let pinned = Set(clipped.filter { $0.wholeCall && $0.manualCategoryID != nil }.map(\.id))
        for i in calls.indices { calls[i].split = calls[i].segmentIDs.contains(where: pinned.contains) }
        let category: (Segment) -> ActivityCategory = { cache[$0.id]?.category ?? .uncategorized }
        away = DayReport.visibleBreaks(away)
        untracked = DayReport.visibleBreaks(untracked)
        blocks = DayReport.blocks(from: clipped, resolution: { cache[$0.id]! }, proof: { s in
            // What the segment is outside the call.
            var plain = s
            plain.wholeCall = false
            let call = callNames[s.id]
            return (call?.name ?? "Call", call?.title ?? "Call", resolve(plain).category)
        })
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

        // Every number comes from the blocks, in whole minutes, so the blocks
        // add up to their row, the rows and the top apps to the total. Time
        // that never made a block (glances under a minute) is left out.
        for (i, m) in DayReport.wholeMinutes(blocks.map(\.duration)).enumerated() {
            blocks[i].duration = m
            blocks[i].call?.total(to: m)
        }
        var order: [ActivityCategory] = []
        var laneBlocks: [ActivityCategory: [Block]] = [:]
        var apps: [String] = []
        var appTotals: [String: Int64] = [:]
        for b in blocks {
            if laneBlocks[b.category] == nil { order.append(b.category) }
            laneBlocks[b.category, default: []].append(b)
            if appTotals[b.appName] == nil { apps.append(b.appName) }
            appTotals[b.appName, default: 0] += b.duration
        }
        lanes = order.map { c in Lane(category: c, total: laneBlocks[c]!.reduce(0) { $0 + $1.duration }, blocks: laneBlocks[c]!) }
            .enumerated().sorted { $0.element.total != $1.element.total ? $0.element.total > $1.element.total : $0.offset < $1.offset }
            .map(\.element)
        tracked = lanes.reduce(0) { $0 + $1.total }
        topApps = apps.map { AppTotal(appName: $0, total: appTotals[$0]!) }
            .sorted { $0.total != $1.total ? $0.total > $1.total : $0.appName < $1.appName }
        longestFocus = DayReport.longestFocus(blocks.filter { $0.category.id != ActivityCategory.meetings.id })
        longCalls = DayReport.stretches(blocks.filter { $0.category.id == ActivityCategory.meetings.id })
            .filter { $0.duration >= DayReport.focusMinimum }
    }

    /// Seconds rounded to whole minutes (as seconds) so they add up to the
    /// minutes in their sum: each rounds down, then the leftover minutes go
    /// to the largest remainders.
    static func wholeMinutes(_ seconds: [Int64]) -> [Int64] {
        var minutes = seconds.map { $0 / 60 }
        let leftover = Int(seconds.reduce(0, +) / 60 - minutes.reduce(0, +))
        let byRemainder = seconds.indices.sorted { seconds[$0] % 60 != seconds[$1] % 60 ? seconds[$0] % 60 > seconds[$1] % 60 : $0 < $1 }
        for i in byRemainder.prefix(leftover) { minutes[i] += 1 }
        return minutes.map { $0 * 60 }
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
    /// A whole call is one block, whatever app was in front; `proof` gives its
    /// name and what each of its segments is outside the call.
    static func blocks(from segments: [Segment], resolution: (Segment) -> CategoryResolution,
                       proof: (Segment) -> (name: String, title: String, category: ActivityCategory) = { _ in ("Call", "Call", .meetings) }) -> [Block] {
        var runs: [Block] = []
        var longest: [Int64: Int64] = [:]  // block id -> longest segment duration
        var lastKind: SegmentKind?
        for s in segments {
            defer { lastKind = s.kind }
            guard s.kind == .active else { continue }
            let res = resolution(s)
            let c = res.category
            let call = res.wholeCall ? proof(s) : nil
            let part = call.map { call -> CallDetail.Part in
                let place = s.domain ?? s.appName
                let title = s.title.map(Titles.withoutAppSuffix).flatMap { $0.isEmpty ? nil : $0 }
                return call.category == c
                    ? CallDetail.Part(start: s.start, end: s.end, duration: s.duration, label: "\(call.name) window", category: call.category)
                    : CallDetail.Part(start: s.start, end: s.end, duration: s.duration, label: title ?? place,
                                      source: title == nil ? nil : place, category: call.category)
            }
            if var last = runs.last, lastKind == .active, last.category == c, s.start - last.end < mergeGap,
               (last.call != nil) == (part != nil),
               part != nil || (last.appBundleID == s.appBundleID && last.domain == s.domain) {
                last.end = max(last.end, s.end)
                last.duration += s.duration
                last.segmentIDs.append(s.id)
                last.edited = last.edited || res.edited
                if let part {
                    last.call?.add(part)
                } else if s.duration > longest[last.id, default: 0] {
                    longest[last.id] = s.duration
                    last.title = s.title
                }
                runs[runs.count - 1] = last
            } else {
                var b = Block(id: s.id, start: s.start, end: s.end, duration: s.duration, appBundleID: s.appBundleID,
                              appName: s.appName, title: call?.title ?? s.title, host: call == nil ? s.host : nil,
                              domain: call == nil ? s.domain : nil, category: c, guess: res.guess, edited: res.edited,
                              segmentIDs: [s.id])
                if let call, let part { b.call = CallDetail(name: call.title, parts: [part]) }
                runs.append(b)
                longest[s.id] = s.duration
            }
        }

        // Absorb or drop short runs.
        var kept: [Block] = []
        for i in runs.indices {
            let run = runs[i]  // may have absorbed a short run just before it
            if run.duration >= minBlock { kept.append(run); continue }
            // A call's bits stay with the call; nothing else joins it.
            if run.call != nil { continue }
            if var prev = kept.last, prev.call == nil, prev.category == run.category, run.start - prev.end < mergeGap {
                prev.end = max(prev.end, run.end)
                prev.duration += run.duration
                prev.segmentIDs += run.segmentIDs
                prev.edited = prev.edited || run.edited
                kept[kept.count - 1] = prev
            } else {
                // Forward, past short glances at something else (a call's first
                // seconds, then a peek at Chrome, then the rest of the call).
                var j = i + 1
                while j < runs.count, runs[j].category != run.category, runs[j].duration < minBlock,
                      runs[j].start - run.end < mergeGap { j += 1 }
                guard j < runs.count, runs[j].call == nil, runs[j].category == run.category,
                      runs[j].start - run.end < mergeGap else { continue }
                runs[j].start = run.start
                runs[j].duration += run.duration
                runs[j].segmentIDs = run.segmentIDs + runs[j].segmentIDs
                runs[j].edited = runs[j].edited || run.edited
                runs[j].id = run.id
            }
        }
        // Dropping a short interruption leaves two halves of the same block; join them.
        var merged: [Block] = []
        for b in kept {
            if var last = merged.last, last.call == nil, b.call == nil, last.appBundleID == b.appBundleID,
               last.domain == b.domain, last.category == b.category, b.start - last.end < mergeGap {
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

    /// Runs of call-flagged segments (the raw flags, before narrowing) with
    /// gaps under a minute, named after where the call took place.
    static func calls(in segments: [Segment]) -> [Call] {
        var runs: [[Segment]] = []
        var open = false
        for s in segments {
            guard s.kind == .active, s.call else { open = false; continue }
            if open, let last = runs.last?.last, s.start - last.end < mergeGap {
                runs[runs.count - 1].append(s)
            } else {
                runs.append([s])
            }
            open = true
        }
        return runs.filter { $0.last!.end - $0.first!.start >= minCall }.map { run in
            let names = run.map { Titles.callName(appBundleID: $0.appBundleID, appName: $0.appName, host: $0.host, title: $0.title) }
            let people = run.lazy.compactMap { Titles.callPeople(host: $0.host, title: $0.title) }.first
            return Call(start: run.first!.start, end: run.last!.end, name: names.first { !$0.hasPrefix("Call in ") } ?? names[0],
                        people: people, segmentIDs: run.map(\.id))
        }
    }

    static func longestFocus(_ blocks: [Block]) -> Focus? {
        stretches(blocks).max { $0.duration < $1.duration }.flatMap { $0.duration >= focusMinimum ? $0 : nil }
    }

    /// Blocks in one app with gaps under a minute, joined; oldest first.
    static func stretches(_ blocks: [Block]) -> [Focus] {
        var all: [Focus] = []
        var titleLength: Int64 = 0
        for b in blocks {
            if var c = all.last, c.appName == b.appName, b.start - c.end < mergeGap {
                c.end = b.end
                c.duration += b.duration
                if b.duration > titleLength { c.title = b.title; titleLength = b.duration }
                all[all.count - 1] = c
            } else {
                all.append(Focus(appName: b.appName, start: b.start, end: b.end, duration: b.duration, title: b.title))
                titleLength = b.duration
            }
        }
        return all
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
        // firstActivity, not tracked: a day of only glances has a zero total
        // but is not empty.
        guard firstActivity != nil else {
            return isToday ? ("Nothing tracked yet today.", "Your first blocks appear within a minute.")
                : ("Nothing was tracked this day.", "Dayline was off, paused or away.")
        }
        if isToday && tracked < 30 * 60 && trackingNow { return ("Tracking is on.", "Your first blocks are already forming.") }
        let when = isToday ? (now - dayStart < 17 * 3600 ? " so far" : " today") : ""
        let first: String
        guard let top = lanes.first else { return ("Only short moments\(when).", "Blocks appear once something lasts a minute.") }
        if Double(top.total) >= 0.4 * Double(tracked) || lanes.count == 1 {
            first = "Mostly \(top.category.shortName)\(when),"
        } else {
            first = "A mix of \(lanes[0].category.shortName) and \(lanes[1].category.shortName)\(when),"
        }
        // Focus wins over calls; a call is never called focus.
        guard let focus = longestFocus ?? longCalls.first else { return (first, "in short stretches.") }
        if longestFocus == nil, longCalls.count > 2 { return (first, "with long calls all day.") }
        if longestFocus == nil, longCalls.count == 2 { return (first, "with two long calls.") }
        let hour = calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(focus.start)))
        let part = switch hour {
        case ..<10: "first thing"
        case ..<12: "in the morning"
        case ..<15: "after lunch"
        case ..<18: "in the afternoon"
        default: "in the evening"
        }
        return (first, longestFocus == nil ? "with one long call \(part)." : "with a long focus block \(part).")
    }
}

import Foundation

/// "Export hours": a client's or project's time as rows for an invoice, from
/// the same blocks the app shows, so the totals match.
public struct Timesheet: Equatable, Sendable {
    public enum Grouping: String, CaseIterable, Sendable {
        case day = "Day"
        case week = "Week"
        case month = "Month"
        case block = "Block"
    }

    public struct Row: Equatable, Sendable {
        /// "2026-11-02"; a week or month row uses its first day; a block, its day.
        public var date: String
        /// "09:05–10:35" for a block row, else nil.
        public var time: String?
        public var client: String
        public var project: String
        /// After rounding.
        public var seconds: Int64
        public var rate: Double?
        public var currency: String
        /// Block rows: what it was ("Kreditni limiti – FigJam").
        public var title: String?
        /// Your notes on those blocks, joined.
        public var notes: String

        public var hours: Double { Double(seconds) / 3600 }
        public var amount: Double? { rate.map { (hours * $0 * 100).rounded() / 100 } }
        /// "1:45"
        public var clock: String { "\(seconds / 3600):" + String(format: "%02d", (seconds % 3600) / 60) }
    }

    public var rows: [Row]
    /// Before rounding, for "Rounded from 34h 20m".
    public var unrounded: Int64

    public var seconds: Int64 { rows.reduce(0) { $0 + $1.seconds } }
    /// Per currency, for the total row: ["EUR": 2253.75].
    public var amounts: [String: Double] {
        rows.reduce(into: [:]) { t, r in if let a = r.amount { t[r.currency, default: 0] += a } }
    }

    /// `days`: each day's start and its blocks (with projects); `include`
    /// picks the client's or project's blocks. `round` is in minutes, 0 for none.
    public init(days: [(dayStart: Int64, blocks: [Block])], include: (Project) -> Bool, grouping: Grouping,
                round: Int, calendar: Calendar = .current) {
        struct Key: Hashable { var period: Int64; var project: Int64; var block: Int64 }
        var order: [Key] = []
        var seconds: [Key: Int64] = [:]
        var info: [Key: (Project, Block)] = [:]
        var notes: [Key: [String]] = [:]
        var unrounded: Int64 = 0
        for (dayStart, blocks) in days.sorted(by: { $0.dayStart < $1.dayStart }) {
            let date = Date(timeIntervalSince1970: TimeInterval(dayStart))
            let period: Int64 = switch grouping {
            case .day, .block: dayStart
            case .week: Int64((calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date).timeIntervalSince1970)
            case .month: Int64((calendar.dateInterval(of: .month, for: date)?.start ?? date).timeIntervalSince1970)
            }
            for b in blocks.sorted(by: { $0.start < $1.start }) {
                guard let p = b.project, include(p) else { continue }
                let key = Key(period: period, project: p.id, block: grouping == .block ? b.id : 0)
                if seconds[key] == nil { order.append(key); info[key] = (p, b) }
                seconds[key, default: 0] += b.duration
                unrounded += b.duration
                if let n = b.note, !(notes[key] ?? []).contains(n) { notes[key, default: []].append(n) }
            }
        }
        let iso = DateFormatter()
        iso.calendar = calendar
        iso.dateFormat = "yyyy-MM-dd"
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm"
        rows = order.map { key in
            let (p, b) = info[key]!
            return Row(date: iso.string(from: Date(timeIntervalSince1970: TimeInterval(key.period))),
                       time: grouping == .block
                           ? "\(clock.string(from: Date(timeIntervalSince1970: TimeInterval(b.start))))–\(clock.string(from: Date(timeIntervalSince1970: TimeInterval(b.end))))"
                           : nil,
                       client: p.clientName ?? "", project: p.name,
                       seconds: Self.rounded(seconds[key]!, to: round), rate: p.hourlyRate, currency: p.currency,
                       title: grouping == .block ? (b.title ?? b.appName) : nil,
                       notes: (notes[key] ?? []).joined(separator: "; "))
        }
        self.unrounded = unrounded
    }

    /// To the nearest step; anything worked counts as at least one step.
    static func rounded(_ seconds: Int64, to minutes: Int) -> Int64 {
        guard minutes > 0 else { return seconds }
        let step = Int64(minutes) * 60
        return max(step, (seconds + step / 2) / step * step)
    }
}

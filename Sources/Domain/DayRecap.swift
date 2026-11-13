import Foundation

/// The end-of-day notification (spec 5.5): the day's total as the title and
/// the one most notable thing about it underneath. Neutral and factual, and
/// app names only: never window titles or sites, since a notification can
/// show on a shared screen.
public struct DayRecap: Equatable, Sendable {
    public var title: String
    public var body: String

    /// Below this nothing is sent.
    public static let minimum: Int64 = 30 * 60
    /// Shorter days get "A short day." instead of a focus note.
    static let shortDay: Int64 = 3 * 3600

    /// nil when too little was tracked to be worth a notification.
    public init?(report r: DayReport) {
        guard r.tracked >= Self.minimum, !r.lanes.isEmpty else { return nil }
        let summary = DaySummary(report: r)
        title = "Your day: \(Durations.format(r.tracked))"
        let lanes = r.lanes.sorted { $0.total != $1.total ? $0.total > $1.total : $0.category.id < $1.category.id }
        // "Mostly" needs a clear lead: 40% of the day and half again the runner-up.
        let second = lanes.count > 1 ? lanes[1].total : 0
        let mix = Double(lanes[0].total) >= 0.4 * Double(r.tracked) && lanes[0].total * 2 >= second * 3
            ? "Mostly \(lanes[0].category.name)."
            : "A mix of \(lanes[0].category.name) and \(lanes[1].category.name)."
        let meetings = r.lanes.first { $0.category.id == ActivityCategory.meetings.id }?.total ?? 0

        // The most notable thing wins: a long day, then a meeting-heavy one,
        // then a day with no focus at all, then the ordinary line.
        switch summary.length {
        case .veryLong:
            body = "Over 10 hours. \(mix) Time to stop?"
        case .long:
            body = "Over 9 hours. \(mix)"
        case .normal where meetings >= 2 * 3600 && meetings * 2 >= r.tracked:
            body = "Half your day was meetings: \(Durations.format(meetings))."
        case .normal where r.tracked < Self.shortDay:
            body = "A short day. \(mix)"
        case .normal:
            if let f = r.longestFocus {
                body = "\(mix) Longest focus \(Durations.format(f.duration)) in \(f.appName)."
            } else {
                body = "\(mix) No focus block over \(DayReport.focusMinimum / 60) minutes."
            }
        }
    }
}

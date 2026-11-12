import Domain
import Foundation

/// Spec 2.2 state machine as the UI sees it.
public enum TrackingPhase: Equatable, Sendable {
    case needsPermission
    case waitingForPermission
    case tracking
    /// `until == nil`: until resumed by hand.
    case paused(since: Int64, until: Int64?)
    case permissionLost(at: Int64)

    public var canPause: Bool {
        switch self {
        case .tracking, .paused: true
        default: false
        }
    }
}

/// What the "Now" card shows when there is no current block.
public enum NowStatus: Equatable, Sendable {
    case none
    case away(since: Int64)
    /// A private window or excluded app is in front.
    case hidden
}

public enum PauseLength: CaseIterable, Sendable {
    case untilResumed, fifteenMinutes, oneHour, untilTomorrow

    public var title: String {
        switch self {
        case .untilResumed: "Until I resume"
        case .fifteenMinutes: "For 15 minutes"
        case .oneHour: "For 1 hour"
        case .untilTomorrow: "Until tomorrow"
        }
    }

    public func end(from date: Date, calendar: Calendar = .current) -> Int64? {
        let end: Date? = switch self {
        case .untilResumed: nil
        case .fifteenMinutes: date.addingTimeInterval(15 * 60)
        case .oneHour: date.addingTimeInterval(3600)
        case .untilTomorrow: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
        }
        return end.map { Int64($0.timeIntervalSince1970) }
    }
}

/// Everything the popover renders.
public struct PopoverModel: Equatable, Sendable {
    public var phase: TrackingPhase
    public var summary: DaySummary
    public var nowStatus: NowStatus
    public var now: Int64

    public init(phase: TrackingPhase, summary: DaySummary, nowStatus: NowStatus, now: Int64) {
        self.phase = phase
        self.summary = summary
        self.nowStatus = nowStatus
        self.now = now
    }
}

public struct PopoverActions {
    public var pause: (PauseLength) -> Void
    public var resume: () -> Void
    public var openTimeline: () -> Void
    public var openSettings: () -> Void
    public var openSystemSettings: () -> Void

    public init(pause: @escaping (PauseLength) -> Void, resume: @escaping () -> Void, openTimeline: @escaping () -> Void,
                openSettings: @escaping () -> Void, openSystemSettings: @escaping () -> Void) {
        self.pause = pause
        self.resume = resume
        self.openTimeline = openTimeline
        self.openSettings = openSettings
        self.openSystemSettings = openSystemSettings
    }
}

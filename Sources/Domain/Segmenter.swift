import Foundation

/// Inputs to the segmenter, all timestamped by the caller (unix seconds).
public enum CaptureEvent: Equatable, Sendable {
    /// Accessibility granted, or the user resumed.
    case startTracking
    /// Paused or Accessibility lost. The gap is recorded as `untracked`.
    case stopTracking
    /// The app is quitting. Close the open segment and record nothing after.
    case shutdown
    /// The frontmost app or tab changed. `nil` means a private window or an
    /// excluded app/site: nothing is recorded, not even away.
    case activity(Activity?)
    /// Seconds since the last keyboard/mouse input. Polled every few seconds.
    case idle(seconds: Double)
    /// Raw mic/camera state.
    case call(Bool)
    case suspend(SuspendReason)
    case resume(SuspendReason)
    /// Periodic heartbeat so the open segment's end keeps moving.
    case tick
}

public enum SuspendReason: Sendable {
    /// System sleep.
    case sleep
    /// Screen locked.
    case lock
    /// Another user's session is in front (fast user switching).
    case session
}

/// What the store should do. At most one segment is open at a time.
public enum SegmentChange: Equatable, Sendable {
    /// Open a new segment (its end starts at `start`).
    case begin(SegmentDraft)
    /// Close the open segment at this time.
    case end(at: Int64)
    /// Delete the open segment; it would have no length.
    case discard
    /// Move the open segment's end forward.
    case extend(to: Int64)
}

public struct SegmenterConfig: Sendable {
    /// No input for this long counts as away (spec: 2 minutes, configurable).
    public var idleThreshold: Int64
    /// Mic/camera off for less than this does not end a call. Meet drops both
    /// for ~11 s between its preview screen and the call itself.
    public var callGrace: Int64

    public init(idleThreshold: Int64 = 120, callGrace: Int64 = 45) {
        self.idleThreshold = idleThreshold
        self.callGrace = callGrace
    }
}

/// Turns capture events into contiguous segments. Pure: no clock, no I/O.
public struct Segmenter: Sendable {
    private enum Mode { case off, tracking, untracked }
    private enum Foreground { case unknown, hidden, visible(Activity) }

    public var config: SegmenterConfig
    public private(set) var current: SegmentDraft?

    private var mode = Mode.off
    private var foreground = Foreground.unknown
    private var suspended = Set<SuspendReason>()
    private var lastInput: Int64 = 0
    private var awaySince: Int64?
    private var rawCall = false
    private var callOffSince: Int64?
    private var callEndedAt: Int64?

    public init(config: SegmenterConfig = .init()) {
        self.config = config
    }

    public var isAway: Bool { awaySince != nil || !suspended.isEmpty }
    private var inCall: Bool { rawCall || callOffSince != nil }

    public mutating func handle(_ event: CaptureEvent, at t: Int64) -> [SegmentChange] {
        var changes = expireCallGrace(at: t)
        var cut = t

        switch event {
        case .startTracking:
            mode = .tracking
            lastInput = t
            awaySince = nil
        case .stopTracking:
            mode = .untracked
        case .shutdown:
            mode = .off
        case .activity(let a):
            foreground = a.map(Foreground.visible) ?? .hidden
        case .idle(let seconds):
            lastInput = max(lastInput, t - Int64(seconds.rounded(.down)))
            if let since = awaySince {
                if lastInput > since {
                    awaySince = nil
                    cut = lastInput
                }
            } else if mode == .tracking, suspended.isEmpty, !inCall, !isHidden {
                // Away starts at the last input, or when the call ended if
                // the user sat through a call without touching anything.
                let from = max(lastInput, callEndedAt ?? lastInput)
                if t - from >= config.idleThreshold {
                    awaySince = from
                    cut = from
                }
            }
        case .call(let on):
            if on {
                rawCall = true
                callOffSince = nil
                awaySince = nil
            } else if rawCall {
                rawCall = false
                callOffSince = t
            }
        case .suspend(let reason):
            suspended.insert(reason)
        case .resume(let reason):
            suspended.remove(reason)
            if suspended.isEmpty {
                lastInput = t
                awaySince = nil
            }
        case .tick:
            break
        }

        changes += reconcile(cut: cut)
        if case .tick = event, current != nil { changes.append(.extend(to: t)) }
        if case .idle = event, current != nil { changes.append(.extend(to: t)) }
        return changes
    }

    // MARK: - Private

    private var isHidden: Bool {
        if case .hidden = foreground { return true }
        return false
    }

    /// The call is over once the mic and camera have been off for the grace
    /// period; it ended when they went off, not when the grace ran out.
    private mutating func expireCallGrace(at t: Int64) -> [SegmentChange] {
        guard let off = callOffSince, t - off >= config.callGrace else { return [] }
        callOffSince = nil
        callEndedAt = off
        return reconcile(cut: off)
    }

    private func desired() -> (kind: SegmentKind, activity: Activity?, call: Bool)? {
        switch mode {
        case .off: return nil
        case .untracked: return (.untracked, nil, false)
        case .tracking: break
        }
        if !suspended.isEmpty { return (.away, nil, false) }
        if isHidden { return nil }
        if awaySince != nil { return (.away, nil, false) }
        if case .visible(let a) = foreground { return (.active, a, inCall) }
        return nil
    }

    private mutating func reconcile(cut: Int64) -> [SegmentChange] {
        let want = desired()
        if let cur = current, let want, cur.kind == want.kind, cur.call == want.call,
           cur.activity == nil && want.activity == nil
               || (cur.activity.flatMap { a in want.activity.map(a.isSameSegment) } ?? false) {
            return []
        }
        if current == nil && want == nil { return [] }

        var changes: [SegmentChange] = []
        var at = cut
        if let cur = current {
            // A cut can reach back in time (idle), but never before the open
            // segment began. If it lands on the start, the segment is empty.
            at = max(cut, cur.start)
            changes.append(at == cur.start ? .discard : .end(at: at))
        }
        current = want.map { SegmentDraft(start: at, kind: $0.kind, activity: $0.activity, call: $0.call) }
        if let draft = current { changes.append(.begin(draft)) }
        return changes
    }
}

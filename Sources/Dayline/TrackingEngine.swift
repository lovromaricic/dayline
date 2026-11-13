import AppKit
import Capture
import Categorize
import Domain
import Store
import UI

/// Owns capture, the segmenter and the store, and the tracking state machine
/// from spec 2.2 (permission states plus pause).
final class TrackingEngine {
    private(set) var phase: TrackingPhase = .needsPermission
    /// Called after anything the UI shows may have changed.
    var onChange: (() -> Void)?

    let database: DaylineDatabase
    let store: SegmentStore
    private(set) var categorizer = Categorizer()
    private var segmenter = Segmenter()
    private var exclusions: Exclusions
    private let permission = PermissionMonitor()
    private let watcher = FrontmostWatcher()
    private let power = PowerMonitor()
    private let calls = CallDetector()
    private var timer: Timer?
    private var lastPoll: Int64 = 0

    init(database: DaylineDatabase) {
        self.database = database
        store = SegmentStore(database: database)
        exclusions = (try? database.exclusions()) ?? Exclusions()
        categorizer.appCategoryType = AppCategoryLookup.categoryType(for:)
        reloadCategories()
        segmenter.config.idleThreshold = Int64(idleMinutes * 60)
        categorizer.callsAreMeetings = callsActive
        watcher.readChromeTitles = readChromeTitles
        watcher.skipPrivateWindows = skipPrivateWindows
    }

    // MARK: - Preferences (spec 5.4); each takes effect without a restart

    private func flag(_ key: String, default value: Bool) -> Bool {
        (try? database.setting(key)).flatMap { $0 }.map { $0 == "1" } ?? value
    }

    private func setFlag(_ key: String, _ value: Bool) {
        try? database.setSetting(key, value ? "1" : "0")
    }

    var showTotalInMenuBar: Bool {
        get { flag("menubar.showTotal", default: true) }
        set { setFlag("menubar.showTotal", newValue); onChange?() }
    }

    /// End-of-day recap (spec 5.5): the hour it is sent, nil when off (the default).
    var recapHour: Int? {
        get { (try? database.setting("recap.hour")).flatMap { $0 }.flatMap(Int.init) }
        set { try? database.setSetting("recap.hour", newValue.map(String.init) ?? "off") }
    }

    static let recapHours = [17, 18, 19, 20]

    /// The day the last recap went out, so it is sent once.
    var recapSentDay: Int64? {
        get { (try? database.setting("recap.lastDay")).flatMap { $0 }.flatMap(Int64.init) }
        set { try? database.setSetting("recap.lastDay", newValue.map(String.init)) }
    }

    /// "Count calls as active": a call keeps you from going away and counts as Meetings.
    var callsActive: Bool {
        get { flag("calls.active", default: true) }
        set {
            setFlag("calls.active", newValue)
            categorizer.callsAreMeetings = newValue
            send(.call(newValue && calls.state.inCall))
            onChange?()
        }
    }

    var readChromeTitles: Bool {
        get { flag("chrome.titles", default: true) }
        set { setFlag("chrome.titles", newValue); watcher.readChromeTitles = newValue; watcher.refresh() }
    }

    var skipPrivateWindows: Bool {
        get { flag("privacy.skipPrivate", default: true) }
        set { setFlag("privacy.skipPrivate", newValue); watcher.skipPrivateWindows = newValue; watcher.refresh() }
    }

    /// "Keep history for": nil is forever.
    var retentionDays: Int? {
        get { (try? database.setting("history.days")).flatMap { $0.flatMap(Int.init) } }
        set {
            try? database.setSetting("history.days", newValue.map(String.init))
            applyRetention()
            onChange?()
        }
    }

    func applyRetention() {
        guard let days = retentionDays else { return }
        let cutoff = Int64(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970) - Int64(days) * 86_400
        if let n = try? database.deleteSegments(endedBefore: cutoff), n > 0 { Log.line("retention removed \(n) segments") }
    }

    func reloadExclusions() {
        exclusions = (try? database.exclusions()) ?? Exclusions()
        watcher.refresh()
    }

    /// "Delete all data": close the open segment first so nothing writes to a
    /// deleted row, then start fresh in the current state.
    func deleteAllData() throws {
        send(.shutdown)
        try database.deleteAll()
        reloadCategories()
        reloadExclusions()
        switch phase {
        case .tracking: send(.startTracking)
        case .paused, .permissionLost: send(.stopTracking)
        default: break
        }
        watcher.refresh()
        Log.line("deleted all data")
        onChange?()
    }

    /// "Count me as away after" (spec 5.4): 1, 2, 3, 5 or 10 minutes; default 2.
    static let idleChoices = [1, 2, 3, 5, 10]

    var idleMinutes: Int {
        get { (try? database.setting("idle.minutes")).flatMap { $0.flatMap(Int.init) } ?? 2 }
        set {
            try? database.setSetting("idle.minutes", String(newValue))
            segmenter.config.idleThreshold = Int64(newValue * 60)
            onChange?()
        }
    }

    /// After rules or categories change; history re-categorizes on the next read.
    func reloadCategories() {
        if let list = try? database.categories() { categorizer.setCategories(list) }
        if let rules = try? database.rules() { categorizer.setRules(rules) }
        if let aliases = try? database.categoryAliases() { categorizer.aliases = aliases }
    }

    static func now() -> Int64 { Int64(Date().timeIntervalSince1970) }

    /// "Needs a category" (spec 5.4): apps and sites in Uncategorized over the last week.
    func unsorted(days: Int = 7) -> [Unsorted] {
        let cal = Calendar.current, now = Self.now()
        let today = cal.startOfDay(for: Date())
        let resolver = categorizer
        let reports = (0..<days).compactMap { back -> DayReport? in
            guard let start = cal.date(byAdding: .day, value: -back, to: today),
                  let end = cal.date(byAdding: .day, value: 1, to: start) else { return nil }
            let from = Int64(start.timeIntervalSince1970), to = Int64(end.timeIntervalSince1970)
            let segs = (try? store.segments(from: from, to: to)) ?? []
            return DayReport(segments: segs, dayStart: from, now: now, resolve: { resolver.resolve($0) })
        }
        return Unsorted.collect(reports)
    }

    /// What the "Now" card shows when there is no current block.
    var nowStatus: NowStatus {
        guard case .tracking = phase else { return .none }
        switch segmenter.current?.kind {
        case .away: return .away(since: segmenter.current!.start)
        case nil: return .hidden
        default: return .none
        }
    }

    func start() {
        watcher.onActivity = { [weak self] activity in
            guard let self else { return }
            send(.activity(activity.flatMap { self.exclusions.excludes($0) ? nil : $0 }))
        }
        power.onEvent = { [weak self] event in
            self?.send(event)
            if case .resume = event { self?.watcher.refresh() }
        }
        calls.onChange = { [weak self] state in
            Log.line("call \(state.inCall ? "on" : "off") users=\(state.micUsers)")
            guard let self else { return }
            send(.call(callsActive && state.inCall))
        }
        permission.onChange = { [weak self] _, new in self?.permissionChanged(new) }

        applyRetention()
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.everySecond() }
        RunLoop.main.add(timer!, forMode: .common)

        permission.start()
        calls.start()
        power.start()
        if permission.state == .tracking {
            beginTracking()
        } else {
            // Without access but with history, this is a returning user whose
            // access was turned off while Dayline was not running (screen 07),
            // not a first launch (screen 03).
            if let last = try? store.lastEnd() {
                phase = .permissionLost(at: last)
                Log.line("permission missing at launch; last data at \(last)")
                // The gap from here until access returns shows as not tracked.
                send(.stopTracking)
            } else {
                phase = .needsPermission
            }
            onChange?()
        }
    }

    func shutdown() {
        send(.shutdown)
    }

    // MARK: - Actions

    /// Spec: the app can only open System Settings and wait for the switch.
    func openSystemSettings() {
        permission.openSystemSettings(prompt: false)
        if case .needsPermission = phase { phase = .waitingForPermission }
        onChange?()
    }

    func pause(_ length: PauseLength) {
        switch phase {
        case .tracking, .paused: break
        default: return  // nothing to pause without permission
        }
        let now = Self.now()
        let since: Int64
        if case .paused(let s, _) = phase { since = s } else { since = now }
        let until = length.end(from: Date())
        phase = .paused(since: since, until: until)
        try? database.setSetting("pause.since", String(since))
        try? database.setSetting("pause.until", until.map(String.init) ?? "")
        send(.stopTracking)
        Log.line("paused until \(until.map(String.init) ?? "resumed")")
    }

    func resume() {
        guard case .paused = phase else { return }
        try? database.setSetting("pause.since", nil)
        try? database.setSetting("pause.until", nil)
        phase = .tracking
        send(.startTracking)
        watcher.refresh()
        Log.line("resumed")
    }

    func togglePause() {
        if case .paused = phase { resume() } else { pause(.untilResumed) }
    }

    // MARK: - Private

    private func send(_ event: CaptureEvent) {
        let changes = segmenter.handle(event, at: Self.now())
        do {
            try store.apply(changes)
        } catch {
            Log.line("store error: \(error)")
        }
        if changes.contains(where: { if case .extend = $0 { return false } else { return true } }) {
            onChange?()
        }
    }

    private func permissionChanged(_ new: PermissionState) {
        Log.line("permission \(new.rawValue)")
        switch new {
        case .tracking:
            beginTracking()
        case .permissionLost:
            watcher.stop()
            phase = .permissionLost(at: Self.now())
            send(.stopTracking)
        case .waitingForPermission:
            if case .needsPermission = phase { phase = .waitingForPermission }
        case .needsPermission:
            break
        }
        onChange?()
    }

    /// Permission is there: track, unless a pause from before is still running.
    private func beginTracking() {
        watcher.start()
        if let since = (try? database.setting("pause.since")).flatMap({ $0.flatMap { Int64($0) } }) {
            let until = (try? database.setting("pause.until")).flatMap { $0.flatMap { Int64($0) } }
            if until.map({ $0 > Self.now() }) ?? true {
                phase = .paused(since: since, until: until)
                send(.stopTracking)
                onChange?()
                return
            }
            try? database.setSetting("pause.since", nil)
            try? database.setSetting("pause.until", nil)
        }
        phase = .tracking
        send(.startTracking)
        onChange?()
    }

    /// Idle poll every 5 s (every second while away, so the return is timed
    /// closely) and the pause auto-resume check.
    private func everySecond() {
        let now = Self.now()
        if case .paused(_, let until?) = phase, until <= now { resume() }
        if now % 3600 == 0 { applyRetention() }
        guard segmenter.isAway || now - lastPoll >= 5 else { return }
        lastPoll = now
        send(.idle(seconds: IdleClock.secondsSinceInput()))
    }
}

enum Log {
    static let url = URL.libraryDirectory.appending(path: "Logs/Dayline/dayline.log")
    private static let handle: FileHandle? = {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        let h = try? FileHandle(forWritingTo: url)
        _ = try? h?.seekToEnd()
        return h
    }()

    /// App and site only; titles stay in the database.
    static func line(_ s: String) {
        let stamp = Date().formatted(Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute().second())
        handle?.write(Data("\(stamp)  \(s)\n".utf8))
    }
}

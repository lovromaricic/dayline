import AppKit
import Domain
import SwiftUI
import UI

/// The main window. Loads a day's segments into a DayReport and keeps today live.
/// Settings open in the same window, in place of the timeline.
final class TimelineWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    private let engine: TrackingEngine
    private let viewModel: HomeViewModel
    private var window: NSWindow?
    private var homeView: NSView?
    private var timer: Timer?
    private(set) var dayStart: Int64
    /// The window shows today and should move on to the next day at midnight.
    private var followsToday = true
    /// The calendar day the window was last opened on.
    private var openedOn: Int64?
    /// The day's segments as last loaded, for corrections.
    private var segments: [Segment] = []
    /// Rules changed: the popover and menu bar total need a refresh too.
    var onRulesChanged: (() -> Void)?
    /// The toolbar's Settings button.
    var onOpenSettings: (() -> Void)?
    /// The Sort note: Settings → Categories & rules.
    var onSortUnsorted: (() -> Void)?
    /// "See Krediti's rules": Settings → Projects with that project open.
    var onShowProject: ((Project) -> Void)?
    private static let settingsItem = NSToolbarItem.Identifier("settings")

    init(engine: TrackingEngine) {
        self.engine = engine
        dayStart = Self.startOfDay(Date())
        viewModel = HomeViewModel(report: DayReport(segments: [], dayStart: dayStart, now: TrackingEngine.now(),
                                                    category: { _ in .uncategorized }))
        super.init()
        viewModel.onMoveDay = { [weak self] days in self?.move(days: days) }
        viewModel.onSortUnsorted = { [weak self] in self?.onSortUnsorted?() }
        viewModel.onShowProject = { [weak self] p in self?.onShowProject?(p) }
        viewModel.onPickDay = { [weak self] date in self?.show(day: Self.startOfDay(date)) }
        viewModel.onSetPeriod = { [weak self] _ in self?.reload(); self?.viewModel.replay += 1 }
        viewModel.onSetCategory = { [weak self] block, category in self?.setCategory(block, category) }
        viewModel.onAlways = { [weak self] correction in self?.always(correction) }
        viewModel.onSplitCall = { [weak self] block in self?.splitCall(block) }
        viewModel.onDeleteBlock = { [weak self] block in self?.deleteBlock(block) }
        viewModel.onCountAsCall = { [weak self] block, category in self?.countAsCall(block, category) ?? [] }
        viewModel.onUnpinSegments = { [weak self] ids in self?.unpin(ids) }
        viewModel.onSetNote = { [weak self] block, note in self?.setNote(block, note) }
        viewModel.onSetProject = { [weak self] block, project in self?.setProject(block, project) }
        viewModel.onProjectAlways = { [weak self] c in self?.projectAlways(c) }
        viewModel.onSetScope = { [weak self] _ in self?.reload(); self?.viewModel.replay += 1 }
        viewModel.onSearchAllDays = { [weak self] query in self?.searchAllDays(query) }
        viewModel.onShowOlderMonth = { [weak self] in self?.showOlderMonth() }
        viewModel.onWholeCall = { [weak self] call in self?.wholeCall(call) }
        viewModel.onOpenSystemSettings = { engine.openSystemSettings() }
        viewModel.onResume = { engine.resume() }
        viewModel.idleChoices = TrackingEngine.idleChoices
        viewModel.idleMinutes = engine.idleMinutes
        viewModel.onSetIdleMinutes = { [weak self] m in
            engine.idleMinutes = m
            self?.viewModel.idleMinutes = m
        }
        viewModel.startAtLogin = LoginItem.isOn || !loginChosen
        viewModel.onSetStartAtLogin = { [weak self] on in self?.setStartAtLogin(on) }
        // No syncPhase() here: before engine.start() the phase is always
        // needsPermission, and adopting it made every launch look like a fresh
        // grant (the "access granted" banner). The engine's first change syncs it.
    }

    // MARK: - Tracking state (spec 2.2, screens 03–07)

    private var loginChosen: Bool { (try? engine.database.setting("login.chosen")) != nil }

    /// During onboarding the switch only records the wish; it is applied once
    /// Accessibility is granted. Afterwards it applies straight away.
    private func setStartAtLogin(_ on: Bool) {
        try? engine.database.setSetting("login.chosen", on ? "on" : "off")
        switch engine.phase {
        case .needsPermission, .waitingForPermission:
            viewModel.startAtLogin = on
        default:
            viewModel.startAtLoginError = LoginItem.set(on)
            viewModel.startAtLogin = LoginItem.isOn
        }
    }

    /// Called on every engine change, visible or not.
    func syncPhase() {
        let old = viewModel.phase
        let new = engine.phase
        guard old != new else { return }
        let wasOnboarding = old == .needsPermission || old == .waitingForPermission
        if wasOnboarding && new == .tracking {
            viewModel.showGrantedBanner = true
            // The onboarding switch defaults to on (screen 03).
            if (try? engine.database.setting("login.chosen")).flatMap({ $0 }) != "off", !LoginItem.isOn {
                viewModel.startAtLoginError = LoginItem.set(true)
            }
            viewModel.startAtLogin = LoginItem.isOn
        }
        viewModel.phase = new
        if isVisible { reload() }
    }

    /// "Just this time": pin the block's segments to the category. Picking
    /// what the rules would give anyway clears the pin instead.
    private func setCategory(_ block: Block, _ category: ActivityCategory) {
        let ids = Set(block.segmentIDs)
        let members = segments.filter { ids.contains($0.id) }
        // A whole call is Meetings until you say otherwise, so any other pick pins it.
        let unpinned = block.call == nil && members.allSatisfy { engine.categorizer.resolve($0, ignoringManual: true).category == category }
        do {
            try engine.store.setManualCategory(segmentIDs: block.segmentIDs, categoryID: unpinned ? nil : category.id)
        } catch {
            Log.line("correction failed: \(error)")
        }
        reload()
        onRulesChanged?()
    }

    /// Picked by hand; when the rules would pick the same anyway, nothing is pinned.
    private func setProject(_ block: Block, _ project: Project?) {
        let ids = Set(block.segmentIDs)
        let resolver = engine.projects
        let automatic = segments.filter { ids.contains($0.id) }
            .allSatisfy { resolver.resolve($0, ignoringManual: true)?.project == project }
        do {
            try engine.store.setManualProject(segmentIDs: block.segmentIDs,
                                              projectID: automatic ? nil : project?.id ?? ProjectResolver.none)
        } catch {
            Log.line("project failed: \(error)")
        }
        reload()
    }

    private func projectAlways(_ c: ProjectCorrection) {
        do {
            try engine.database.addProjectRule(projectID: c.project.id, kind: c.kind, pattern: c.pattern, at: TrackingEngine.now())
            if let block = viewModel.report.blocks.first(where: { $0.id == c.blockID }) {
                try engine.store.setManualProject(segmentIDs: block.segmentIDs, projectID: nil)
            }
        } catch {
            Log.line("project rule failed: \(error)")
        }
        engine.reloadCategories()
        reload()
    }

    private func setNote(_ block: Block, _ note: String) {
        do {
            try engine.store.setNote(segmentIDs: block.segmentIDs, note: note)
        } catch {
            Log.line("note failed: \(error)")
        }
        reload()
    }

    private func deleteBlock(_ block: Block) {
        do {
            try engine.store.deleteSegments(ids: block.segmentIDs)
        } catch {
            Log.line("delete block failed: \(error)")
        }
        reload()
        onRulesChanged?()
    }

    /// "Not work during the call": the category's segments in the call are
    /// pinned to Meetings, so they stay the call's time (no gap, no split).
    private func countAsCall(_ block: Block, _ category: ActivityCategory) -> [Int64] {
        let ids = Set(block.segmentIDs)
        let picked = Segment.narrowingCalls(segments).filter { s in
            guard ids.contains(s.id) else { return false }
            var plain = s
            plain.wholeCall = false
            return engine.categorizer.resolve(plain).category == category
        }.map(\.id)
        guard !picked.isEmpty else { return [] }
        do {
            try engine.store.setManualCategory(segmentIDs: picked, categoryID: block.category.id)
        } catch {
            Log.line("count as call failed: \(error)")
            return []
        }
        reload()
        onRulesChanged?()
        return picked
    }

    private func unpin(_ ids: [Int64]) {
        do {
            try engine.store.setManualCategory(segmentIDs: ids, categoryID: nil)
        } catch {
            Log.line("unpin failed: \(error)")
        }
        reload()
        onRulesChanged?()
    }

    /// "What I was doing": pin each of the call's segments to what it is
    /// outside the call, so the call shows as the apps you were in.
    private func splitCall(_ block: Block) {
        let ids = Set(block.segmentIDs)
        var groups: [Int64: [Int64]] = [:]
        for s in Segment.narrowingCalls(segments) where ids.contains(s.id) {
            groups[engine.categorizer.resolve(s, ignoringManual: true).category.id, default: []].append(s.id)
        }
        do {
            for (category, ids) in groups { try engine.store.setManualCategory(segmentIDs: ids, categoryID: category) }
        } catch {
            Log.line("split call failed: \(error)")
        }
        reload()
        onRulesChanged?()
    }

    /// Back to one Meetings block: the call's pins are dropped.
    private func wholeCall(_ call: DayReport.Call) {
        do {
            try engine.store.setManualCategory(segmentIDs: call.segmentIDs, categoryID: nil)
        } catch {
            Log.line("whole call failed: \(error)")
        }
        reload()
        onRulesChanged?()
    }

    /// "Always": a correction rule; the block's pin is dropped so the rule governs it.
    private func always(_ c: Correction) {
        do {
            try engine.database.addRule(kind: c.kind, pattern: c.pattern, categoryID: c.category.id, origin: .correction,
                                        at: TrackingEngine.now())
            if let block = viewModel.report.blocks.first(where: { $0.id == c.blockID }) {
                try engine.store.setManualCategory(segmentIDs: block.segmentIDs, categoryID: nil)
            }
        } catch {
            Log.line("rule failed: \(error)")
        }
        engine.reloadCategories()
        reload()
        onRulesChanged?()
    }

    /// The timeline is on screen (not hidden behind the settings page).
    var isVisible: Bool { (window?.isVisible ?? false) && window?.contentView === homeView }

    func show() {
        if window == nil { window = makeWindow() }
        // Reopening jumps back to today, and so does opening it on a new day
        // (the window usually stays open behind other apps, holding the day
        // you last looked at), and a window showing today when midnight passed.
        let today = Self.startOfDay(Date())
        if !(window?.isVisible ?? false) || openedOn != today { followsToday = true }
        openedOn = today
        if followsToday { dayStart = today }
        unsortedAt = 0
        viewModel.replay += 1
        if window?.contentView !== homeView { window?.contentView = homeView }
        showSettingsButton(true)
        reload()
        bringToFront()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.tick() }
    }

    /// Swaps the settings page in; Back to Dayline calls `show()`.
    func show(settings view: NSView) {
        if window == nil { window = makeWindow() }
        if window?.contentView !== view { window?.contentView = view }
        // A Settings button inside Settings goes nowhere.
        showSettingsButton(false)
        timer?.invalidate()
        timer = nil
        bringToFront()
    }

    /// Always ends with the window in front. Since macOS 14 a plain activate()
    /// is a request the system may decline (the popover never activates
    /// Dayline), which left Open timeline doing nothing now and then; a
    /// minimized window also has to be brought back first.
    private func bringToFront() {
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Segment, rule or category changes while the window is open.
    func refresh() {
        syncPhase()
        guard isVisible else { return }
        reload()
    }

    private func tick() {
        let today = Self.startOfDay(Date())
        // Past days do not change; only today needs the 5 s refresh. After
        // midnight a window that was showing today moves on to the new day.
        if followsToday && dayStart != today { dayStart = today }
        if dayStart == today || viewModel.period != .day && viewModel.week?.containsToday == true { reload(ticking: true) }
    }

    /// Opens the window on a given day (the recap notification).
    func open(day: Int64) {
        show()
        show(day: day)
    }

    private func show(day: Int64) {
        let today = Self.startOfDay(Date())
        let before = spanStart(dayStart)
        dayStart = min(day, today)
        followsToday = dayStart == today
        reload()
        // A new day, or a new week or month in those views: the charts grow in again.
        if spanStart(dayStart) != before { viewModel.replay += 1 }
    }

    private func move(days: Int) {
        let cal = Calendar.current
        let from = Date(timeIntervalSince1970: TimeInterval(dayStart))
        // The arrows step a whole week or month in those views.
        let d = switch viewModel.period {
        case .day: cal.date(byAdding: .day, value: days, to: from)!
        case .week: cal.date(byAdding: .day, value: days * 7, to: from)!
        // From the 1st, so 31 March back a month is 1 February, not 3 March.
        case .month: cal.date(byAdding: .month, value: days, to: cal.dateInterval(of: .month, for: from)!.start)!
        }
        show(day: Self.startOfDay(d))
    }

    /// `ticking`: the 5 s refresh, where past days in a week or month are
    /// reused; any other reload (a correction, a rule) builds them again.
    private func reload(ticking: Bool = false) {
        if !ticking { pastDays = [:] }
        let next = Int64(Calendar.current.date(byAdding: .day, value: 1,
                                               to: Date(timeIntervalSince1970: TimeInterval(dayStart)))!.timeIntervalSince1970)
        segments = (try? engine.store.segments(from: dayStart, to: next)) ?? []
        let categorizer = engine.categorizer
        if viewModel.categories != categorizer.categoryList { viewModel.categories = categorizer.categoryList }
        if viewModel.projects != engine.projects.active { viewModel.projects = engine.projects.active }
        if viewModel.projects.isEmpty {
            if viewModel.scope != nil { viewModel.setScope(nil); return }
            if viewModel.mode == .byProject { viewModel.mode = .byCategory }
        }
        let shown = scoped(segments)
        let report = DayReport(segments: shown, dayStart: dayStart, now: TrackingEngine.now(),
                               resolve: { categorizer.resolve($0) }).withProjects(engine.projects, segments: shown)
        // Filtered: the whole day's time too, for "79% of 6h 25m".
        let unscoped = viewModel.scope == nil ? 0
            : DayReport(segments: segments, dayStart: dayStart, now: TrackingEngine.now(), resolve: { categorizer.resolve($0) }).tracked
        if viewModel.unscopedTracked != unscoped { viewModel.unscopedTracked = unscoped }
        viewModel.update(engine.hidesTitlesNow ? report.hidingTitles() : report)
        let week = viewModel.period == .day ? nil : loadSpan()
        if viewModel.week != week { viewModel.week = week }
        // A week of reports: at most once a minute, or right away after show().
        let now = TrackingEngine.now()
        if now - unsortedAt >= 60 {
            unsortedAt = now
            let u = engine.unsorted()
            let total = u.reduce(0) { $0 + $1.total }
            if viewModel.unsortedCount != u.count { viewModel.unsortedCount = u.count }
            if viewModel.unsortedTotal != total { viewModel.unsortedTotal = total }
        }
    }

    private var unsortedAt: Int64 = 0
    private var pendingSearch: DispatchWorkItem?
    /// All days search: the query, the days with a matching segment (newest
    /// first), and the oldest month shown so far.
    private var searchQuery = ""
    private var matchDays: [Int64] = []
    private var shownFrom: Int64 = 0

    /// All days search starts with the newest month that has a match (this
    /// month, if any). Waits for a pause in typing.
    private func searchAllDays(_ query: String) {
        pendingSearch?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.viewModel.isSearchingAllDays else { return }
            let starts = (try? self.engine.store.starts(matching: query)) ?? []
            var days: [Int64] = []
            for s in starts {
                let d = Self.startOfDay(Date(timeIntervalSince1970: TimeInterval(s)))
                if days.last != d { days.append(d) }
            }
            self.searchQuery = query
            self.matchDays = days
            self.shownFrom = days.first.map(Self.startOfMonth) ?? 0
            self.showSearchResults(untilAMatch: true)
        }
        pendingSearch = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// "Show October": back to the next older month with a match.
    private func showOlderMonth() {
        guard let older = matchDays.first(where: { $0 < shownFrom }) else { return }
        let before = viewModel.allDaysVisible.count
        shownFrom = Self.startOfMonth(older)
        showSearchResults(untilAMatch: true, beyond: before)
    }

    /// The matching days from `shownFrom` on, each built as in the day view so
    /// blocks merge the same way, keeping the blocks that match. `untilAMatch`:
    /// a month with nothing in the chosen category is skipped, so the list
    /// (or "Show October") always adds something.
    private func showSearchResults(untilAMatch: Bool = false, beyond shown: Int = 0) {
        let cal = Calendar.current
        let today = Self.startOfDay(Date()), now = TrackingEngine.now()
        let categorizer = engine.categorizer
        let results = matchDays.filter { $0 >= shownFrom }.compactMap { day -> SearchDay? in
            let next = Self.startOfDay(cal.date(byAdding: .day, value: 1, to: Date(timeIntervalSince1970: TimeInterval(day)))!)
            let segs = (try? engine.store.segments(from: day, to: next)) ?? []
            var report = DayReport(segments: segs, dayStart: day, now: now, resolve: { categorizer.resolve($0) })
                .withProjects(engine.projects, segments: segs)
            if engine.hidesTitlesNow { report = report.hidingTitles() }
            let blocks = report.blocks.reversed().filter { HomeViewModel.matches($0, searchQuery) }
            return blocks.isEmpty ? nil : SearchDay(dayStart: day, isToday: day == today, blocks: blocks)
        }
        let older = matchDays.first { $0 < shownFrom }.map(Self.startOfMonth)
        if viewModel.allDaysResults != results { viewModel.allDaysResults = results }
        if viewModel.allDaysOlder != older { viewModel.allDaysOlder = older }
        if untilAMatch, viewModel.allDaysVisible.count <= shown, let next = matchDays.first(where: { $0 < shownFrom }) {
            shownFrom = Self.startOfMonth(next)
            showSearchResults(untilAMatch: true, beyond: shown)
        }
    }

    private static func startOfMonth(_ day: Int64) -> Int64 {
        let d = Date(timeIntervalSince1970: TimeInterval(day))
        return Int64((Calendar.current.dateInterval(of: .month, for: d)?.start ?? d).timeIntervalSince1970)
    }
    /// Past days of the week or month on screen; they don't change between ticks.
    private var pastDays: [Int64: DayReport] = [:]

    /// The calendar week or month around `day` in those views; the day itself in the day view.
    private func spanStart(_ day: Int64) -> Int64 {
        let anchor = Date(timeIntervalSince1970: TimeInterval(day))
        let unit: Calendar.Component
        switch viewModel.period {
        case .day: return day
        case .week: unit = .weekOfYear
        case .month: unit = .month
        }
        return Int64((Calendar.current.dateInterval(of: unit, for: anchor)?.start ?? anchor).timeIntervalSince1970)
    }

    /// The calendar week or month around `dayStart`, one DayReport per day up to today.
    private func loadSpan() -> WeekReport {
        let cal = Calendar.current
        let month = viewModel.period == .month
        let anchor = Date(timeIntervalSince1970: TimeInterval(dayStart))
        let start = cal.dateInterval(of: month ? .month : .weekOfYear, for: anchor)?.start ?? anchor
        let count = month ? cal.range(of: .day, in: .month, for: anchor)?.count ?? 30 : 7
        let starts = (0..<count).map { Self.startOfDay(cal.date(byAdding: .day, value: $0, to: start)!) }
        let today = Self.startOfDay(Date()), now = TrackingEngine.now()
        let categorizer = engine.categorizer
        let reports = starts.filter { $0 <= today }.map { day in
            if day < today, let kept = pastDays[day] { return kept }
            let next = Self.startOfDay(cal.date(byAdding: .day, value: 1, to: Date(timeIntervalSince1970: TimeInterval(day)))!)
            let segs = scoped((try? engine.store.segments(from: day, to: next)) ?? [])
            let report = DayReport(segments: segs, dayStart: day, now: now, resolve: { categorizer.resolve($0) })
                .withProjects(engine.projects, segments: segs)
            let shown = engine.hidesTitlesNow ? report.hidingTitles() : report
            if day < today { pastDays[day] = shown }
            return shown
        }
        return WeekReport(weekStart: starts[0], reports: reports, dayStarts: starts, today: today, isMonth: month)
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 716),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "Dayline"
        // A compact toolbar gives a 38 pt title bar with the window buttons
        // centered in it, so they line up with our header. Its one item is
        // Settings: a real toolbar item, because the title bar swallows
        // clicks meant for SwiftUI buttons drawn under it.
        let toolbar = NSToolbar(identifier: "DaylineMain")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        w.toolbar = toolbar
        w.toolbarStyle = .unifiedCompact
        w.titlebarSeparatorStyle = .none
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = NSColor(srgbRed: 0x10 / 255, green: 0x11 / 255, blue: 0x13 / 255, alpha: 1)
        w.isReleasedWhenClosed = false
        w.contentMinSize = NSSize(width: 1000, height: 640)
        let home = NSHostingView(rootView: HomeView(viewModel: viewModel))
        // Swapping pages must not resize the window.
        home.sizingOptions = []
        homeView = home
        w.contentView = home
        w.setFrameAutosaveName("DaylineMain")
        if !w.setFrameUsingName("DaylineMain") { w.center() }
        w.delegate = self
        return w
    }

    /// Removing the item (not the toolbar) keeps the title bar's height.
    private func showSettingsButton(_ visible: Bool) {
        guard let toolbar = window?.toolbar else { return }
        let index = toolbar.items.firstIndex { $0.itemIdentifier == Self.settingsItem }
        if visible, index == nil {
            toolbar.insertItem(withItemIdentifier: Self.settingsItem, at: toolbar.items.count)
        } else if !visible, let index {
            toolbar.removeItem(at: index)
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.settingsItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard id == Self.settingsItem else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = "Settings"
        item.toolTip = "Settings (⌘,)"
        item.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Settings")
        item.isBordered = true
        item.target = self
        item.action = #selector(settingsClicked)
        return item
    }

    @objc private func settingsClicked() { onOpenSettings?() }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        // Tomorrow it opens on all work, not on a filter you forgot about.
        viewModel.setScope(nil)
    }

    /// With the header filter on, only that client's or project's active time
    /// is kept; away and untracked stretches stay, so the day's shape does too.
    private func scoped(_ segs: [Segment]) -> [Segment] {
        guard let scope = viewModel.scope else { return segs }
        let resolver = engine.projects
        return segs.filter { $0.kind != .active || scope.contains(resolver.resolve($0)?.project) }
    }

    static func startOfDay(_ d: Date) -> Int64 { Int64(Calendar.current.startOfDay(for: d).timeIntervalSince1970) }
}

enum MainMenu {
    /// Accessory apps have no visible menu bar, but key equivalents still need
    /// a main menu: ⌘, ⌘W ⌘Q, and Edit commands for the search field.
    static func install(settings: Selector, target: AnyObject) {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let app = NSMenu()
        let s = NSMenuItem(title: "Settings…", action: settings, keyEquivalent: ",")
        s.target = target
        app.addItem(s)
        app.addItem(.separator())
        app.addItem(NSMenuItem(title: "Quit Dayline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = app
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let file = NSMenu(title: "File")
        file.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileItem.submenu = file
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        edit.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}

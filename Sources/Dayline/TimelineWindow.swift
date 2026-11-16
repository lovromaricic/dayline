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
    private static let settingsItem = NSToolbarItem.Identifier("settings")

    init(engine: TrackingEngine) {
        self.engine = engine
        dayStart = Self.startOfDay(Date())
        viewModel = HomeViewModel(report: DayReport(segments: [], dayStart: dayStart, now: TrackingEngine.now(),
                                                    category: { _ in .uncategorized }))
        super.init()
        viewModel.onMoveDay = { [weak self] days in self?.move(days: days) }
        viewModel.onSortUnsorted = { [weak self] in self?.onSortUnsorted?() }
        viewModel.onPickDay = { [weak self] date in self?.show(day: Self.startOfDay(date)) }
        viewModel.onSetPeriod = { [weak self] _ in self?.reload(); self?.viewModel.replay += 1 }
        viewModel.onSetCategory = { [weak self] block, category in self?.setCategory(block, category) }
        viewModel.onAlways = { [weak self] correction in self?.always(correction) }
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
        let unpinned = members.allSatisfy { engine.categorizer.resolve($0, ignoringManual: true).category == category }
        do {
            try engine.store.setManualCategory(segmentIDs: block.segmentIDs, categoryID: unpinned ? nil : category.id)
        } catch {
            Log.line("correction failed: \(error)")
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
        if dayStart == today || viewModel.period == .week && viewModel.week?.containsToday == true { reload() }
    }

    /// Opens the window on a given day (the recap notification).
    func open(day: Int64) {
        show()
        show(day: day)
    }

    private func show(day: Int64) {
        let today = Self.startOfDay(Date())
        let before = viewModel.period == .week ? weekStart(dayStart) : dayStart
        dayStart = min(day, today)
        followsToday = dayStart == today
        reload()
        // A new day, or a new week in the week view: the charts grow in again.
        if (viewModel.period == .week ? weekStart(dayStart) : dayStart) != before { viewModel.replay += 1 }
    }

    private func move(days: Int) {
        let cal = Calendar.current
        // The arrows step a whole week in the week view.
        let step = viewModel.period == .week ? days * 7 : days
        let d = cal.date(byAdding: .day, value: step, to: Date(timeIntervalSince1970: TimeInterval(dayStart)))!
        show(day: Self.startOfDay(d))
    }

    private func reload() {
        let next = Int64(Calendar.current.date(byAdding: .day, value: 1,
                                               to: Date(timeIntervalSince1970: TimeInterval(dayStart)))!.timeIntervalSince1970)
        segments = (try? engine.store.segments(from: dayStart, to: next)) ?? []
        let categorizer = engine.categorizer
        if viewModel.categories != categorizer.categoryList { viewModel.categories = categorizer.categoryList }
        viewModel.update(DayReport(segments: segments, dayStart: dayStart, now: TrackingEngine.now(),
                                   resolve: { categorizer.resolve($0) }))
        let week = viewModel.period == .week ? loadWeek() : nil
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

    private func weekStart(_ day: Int64) -> Int64 {
        let anchor = Date(timeIntervalSince1970: TimeInterval(day))
        return Int64((Calendar.current.dateInterval(of: .weekOfYear, for: anchor)?.start ?? anchor).timeIntervalSince1970)
    }

    /// The calendar week around `dayStart`, one DayReport per day up to today.
    private func loadWeek() -> WeekReport {
        let cal = Calendar.current
        let anchor = Date(timeIntervalSince1970: TimeInterval(dayStart))
        let start = cal.dateInterval(of: .weekOfYear, for: anchor)?.start ?? anchor
        let starts = (0..<7).map { Self.startOfDay(cal.date(byAdding: .day, value: $0, to: start)!) }
        let today = Self.startOfDay(Date()), now = TrackingEngine.now()
        let categorizer = engine.categorizer
        let reports = starts.filter { $0 <= today }.map { day in
            let next = Self.startOfDay(cal.date(byAdding: .day, value: 1, to: Date(timeIntervalSince1970: TimeInterval(day)))!)
            let segs = (try? engine.store.segments(from: day, to: next)) ?? []
            return DayReport(segments: segs, dayStart: day, now: now, resolve: { categorizer.resolve($0) })
        }
        return WeekReport(weekStart: starts[0], reports: reports, dayStarts: starts, today: today)
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

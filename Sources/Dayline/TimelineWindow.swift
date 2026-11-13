import AppKit
import Domain
import SwiftUI
import UI

/// The main window. Loads a day's segments into a DayReport and keeps today live.
/// Settings open in the same window, in place of the timeline.
final class TimelineWindowController: NSObject, NSWindowDelegate {
    private let engine: TrackingEngine
    private let viewModel: HomeViewModel
    private var window: NSWindow?
    private var homeView: NSView?
    private var timer: Timer?
    private(set) var dayStart: Int64
    /// The window shows today and should move on to the next day at midnight.
    private var followsToday = true
    /// The day's segments as last loaded, for corrections.
    private var segments: [Segment] = []
    /// Rules changed: the popover and menu bar total need a refresh too.
    var onRulesChanged: (() -> Void)?

    init(engine: TrackingEngine) {
        self.engine = engine
        dayStart = Self.startOfDay(Date())
        viewModel = HomeViewModel(report: DayReport(segments: [], dayStart: dayStart, now: TrackingEngine.now(),
                                                    category: { _ in .uncategorized }))
        super.init()
        viewModel.onMoveDay = { [weak self] days in self?.move(days: days) }
        viewModel.onPickDay = { [weak self] date in self?.show(day: Self.startOfDay(date)) }
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
        // Reopening jumps back to today, and so does a window that was
        // showing today when midnight passed.
        if !(window?.isVisible ?? false) { followsToday = true }
        if followsToday { dayStart = Self.startOfDay(Date()) }
        if window?.contentView !== homeView { window?.contentView = homeView }
        reload()
        bringToFront()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.tick() }
    }

    /// Swaps the settings page in; Back to Dayline calls `show()`.
    func show(settings view: NSView) {
        if window == nil { window = makeWindow() }
        if window?.contentView !== view { window?.contentView = view }
        timer?.invalidate()
        timer = nil
        bringToFront()
    }

    private func bringToFront() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
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
        if dayStart == today { reload() }
    }

    private func show(day: Int64) {
        let today = Self.startOfDay(Date())
        dayStart = min(day, today)
        followsToday = dayStart == today
        reload()
    }

    private func move(days: Int) {
        let cal = Calendar.current
        let d = cal.date(byAdding: .day, value: days, to: Date(timeIntervalSince1970: TimeInterval(dayStart)))!
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
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 716),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "Dayline"
        // An empty compact toolbar gives a 38 pt title bar with the window
        // buttons centered in it, so they line up with our header.
        w.toolbar = NSToolbar(identifier: "DaylineMain")
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

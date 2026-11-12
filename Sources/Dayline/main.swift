import AppKit
import Domain
import Store
import SwiftUI
import UI

// Dayline: menu bar app. Capture runs in-process (the M1 agent is folded in here).

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var engine: TrackingEngine!
    private var statusItem: StatusItemController!
    private let popoverModel = PopoverViewModel(model: PopoverModel(
        phase: .needsPermission,
        summary: DaySummary(segments: [], dayStart: 0, now: 0, category: { _ in .uncategorized }),
        nowStatus: .none, now: 0))
    private var refreshTimer: Timer?
    private var timeline: TimelineWindowController!
    private var settings: SettingsController!

    func applicationDidFinishLaunching(_ note: Notification) {
        let database: DaylineDatabase
        do {
            database = try DaylineDatabase()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Dayline can't open its database"
            alert.informativeText = "\(DaylineDatabase.defaultURL.path)\n\n\(error.localizedDescription)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        engine = TrackingEngine(database: database)
        let actions = PopoverActions(
            pause: { [weak self] in self?.engine.pause($0) },
            resume: { [weak self] in self?.engine.resume() },
            openTimeline: { [weak self] in self?.showTimeline() },
            openSettings: { [weak self] in self?.openSettings() },
            openSystemSettings: { [weak self] in self?.engine.openSystemSettings() })
        statusItem = StatusItemController(engine: engine, popover: PopoverView(viewModel: popoverModel, actions: actions))
        statusItem.onPopoverShow = { [weak self] in self?.refresh() }
        statusItem.onOpenTimeline = { [weak self] in self?.showTimeline() }
        timeline = TimelineWindowController(engine: engine)
        timeline.onOpenSettings = { [weak self] in self?.openSettings() }
        timeline.onRulesChanged = { [weak self] in self?.refresh() }
        settings = SettingsController(engine: engine)
        settings.onChange = { [weak self] in
            self?.refresh()
            self?.timeline.refresh()
        }
        settings.onBack = { [weak self] in self?.timeline.show() }
        engine.onChange = { [weak self] in
            self?.refresh()
            self?.timeline.refresh()
            self?.settings?.refresh()
        }
        MainMenu.install(settings: #selector(openSettings), target: self)
        engine.start()
        // First launch (or permission never granted): show the setup screen.
        if engine.phase == .needsPermission { timeline.show() }

        // The total moves with time even without segment changes: every 5 s
        // while the popover is open, every 30 s otherwise.
        refreshTimer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if statusItem.isPopoverShown || Int(Date().timeIntervalSince1970) % 30 < 5 { refresh() }
        }
        RunLoop.main.add(refreshTimer!, forMode: .common)
        Log.line("launched pid \(getpid()) from \(Bundle.main.bundlePath)")
        // Start at login points at a bundle location; after scripts/install.sh
        // moves the app, register again so it points here.
        if (try? database.setting("login.chosen")).flatMap({ $0 }) == "on" { LoginItem.set(true) }
    }

    func applicationWillTerminate(_ note: Notification) {
        engine?.shutdown()
        Log.line("quit")
    }

    private func refresh() {
        let now = TrackingEngine.now()
        let dayStart = Int64(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        let segments = (try? engine.store.segments(from: dayStart, to: dayStart + 86_400)) ?? []
        let categorizer = engine.categorizer
        let summary = DaySummary(segments: segments, dayStart: dayStart, now: now, resolve: { categorizer.resolve($0) })
        let model = PopoverModel(phase: engine.phase, summary: summary, nowStatus: engine.nowStatus, now: now)
        if model != popoverModel.model { popoverModel.model = model }
        statusItem.update(phase: engine.phase, tracked: summary.tracked, showTotal: engine.showTotalInMenuBar)
        DispatchQueue.main.async { self.statusItem.refitPopover() }
    }

    private func showTimeline() {
        statusItem.closePopover()
        timeline.show()
    }

    @objc private func openSettings() {
        statusItem.closePopover()
        settings.prepare()
        timeline.show(settings: settings.view)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)

// SIGTERM (pkill, logout scripts) should close the open segment cleanly too.
signal(SIGTERM, SIG_IGN)
let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigterm.setEventHandler { NSApp.terminate(nil) }
sigterm.resume()

app.run()

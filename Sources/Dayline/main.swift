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
    private var recap: Recap!

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
        // Opening shows the current state as is; only changes while it is open animate.
        statusItem.onPopoverShow = { [weak self] in
            self?.refresh(animated: false)
            self?.popoverModel.opened += 1
        }
        statusItem.onOpenTimeline = { [weak self] in self?.showTimeline() }
        statusItem.onOpenSettings = { [weak self] in self?.openSettings() }
        timeline = TimelineWindowController(engine: engine)
        timeline.onRulesChanged = { [weak self] in self?.refresh() }
        timeline.onOpenSettings = { [weak self] in self?.openSettings() }
        timeline.onSortUnsorted = { [weak self] in self?.openSettings(section: .categories) }
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
        recap = Recap(engine: engine)
        recap.onOpenDay = { [weak self] day in
            self?.statusItem.closePopover()
            self?.timeline.open(day: day)
        }
        MainMenu.install(settings: #selector(openSettingsAction), target: self)
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

    private func refresh(animated: Bool = true) {
        let now = TrackingEngine.now()
        let dayStart = Int64(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        let segments = (try? engine.store.segments(from: dayStart, to: dayStart + 86_400)) ?? []
        let categorizer = engine.categorizer
        let report = DayReport(segments: segments, dayStart: dayStart, now: now, resolve: { categorizer.resolve($0) })
        let summary = DaySummary(report: engine.hidesTitlesNow ? report.hidingTitles() : report)
        recap.check(report: report, now: now)
        let model = PopoverModel(phase: engine.phase, summary: summary, nowStatus: engine.nowStatus, now: now)
        if model != popoverModel.model {
            if animated, statusItem.isPopoverShown, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                withAnimation(.smooth(duration: 0.35)) { popoverModel.model = model }
            } else {
                popoverModel.model = model
            }
        }
        statusItem.update(phase: engine.phase, tracked: summary.tracked, length: summary.length, showTotal: engine.showTotalInMenuBar)
        DispatchQueue.main.async { self.statusItem.refitPopover() }
    }

    private func showTimeline() {
        statusItem.closePopover()
        timeline.show()
    }

    @objc private func openSettingsAction() { openSettings() }

    private func openSettings(section: SettingsSection = .general) {
        statusItem.closePopover()
        settings.prepare(section: section)
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

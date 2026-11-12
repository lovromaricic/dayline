import AppKit
import Categorize
import Domain
import Store
import SwiftUI
import UI

/// The Settings window (spec 5.4). ⌘, opens it from anywhere.
final class SettingsWindowController {
    private let engine: TrackingEngine
    private let viewModel = SettingsViewModel()
    private var window: NSWindow?
    /// Rules or categories changed: refresh the timeline, popover and menu bar.
    var onChange: (() -> Void)?
    var onBack: (() -> Void)?

    init(engine: TrackingEngine) {
        self.engine = engine
        let db = engine.database
        viewModel.onBack = { [weak self] in
            self?.window?.close()
            self?.onBack?()
        }
        viewModel.onAddRule = { [weak self] kind, pattern, categoryID in
            self?.write { try db.addRule(kind: kind, pattern: pattern, categoryID: categoryID, origin: .user, at: TrackingEngine.now()) }
        }
        viewModel.onSetRuleCategory = { [weak self] id, categoryID in self?.write { try db.setRuleCategory(id: id, categoryID: categoryID) } }
        viewModel.onDeleteRule = { [weak self] id in self?.write { try db.deleteRule(id: id) } }
        viewModel.onAddCategory = { [weak self] name, color in self?.write { try db.addCategory(name: name, color: color) } }
        viewModel.onUpdateCategory = { [weak self] c in self?.write { try db.updateCategory(c) } }
        viewModel.onMergeCategory = { [weak self] from, to in
            guard let self, confirm("Merge \(from.name) into \(to.name)?",
                                    "Its time, rules and corrections move to \(to.name), and \(from.name) is removed.",
                                    button: "Merge") else { return }
            write { try db.mergeCategory(from.id, into: to.id) }
        }
        viewModel.onDeleteCategory = { [weak self] c in
            guard let self, confirm("Delete \(c.name)?",
                                    "Its time moves to Uncategorized, and rules that used it point there too.",
                                    button: "Delete", destructive: true) else { return }
            write { try db.mergeCategory(c.id, into: ActivityCategory.uncategorized.id) }
        }

        // General
        viewModel.idleChoices = TrackingEngine.idleChoices
        viewModel.onSetStartAtLogin = { [weak self] on in
            try? db.setSetting("login.chosen", on ? "on" : "off")
            self?.viewModel.startAtLoginError = LoginItem.set(on)
            self?.reload()
        }
        viewModel.onSetShowTotal = { [weak self] on in engine.showTotalInMenuBar = on; self?.reload() }
        viewModel.onSetIdleMinutes = { [weak self] m in engine.idleMinutes = m; self?.reload(); self?.onChange?() }
        viewModel.onSetCallsActive = { [weak self] on in engine.callsActive = on; self?.reload(); self?.onChange?() }
        viewModel.onSetChromeTitles = { [weak self] on in engine.readChromeTitles = on; self?.reload() }
        viewModel.onOpenSystemSettings = { engine.openSystemSettings() }

        // Privacy & data
        viewModel.onSetSkipPrivate = { [weak self] on in engine.skipPrivateWindows = on; self?.reload() }
        viewModel.onAddExclusion = { [weak self] kind, pattern in
            self?.write { try db.addExclusion(kind: kind, pattern: pattern) }
            engine.reloadExclusions()
        }
        viewModel.onDeleteExclusion = { [weak self] id in
            self?.write { try db.deleteExclusion(id: id) }
            engine.reloadExclusions()
        }
        viewModel.onSetRetention = { [weak self] days in
            if let days, let self, !confirm("Keep only the last \(days == 365 ? "year" : "\(days) days")?",
                                            "Older days are deleted now and every day from here on. This cannot be undone.",
                                            button: "Delete older days", destructive: true) { return }
            engine.retentionDays = days
            self?.reload()
            self?.onChange?()
        }
        viewModel.onShowInFinder = {
            NSWorkspace.shared.activateFileViewerSelecting([DaylineDatabase.defaultURL])
        }
        viewModel.onExport = { [weak self] format in Exporter.run(format: format, engine: engine, window: self?.window) }
        viewModel.onDeleteAll = { [weak self] in
            guard let self, confirm("Delete all data?",
                                    "All tracked time, rules, excluded apps and sites, and your own categories are removed from this Mac. Your settings stay. This cannot be undone.",
                                    button: "Delete all data", destructive: true) else { return }
            do {
                try engine.deleteAllData()
            } catch {
                NSAlert(error: error).runModal()
            }
            reload()
            onChange?()
        }
    }

    /// Spec 5.4: destructive actions get a confirmation dialog.
    private func confirm(_ title: String, _ message: String, button: String, destructive: Bool = false) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = destructive ? .critical : .warning
        guard destructive else {
            alert.addButton(withTitle: button)
            alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn
        }
        // Destructive: Cancel comes first so it owns Return and Escape; the
        // destructive button needs a deliberate click.
        alert.addButton(withTitle: "Cancel")
        let destroy = alert.addButton(withTitle: button)
        destroy.hasDestructiveAction = true
        destroy.keyEquivalent = ""
        return alert.runModal() == .alertSecondButtonReturn
    }

    func show(section: SettingsSection = .general) {
        if window == nil { window = makeWindow() }
        viewModel.section = section
        reload()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func write(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            Log.line("settings write failed: \(error)")
        }
        engine.reloadCategories()
        reload()
        onChange?()
    }

    private func reload() {
        let db = engine.database
        viewModel.categories = (try? db.categories()) ?? []
        viewModel.rules = (try? db.rules()) ?? []
        let recent = (try? db.recentApps(since: TrackingEngine.now() - 30 * 86_400)) ?? []
        viewModel.recentApps = recent
        var names = Dictionary(recent, uniquingKeysWith: { a, _ in a })
        for rule in viewModel.rules where rule.kind == .app && names[rule.pattern] == nil {
            names[rule.pattern] = appName(rule.pattern)
        }
        viewModel.appNames = names
        let categories = engine.categorizer.categories
        // General
        viewModel.startAtLogin = LoginItem.isOn
        viewModel.showTotal = engine.showTotalInMenuBar
        viewModel.idleMinutes = engine.idleMinutes
        viewModel.callsActive = engine.callsActive
        viewModel.chromeTitles = engine.readChromeTitles
        switch engine.phase {
        case .tracking, .paused: viewModel.accessibilityGranted = true
        default: viewModel.accessibilityGranted = false
        }
        // Privacy & data
        viewModel.skipPrivate = engine.skipPrivateWindows
        viewModel.retentionDays = engine.retentionDays
        viewModel.exclusions = ((try? db.exclusionRows()) ?? []).map {
            SettingsViewModel.Exclusion(id: $0.id, kind: $0.kind, label: $0.kind == .app ? names[$0.pattern] ?? appName($0.pattern) : $0.pattern)
        }
        if let info = try? db.storageInfo() {
            let size = ByteCountFormatter.string(fromByteCount: info.bytes, countStyle: .file)
            viewModel.storageText = info.since.map { "\(size) since \(Date(timeIntervalSince1970: TimeInterval($0)).formatted(.dateTime.day().month(.abbreviated)))" } ?? "\(size), nothing recorded yet"
        }
        viewModel.builtins = BuiltinRules.all
            .map { BuiltinRuleRow(kind: $0.kind, label: $0.label, category: categories[$0.category.id] ?? $0.category) }
            .sorted { $0.category.id != $1.category.id ? $0.category.id < $1.category.id : $0.label.lowercased() < $1.label.lowercased() }
    }

    /// Visible settings may be stale after engine changes (permission, menu bar).
    func refresh() {
        if window?.isVisible ?? false { reload() }
    }

    private func appName(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "Dayline Settings"
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = NSColor(srgbRed: 0x10 / 255, green: 0x11 / 255, blue: 0x13 / 255, alpha: 1)
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: SettingsView(viewModel: viewModel))
        w.setFrameAutosaveName("DaylineSettings")
        if !w.setFrameUsingName("DaylineSettings") { w.center() }
        return w
    }
}

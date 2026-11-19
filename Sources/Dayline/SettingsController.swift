import AppKit
import Categorize
import Domain
import Store
import SwiftUI
import UI

/// Settings (spec 5.4), shown inside the main window in place of the
/// timeline. ⌘, opens it from anywhere.
final class SettingsController {
    private let engine: TrackingEngine
    private let viewModel = SettingsViewModel()
    /// The page the main window swaps in; built once so it keeps its state.
    private(set) lazy var view: NSView = {
        let v = NSHostingView(rootView: SettingsView(viewModel: viewModel))
        v.sizingOptions = []
        return v
    }()
    private var window: NSWindow? { view.window }
    /// Rules or categories changed: refresh the timeline, popover and menu bar.
    var onChange: (() -> Void)?
    var onBack: (() -> Void)?

    init(engine: TrackingEngine) {
        self.engine = engine
        let db = engine.database
        viewModel.onBack = { [weak self] in self?.onBack?() }
        viewModel.onAddRule = { [weak self] kind, pattern, categoryID in
            self?.write { try db.addRule(kind: kind, pattern: pattern, categoryID: categoryID, origin: .user, at: TrackingEngine.now()) }
        }
        viewModel.onSetRuleCategory = { [weak self] id, categoryID in self?.write { try db.setRuleCategory(id: id, categoryID: categoryID) } }
        viewModel.onSort = { [weak self] u, categoryID in
            self?.write { try db.addRule(kind: u.kind, pattern: u.pattern, categoryID: categoryID, origin: .user, at: TrackingEngine.now()) }
        }
        viewModel.onDeleteRule = { [weak self] id in self?.write { try db.deleteRule(id: id) } }
        viewModel.onAddCategory = { [weak self] name, color in self?.write { try db.addCategory(name: name, color: color) } }
        viewModel.onUpdateCategory = { [weak self] c in self?.write { try db.updateCategory(c) } }
        viewModel.onDeleteCategory = { [weak self] c in
            guard let self, let to = askDelete(c) else { return }
            write { try db.mergeCategory(c.id, into: to.id) }
        }

        // Projects
        viewModel.onAddProject = { [weak self] name, clientName in
            self?.write {
                let now = TrackingEngine.now()
                let client = clientName.isEmpty ? nil : try db.addClient(name: clientName, at: now)
                try db.addProject(name: name, clientID: client?.id, at: now)
            }
        }
        viewModel.onAddClient = { [weak self] name in self?.write { try db.addClient(name: name, at: TrackingEngine.now()) } }
        viewModel.onRenameProject = { [weak self] id, name in self?.write { try db.renameProject(id: id, name: name) } }
        viewModel.onRenameClient = { [weak self] id, name in self?.write { try db.renameClient(id: id, name: name) } }
        viewModel.onDeleteProjectRule = { [weak self] id in self?.write { try db.deleteProjectRule(id: id) } }
        viewModel.onDeleteProject = { [weak self] p in
            guard let self, confirmDelete("Delete \(p.name)?",
                                          "Its \(Durations.format(viewModel.projectMonth[p.id] ?? 0)) this month and all earlier time go back to No project, and what it learned is removed. Your tracked time itself isn’t deleted.",
                                          button: "Delete project") else { return }
            viewModel.openProject = nil
            write { try db.deleteProject(id: p.id) }
        }
        viewModel.onDeleteClient = { [weak self] c in
            guard let self, confirmDelete("Delete \(c.name)?", "Its projects stay, without a client.", button: "Delete client") else { return }
            write { try db.deleteClient(id: c.id) }
        }

        // General
        viewModel.idleChoices = TrackingEngine.idleChoices
        viewModel.onSetStartAtLogin = { [weak self] on in
            try? db.setSetting("login.chosen", on ? "on" : "off")
            self?.viewModel.startAtLoginError = LoginItem.set(on)
            self?.reload()
        }
        viewModel.onSetShowTotal = { [weak self] on in engine.showTotalInMenuBar = on; self?.reload() }
        viewModel.breakChoices = BreakReminder.choices
        viewModel.onSetBreakReminder = { [weak self] on in
            engine.breakReminder = on
            if on { Recap.requestPermission() }
            self?.reload()
        }
        viewModel.onSetBreakMinutes = { [weak self] m in engine.breakMinutes = m; self?.reload() }
        viewModel.recapHours = TrackingEngine.recapHours
        viewModel.onSetRecapHour = { [weak self] hour in
            engine.recapHour = hour
            if hour != nil { Recap.requestPermission() }
            self?.reload()
        }
        viewModel.onSetIdleMinutes = { [weak self] m in engine.idleMinutes = m; self?.reload(); self?.onChange?() }
        viewModel.onSetCallsActive = { [weak self] on in engine.callsActive = on; self?.reload(); self?.onChange?() }
        viewModel.onSetChromeTitles = { [weak self] on in engine.readChromeTitles = on; self?.reload() }
        viewModel.onOpenSystemSettings = { engine.openSystemSettings() }

        // Privacy & data
        viewModel.onSetSkipPrivate = { [weak self] on in engine.skipPrivateWindows = on; self?.reload() }
        viewModel.onAddExclusion = { [weak self] kind, pattern, mode in
            guard let self else { return }
            let hideSaved: Bool? = mode == .titles ? askHideSaved(pattern: pattern, kind: kind) : false
            guard hideSaved != nil else { return }
            write {
                try db.addExclusion(kind: kind, pattern: pattern, mode: mode)
                if hideSaved == true { try db.hideSavedTitles(kind: kind, pattern: pattern) }
                engine.reloadExclusions()
            }
        }
        viewModel.onSetTitlesOnScreen = { [weak self] m in engine.titlesOnScreen = m; self?.reload(); self?.onChange?() }
        viewModel.onDeleteExclusion = { [weak self] id in
            self?.write { try db.deleteExclusion(id: id); engine.reloadExclusions() }
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

    /// Adding to "Never save titles for": from now on, or also the titles
    /// already saved (replaced by their labels, which cannot be undone).
    /// nil when cancelled.
    private func askHideSaved(pattern: String, kind: Rule.Kind) -> Bool? {
        let name = kind == .app ? appName(pattern) : pattern
        let alert = NSAlert()
        alert.messageText = "Never save titles for \(name)?"
        alert.informativeText = "From now on its window and tab titles are not saved; its time still counts. Titles saved before can be replaced too. That cannot be undone."
        alert.addButton(withTitle: "From now on")
        alert.addButton(withTitle: "Also replace saved titles")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return false
        case .alertSecondButtonReturn: return true
        default: return nil
        }
    }

    /// Deleting a category asks where its time goes: Uncategorized (a plain
    /// delete) or another category (a merge). nil when cancelled.
    private func askDelete(_ c: ActivityCategory) -> ActivityCategory? {
        // Uncategorized first, so the default is a plain delete.
        let rest = viewModel.categories.filter { $0.id != c.id }
        let others = rest.filter { $0.id == ActivityCategory.uncategorized.id }
            + rest.filter { $0.id != ActivityCategory.uncategorized.id }
        let alert = NSAlert()
        alert.messageText = "Delete \(c.name)?"
        alert.informativeText = "Its time, rules and corrections move to:"
        alert.alertStyle = .critical
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 26), pullsDown: false)
        picker.addItems(withTitles: others.map(\.name))
        alert.accessoryView = picker
        // Cancel first so it owns Return and Escape; Delete needs a click.
        alert.addButton(withTitle: "Cancel")
        let delete = alert.addButton(withTitle: "Delete")
        delete.hasDestructiveAction = true
        delete.keyEquivalent = ""
        guard alert.runModal() == .alertSecondButtonReturn, others.indices.contains(picker.indexOfSelectedItem) else { return nil }
        return others[picker.indexOfSelectedItem]
    }

    /// Cancel owns Return and Escape; the destructive button needs a click.
    private func confirmDelete(_ title: String, _ text: String, button: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Cancel")
        let delete = alert.addButton(withTitle: button)
        delete.hasDestructiveAction = true
        delete.keyEquivalent = ""
        return alert.runModal() == .alertSecondButtonReturn
    }

    /// Fresh values before the page is shown; `project` opens its panel.
    func prepare(section: SettingsSection = .general, project: Int64? = nil) {
        viewModel.section = section
        viewModel.openProject = project
        reload()
    }

    /// Each project's time this month, from its segments (hand-picked or by rule).
    private func projectMonthTotals(_ resolver: ProjectResolver) -> [Int64: Int64] {
        guard !resolver.isEmpty else { return [:] }
        let cal = Calendar.current
        let start = cal.dateInterval(of: .month, for: Date())?.start ?? Date()
        let from = Int64(start.timeIntervalSince1970), now = TrackingEngine.now()
        var totals: [Int64: Int64] = [:]
        for s in (try? engine.store.segments(from: from, to: now)) ?? [] where s.kind == .active {
            guard let p = resolver.resolve(s)?.project else { continue }
            totals[p.id, default: 0] += min(s.end, now) - max(s.start, from)
        }
        return totals
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
        viewModel.clients = (try? db.clients()) ?? []
        viewModel.projects = engine.projects.list
        viewModel.projectRules = engine.projects.rules
        viewModel.projectMonth = projectMonthTotals(engine.projects)
        if let id = viewModel.openProject, !viewModel.projects.contains(where: { $0.id == id }) { viewModel.openProject = nil }
        viewModel.unsorted = engine.unsorted()
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
        viewModel.recapHour = engine.recapHour
        viewModel.breakReminder = engine.breakReminder
        viewModel.breakMinutes = engine.breakMinutes
        viewModel.idleMinutes = engine.idleMinutes
        viewModel.callsActive = engine.callsActive
        viewModel.chromeTitles = engine.readChromeTitles
        switch engine.phase {
        case .tracking, .paused: viewModel.accessibilityGranted = true
        default: viewModel.accessibilityGranted = false
        }
        // Privacy & data
        viewModel.skipPrivate = engine.skipPrivateWindows
        viewModel.titlesOnScreen = engine.titlesOnScreen
        viewModel.retentionDays = engine.retentionDays
        viewModel.exclusions = ((try? db.exclusionRows()) ?? []).map {
            SettingsViewModel.Exclusion(id: $0.id, kind: $0.kind, label: $0.kind == .app ? names[$0.pattern] ?? appName($0.pattern) : $0.pattern,
                                        mode: $0.mode)
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
}

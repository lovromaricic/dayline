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
        viewModel.onArchiveProject = { [weak self] p, archive in
            self?.write { try db.setProjectArchived(id: p.id, at: archive ? TrackingEngine.now() : nil) }
        }
        viewModel.onMoveProject = { [weak self] p, c in self?.write { try db.setProjectClient(id: p.id, clientID: c?.id) } }
        viewModel.onEditClientRate = { [weak self] c in
            guard let self, let (rate, currency) = askRate("Hourly rate for \(c.name)",
                                                         "Used for all its projects unless one has its own. Leave empty for hours only.",
                                                         rate: c.rate, currency: c.currency ?? defaultCurrency, currencyPicker: true) else { return }
            write { try db.setClientRate(id: c.id, rate: rate, currency: currency) }
        }
        viewModel.onEditProjectRate = { [weak self] p in
            guard let self else { return }
            let hint = p.clientRate.map { "Leave empty to use \(p.clientName ?? "the client")’s rate (\(Self.plain($0)) \(p.currency))." }
                ?? "Leave empty for hours only."
            // A project without a client keeps its currency on a client-less default: your Mac's.
            guard let (rate, _) = askRate("Hourly rate for \(p.name)", hint, rate: p.rate, currency: p.currency, currencyPicker: false) else { return }
            write { try db.setProjectRate(id: p.id, rate: rate) }
        }
        viewModel.onExportClient = { [weak self] c in
            self?.export(name: c.name) { $0.clientID == c.id }
        }
        viewModel.onExportProject = { [weak self] p in
            self?.export(name: [p.clientName, p.name].compactMap { $0 }.joined(separator: "-")) { $0.id == p.id }
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

    private static func plain(_ n: Double) -> String { n.rounded() == n ? String(Int(n)) : String(format: "%.2f", n) }

    /// Rate per hour and currency; nil when cancelled. An empty field clears the rate.
    private func askRate(_ title: String, _ text: String, rate: Double?, currency: String,
                         currencyPicker: Bool) -> (Double?, String?)? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        let field = NSTextField(string: rate.map(Self.plain) ?? "")
        field.placeholderString = "60"
        field.frame = NSRect(x: 0, y: 0, width: 100, height: 24)
        let codes = Array(Set(["EUR", "USD", "GBP", "CHF", defaultCurrency, currency])).sorted()
        let picker = NSPopUpButton(frame: NSRect(x: 108, y: -1, width: 90, height: 26), pullsDown: false)
        picker.addItems(withTitles: codes)
        picker.selectItem(withTitle: currency)
        picker.isEnabled = currencyPicker
        let label = NSTextField(labelWithString: "per hour")
        label.frame = NSRect(x: 206, y: 3, width: 80, height: 18)
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 290, height: 26))
        [field, picker, label].forEach(box.addSubview)
        alert.accessoryView = box
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return (Double(text).flatMap { $0 > 0 ? $0 : nil }, picker.titleOfSelectedItem)
    }

    /// "Export hours": period, rows, rounding and format, then where to save.
    private func export(name: String, include: @escaping (Project) -> Bool) {
        let alert = NSAlert()
        alert.messageText = "Export hours for \(name)"
        alert.informativeText = "One row per project for each day, week or month, with rates and amounts where set."
        func popup(_ items: [String], selected: Int, y: CGFloat) -> NSPopUpButton {
            let p = NSPopUpButton(frame: NSRect(x: 90, y: y, width: 190, height: 26), pullsDown: false)
            p.addItems(withTitles: items)
            p.selectItem(at: selected)
            return p
        }
        func label(_ s: String, y: CGFloat) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.frame = NSRect(x: 0, y: y + 4, width: 86, height: 18)
            return l
        }
        let periods = ["This week", "Last week", "This month", "Last month"]
        let period = popup(periods, selected: 2, y: 96)
        let rows = popup(Timesheet.Grouping.allCases.map(\.rawValue), selected: 0, y: 64)
        let rounding = popup(["None", "15 minutes", "30 minutes"], selected: 0, y: 32)
        let format = popup(TimesheetFile.Format.allCases.map(\.rawValue), selected: 0, y: 0)
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 290, height: 124))
        for (l, y) in [("Period", 96), ("One row per", 64), ("Round to", 32), ("Format", 0)] as [(String, CGFloat)] {
            box.addSubview(label(l, y: y))
        }
        [period, rows, rounding, format].forEach(box.addSubview)
        alert.accessoryView = box
        alert.addButton(withTitle: "Export…")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let cal = Calendar.current, now = Date()
        let unit: Calendar.Component = period.indexOfSelectedItem < 2 ? .weekOfYear : .month
        let anchor = period.indexOfSelectedItem % 2 == 1 ? cal.date(byAdding: unit, value: -1, to: now)! : now
        guard let range = cal.dateInterval(of: unit, for: anchor) else { return }
        let grouping = Timesheet.Grouping.allCases[rows.indexOfSelectedItem]
        let fileFormat = TimesheetFile.Format.allCases[format.indexOfSelectedItem]
        let sheet = timesheet(range, grouping: grouping, round: [0, 15, 30][rounding.indexOfSelectedItem], include: include)
        guard !sheet.rows.isEmpty else {
            let empty = NSAlert()
            empty.messageText = "Nothing to export"
            empty.informativeText = "\(name) has no time in that period."
            empty.runModal()
            return
        }
        let save = NSSavePanel()
        let when = unit == .month ? range.start.formatted(.dateTime.month(.wide).year())
            : "week of \(range.start.formatted(.dateTime.day().month(.abbreviated).year()))"
        save.nameFieldStringValue = "\(name) \(when).\(fileFormat.fileExtension)".replacingOccurrences(of: "/", with: "-")
        save.allowedContentTypes = [fileFormat == .xlsx ? .init(filenameExtension: "xlsx")! : .commaSeparatedText]
        guard save.runModal() == .OK, let url = save.url else { return }
        do {
            try TimesheetFile.data(sheet, grouping: grouping, format: fileFormat).write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            Log.line("timesheet export failed: \(error)")
            let fail = NSAlert(error: error)
            fail.runModal()
        }
    }

    /// The days in `range`, built as the timeline builds them, so totals match.
    private func timesheet(_ range: DateInterval, grouping: Timesheet.Grouping, round: Int,
                           include: @escaping (Project) -> Bool) -> Timesheet {
        let cal = Calendar.current, now = TrackingEngine.now()
        let categorizer = engine.categorizer, projects = engine.projects
        var days: [(dayStart: Int64, blocks: [Block])] = []
        var day = cal.startOfDay(for: range.start)
        while day < range.end, Int64(day.timeIntervalSince1970) <= now {
            let next = cal.date(byAdding: .day, value: 1, to: day)!
            let from = Int64(day.timeIntervalSince1970)
            let segs = (try? engine.store.segments(from: from, to: Int64(next.timeIntervalSince1970))) ?? []
            if !segs.isEmpty {
                let report = DayReport(segments: segs, dayStart: from, now: now, resolve: { categorizer.resolve($0) })
                    .withProjects(projects, segments: segs)
                days.append((from, report.blocks))
            }
            day = next
        }
        return Timesheet(days: days, include: include, grouping: grouping, round: round)
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

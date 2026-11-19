import Domain
import SwiftUI

public enum ExportFormat: String, Sendable {
    case csv = "CSV"
    case json = "JSON"
}

/// Page title + subtitle (screens 08–10).
private func pageHeader(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.system(size: 30, weight: .light)).tracking(-0.3)
        Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.textMuted)
    }
}

/// A titled group of rows in a bordered card.
private func group(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title).eyebrow()
        VStack(spacing: 0) { rows() }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.02)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
    }
}

/// SettingRow (spec 8): title, subtitle, trailing control; hairline above unless first.
private struct SettingRow<Trailing: View>: View {
    var title: String
    var subtitle: String
    var first = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(minHeight: 52)
        .overlay(alignment: .top) { Rectangle().fill(first ? .clear : Theme.border).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }
}

private func toggle(_ label: String, _ isOn: Bool, _ set: ((Bool) -> Void)?) -> some View {
    Toggle("", isOn: Binding(get: { isOn }, set: { set?($0) })).toggleStyle(LimeSwitch()).accessibilityLabel(label)
}

private func outlineButton(_ title: String, color: Color = Theme.text, border: Color = Theme.border,
                           action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title).font(.system(size: 13)).foregroundStyle(color)
            .padding(.horizontal, 14).frame(height: 34)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(border))
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}

private func recapLabel(_ hour: Int?) -> String { hour.map { "At \($0):00" } ?? "Off" }

/// SelectField (spec 8): bordered menu with a chevron.
private func select<T: Hashable>(_ current: String, options: [T], label: @escaping (T) -> String,
                                 pick: @escaping (T) -> Void) -> some View {
    Menu {
        ForEach(options, id: \.self) { o in Button(label(o)) { pick(o) } }
    } label: {
        HStack(spacing: 22) {
            Text(current).font(.system(size: 13))
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textMuted)
        }
        .padding(.leading, 12).padding(.trailing, 14).frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surfaceControl))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
        .contentShape(Rectangle())
    }
    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
}

func minutesLabel(_ m: Int) -> String { "\(m) minute\(m == 1 ? "" : "s")" }

// MARK: - General (screen 08)

struct GeneralPage: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                pageHeader("General", "Dayline works quietly in the background. Change how it behaves here.")
                group("STARTUP") {
                    SettingRow(title: "Start at login", subtitle: vm.startAtLoginError.map { "macOS refused: \($0)" }
                               ?? "Tracking is always on without you thinking about it.", first: true) {
                        toggle("Start at login", vm.startAtLogin, vm.onSetStartAtLogin)
                    }
                    SettingRow(title: "Show today’s total in the menu bar", subtitle: "The ring and time next to the clock.") {
                        toggle("Show today’s total in the menu bar", vm.showTotal, vm.onSetShowTotal)
                    }
                    SettingRow(title: "End-of-day recap",
                               subtitle: "One notification with the day’s total. Click it to open the day.") {
                        select(recapLabel(vm.recapHour), options: [nil] + vm.recapHours.map { Optional($0) }, label: recapLabel) {
                            vm.onSetRecapHour?($0)
                        }
                    }
                }
                group("BREAKS") {
                    SettingRow(title: "Break reminder",
                               subtitle: "A notification when you’ve worked a while without stepping away. Never during calls.", first: true) {
                        toggle("Break reminder", vm.breakReminder, vm.onSetBreakReminder)
                    }
                    if vm.breakReminder {
                        SettingRow(title: "Remind me after", subtitle: "Time at your Mac without a break. Stepping away resets it.") {
                            select(minutesLabel(vm.breakMinutes), options: vm.breakChoices, label: minutesLabel) { vm.onSetBreakMinutes?($0) }
                        }
                    }
                }
                group("TRACKING") {
                    SettingRow(title: "Count me as away after", subtitle: "No keyboard or mouse activity for this long pauses the clock.",
                               first: true) {
                        select(minutesLabel(vm.idleMinutes), options: vm.idleChoices, label: minutesLabel) { vm.onSetIdleMinutes?($0) }
                    }
                    SettingRow(title: "Count calls as meetings",
                               subtitle: "While the mic or camera is on, the whole call counts as Meetings and you stay tracked, even if you are not typing.") {
                        toggle("Count calls as meetings", vm.callsActive, vm.onSetCallsActive)
                    }
                    SettingRow(title: "Read browser tab titles", subtitle: "Chrome and Safari. Uses the window title, so no extension is needed.") {
                        toggle("Read browser tab titles", vm.chromeTitles, vm.onSetChromeTitles)
                    }
                }
                group("PERMISSIONS") {
                    SettingRow(title: "Accessibility access", subtitle: "Needed to see which app and tab you are in.", first: true) {
                        HStack(spacing: 20) {
                            HStack(spacing: 8) {
                                Image(systemName: vm.accessibilityGranted ? "checkmark.circle" : "exclamationmark.circle")
                                Text(vm.accessibilityGranted ? "Granted" : "Not granted")
                            }
                            .font(.system(size: 13))
                            .foregroundStyle(vm.accessibilityGranted ? Theme.ok : Theme.danger)
                            outlineButton("Open System Settings") { vm.onOpenSystemSettings?() }
                        }
                    }
                }
            }
            .padding(.top, 16).padding(.horizontal, 40).padding(.bottom, 32).darkScroller()
        }
    }
}

// MARK: - Privacy & data (screen 10)

struct PrivacyPage: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageHeader("Privacy & data", "Everything stays on this Mac. Decide what Dayline ignores and what it keeps.")
                group("PRIVATE BROWSING") {
                    SettingRow(title: "Private browsing windows",
                               subtitle: vm.skipPrivate ? "Chrome Incognito and Safari Private windows are skipped." : "Chrome Incognito and Safari Private windows are recorded like any other window.",
                               first: true) {
                        toggle("Skip private browsing windows", vm.skipPrivate, vm.onSetSkipPrivate)
                    }
                }
                group("TITLES") {
                    SettingRow(title: "Hide titles on screen", subtitle: titlesSubtitle, first: true) {
                        select(vm.titlesOnScreen.label, options: TitlesOnScreen.allCases, label: \.label) { vm.onSetTitlesOnScreen?($0) }
                    }
                    SettingRow(title: "Never save titles for",
                               subtitle: "Their time still counts. Titles show as “Hidden title A”, “Hidden title B”.") { EmptyView() }
                    NeverTrackList(vm: vm, mode: .titles, chipWidth: 64)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
                }
                group("YOUR DATA") {
                    SettingRow(title: "Keep history for", subtitle: "Older days are deleted automatically.", first: true) {
                        select(retentionLabel(vm.retentionDays), options: vm.retentionChoices, label: retentionLabel) { vm.onSetRetention?($0) }
                    }
                    SettingRow(title: "Stored on this Mac", subtitle: vm.storageText) {
                        outlineButton("Show in Finder") { vm.onShowInFinder?() }
                    }
                    SettingRow(title: "Export", subtitle: "All your tracked time as a file you own.") {
                        HStack(spacing: 8) {
                            outlineButton("CSV") { vm.onExport?(.csv) }
                            outlineButton("JSON") { vm.onExport?(.json) }
                        }
                    }
                    SettingRow(title: "Delete everything", subtitle: "Removes all tracked time and rules. This cannot be undone.") {
                        outlineButton("Delete all data", color: Theme.danger, border: Theme.danger.opacity(0.4)) { vm.onDeleteAll?() }
                    }
                }
            }
            .padding(.top, 16).padding(.horizontal, 40).padding(.bottom, 32).darkScroller()
        }
    }

    private var titlesSubtitle: String {
        switch vm.titlesOnScreen {
        case .never: "Window and tab titles show everywhere."
        case .calls: "Titles are hidden while you’re on a call. They are still saved."
        case .always: "Titles are always hidden on screen. They are still saved."
        }
    }

    private func retentionLabel(_ days: Int?) -> String {
        switch days {
        case nil: "Forever"
        case 365: "1 year"
        case let d?: "\(d) days"
        }
    }
}

/// Never track (spec 5.4, on Categories & rules): apps and sites whose time is
/// not recorded at all. Private browsing windows stay on Privacy & data.
struct NeverTrackList: View {
    @ObservedObject var vm: SettingsViewModel
    /// The same list serves "Never save titles for" on Privacy & data.
    var mode = ExclusionMode.skip
    /// Matches the rule rows above it.
    var chipWidth: CGFloat = 150
    @State private var adding = false
    @State private var kind = Rule.Kind.app
    @State private var site = ""

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, e in
                HStack(spacing: 14) {
                    kindChip(e.kind).frame(width: chipWidth, alignment: .leading)
                    Text(e.label).font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: { vm.onDeleteExclusion?(e.id) }) {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textMuted)
                            .frame(width: 32, height: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(mode == .skip ? "Track it again" : "Save its titles again")
                    .accessibilityLabel(mode == .skip ? "Stop excluding \(e.label)" : "Save titles for \(e.label) again")
                }
                .padding(.leading, 20).padding(.trailing, 12).padding(.vertical, 8)
                .frame(minHeight: 46)
                .overlay(alignment: .top) { Rectangle().fill(i == 0 ? .clear : Theme.border).frame(height: 1) }
            }
            if adding { addRow } else {
                Button(action: { adding = true }) {
                    HStack(spacing: 8) {
                        Text("+").font(.system(size: 16))
                        Text("Add an app or site").font(.system(size: 13))
                    }
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { Rectangle().fill(items.isEmpty ? .clear : Theme.border).frame(height: 1) }
            }
        }
    }

    private var items: [SettingsViewModel.Exclusion] { vm.exclusions.filter { $0.mode == mode } }

    private var addRow: some View {
        HStack(spacing: 14) {
            Menu {
                Button("App") { kind = .app }
                Button("Site") { kind = .site }
            } label: {
                HStack(spacing: 6) {
                    Text(kind.label).font(.system(size: 12))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 10).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.10)))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            if kind == .app {
                Menu {
                    ForEach(vm.recentApps, id: \.0) { app in
                        Button(app.1) { vm.onAddExclusion?(.app, app.0, mode); adding = false }
                    }
                } label: {
                    Text("Choose an app").font(.system(size: 14)).foregroundStyle(Theme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            } else {
                TextField("example.com", text: $site, onCommit: addSite).textFieldStyle(.plain).font(.system(size: 14))
            }
            if kind == .site {
                Button("Add", action: addSite).buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
            }
            Button(action: { adding = false; site = "" }) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textMuted)
                    .frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Cancel")
        }
        .padding(.leading, 20).padding(.trailing, 12).padding(.vertical, 8)
        .frame(minHeight: 46)
        .background(Theme.accent.opacity(0.04))
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        .onExitCommand { adding = false }
    }

    private func addSite() {
        var p = site.trimmingCharacters(in: .whitespaces).lowercased()
        if let r = p.range(of: "://") { p = String(p[r.upperBound...]) }
        if let slash = p.firstIndex(of: "/") { p = String(p[..<slash]) }
        if p.hasPrefix("www.") { p.removeFirst(4) }
        guard !p.isEmpty else { return }
        vm.onAddExclusion?(.site, p, mode)
        site = ""
        adding = false
    }
}

// MARK: - Projects

/// Clients and their projects, with time this month. A project opens a panel
/// with what it learned ("Auto-adds"), where a wrong rule is removed.
struct ProjectsPage: View {
    @ObservedObject var vm: SettingsViewModel
    @State private var adding: Adding?
    @State private var name = ""
    @State private var client = ""
    @FocusState private var nameFocused: Bool

    enum Adding { case project, client }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .bottom) {
                        pageHeader("Projects", "Grouped by client. Totals are for this month.")
                        Spacer()
                        HStack(spacing: 8) {
                            outlineButton("+ New client") { start(.client) }
                            outlineButton("+ New project") { start(.project) }
                        }
                    }
                    if let adding { form(adding) }
                    if active.isEmpty && adding == nil {
                        empty
                    }
                    ForEach(groups, id: \.0) { client, projects in
                        clientGroup(client, projects)
                    }
                    // Clients without projects yet still show, so you can add to them.
                    ForEach(vm.clients.filter { c in !active.contains { $0.clientID == c.id } }) { c in
                        clientGroup(c, [])
                    }
                    if !archived.isEmpty { archivedSection }
                }
                .padding(.top, 16).padding(.horizontal, 40).padding(.bottom, 32).darkScroller()
            }
            if let id = vm.openProject, let p = vm.projects.first(where: { $0.id == id }) {
                ProjectPanel(vm: vm, project: p).id(p.id)
            }
        }
    }

    private var active: [Project] { vm.projects.filter { !$0.isArchived } }
    private var archived: [Project] { vm.projects.filter(\.isArchived) }

    /// Finished projects: out of the pickers, totals kept for past invoices.
    private var archivedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("ARCHIVED · \(archived.count)").eyebrow()
                Text("Hidden from pickers. Their past time still counts.").font(.system(size: 12)).foregroundStyle(Theme.textFaint)
            }
            VStack(spacing: 0) {
                ForEach(Array(archived.enumerated()), id: \.element.id) { i, p in
                    HStack(spacing: 16) {
                        Button { vm.openProject = vm.openProject == p.id ? nil : p.id } label: {
                            Text(p.fullName).font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button("Unarchive") { vm.onArchiveProject?(p, false) }
                            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 18).frame(height: 40)
                    .overlay(alignment: .top) { Rectangle().fill(i == 0 ? .clear : Theme.border).frame(height: 1) }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border.opacity(0.7)))
        }
    }

    private var groups: [(Client?, [Project])] {
        var out: [(Client?, [Project])] = []
        for p in active {
            let c = p.clientID.flatMap { id in vm.clients.first { $0.id == id } }
            if let i = out.firstIndex(where: { $0.0?.id == c?.id }) { out[i].1.append(p) } else { out.append((c, [p])) }
        }
        return out
    }

    private func start(_ a: Adding) {
        adding = a
        name = ""
        client = ""
        DispatchQueue.main.async { nameFocused = true }
    }

    private func submit() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, let a = adding else { return }
        switch a {
        case .project: vm.onAddProject?(n, client.trimmingCharacters(in: .whitespaces))
        case .client: vm.onAddClient?(n)
        }
        adding = nil
    }

    private func form(_ a: Adding) -> some View {
        HStack(spacing: 8) {
            TextField(a == .project ? "Project name" : "Client name", text: $name)
                .textFieldStyle(.plain).font(.system(size: 13))
                .focused($nameFocused)
                .onSubmit(submit)
                .padding(.horizontal, 12).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surfaceControl))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.accent.opacity(0.6)))
            if a == .project {
                HStack(spacing: 0) {
                    TextField("Client (optional)", text: $client)
                        .textFieldStyle(.plain).font(.system(size: 13))
                        .onSubmit(submit)
                    if !vm.clients.isEmpty {
                        Menu {
                            Button("No client") { client = "" }
                            Divider()
                            ForEach(vm.clients) { c in Button(c.name) { client = c.name } }
                        } label: {
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textMuted)
                                .frame(width: 24, height: 30).contentShape(Rectangle())
                        }
                        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                        .help("Pick a client")
                    }
                }
                .padding(.leading, 12).padding(.trailing, 4).frame(width: 220, height: 34)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surfaceControl))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
            }
            outlineButton("Cancel") { adding = nil }
            Button(action: submit) {
                Text("Add").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .onExitCommand { adding = nil }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Text("Add your first project").font(.system(size: 18, weight: .light))
            Text("Then pick it on any block, and Dayline learns where similar work belongs. A client is optional.")
                .font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
    }

    private func clientGroup(_ c: Client?, _ projects: [Project]) -> some View {
        let total = projects.reduce(Int64(0)) { $0 + (vm.projectMonth[$1.id] ?? 0) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text((c?.name ?? "No client").uppercased()).eyebrow()
                Text(clientTotal(c, projects, total)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.textFaint)
                Spacer()
                if let c {
                    Button("Export") { vm.onExportClient?(c) }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        .disabled(projects.isEmpty)
                    Menu {
                        Button("Rename") { rename(c) }
                        Button(c.rate == nil ? "Set rate" : "Edit rate") { vm.onEditClientRate?(c) }
                        Divider()
                        Button("Delete client") { vm.onDeleteClient?(c) }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                            .frame(width: 24, height: 20).contentShape(Rectangle())
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("\(c.name) options")
                }
            }
            VStack(spacing: 0) {
                if projects.isEmpty {
                    Text("No projects yet.").font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(projects.enumerated()), id: \.element.id) { i, p in
                    Button { vm.openProject = vm.openProject == p.id ? nil : p.id } label: {
                        HStack(spacing: 16) {
                            Text(p.name).font(.system(size: 14))
                            Spacer()
                            Text(Durations.format(vm.projectMonth[p.id] ?? 0)).font(.system(size: 13).monospacedDigit())
                                .foregroundStyle(Theme.textMuted)
                            if let money = vm.amount(p) {
                                Text(money).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                                    .frame(minWidth: 64, alignment: .trailing)
                            }
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textFaint)
                        }
                        .padding(.horizontal, 18).frame(height: 44)
                        .background(vm.openProject == p.id ? Color.white.opacity(0.06) : .clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .top) { Rectangle().fill(i == 0 ? .clear : Theme.border).frame(height: 1) }
                    .accessibilityHint("Shows what this project auto-adds")
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.02)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
        }
    }

    /// "34h 20m · €2,243", or "· no rate" for a client without one.
    private func clientTotal(_ c: Client?, _ projects: [Project], _ total: Int64) -> String {
        let time = Durations.format(total)
        guard let c else { return time }
        var sums: [String: Double] = [:]
        for p in projects { if let r = p.hourlyRate { sums[p.currency, default: 0] += Double(vm.projectMonth[p.id] ?? 0) / 3600 * r } }
        if sums.isEmpty { return c.rate == nil ? "\(time) · no rate" : time }
        return ([time] + sums.sorted { $0.key < $1.key }.map { Fmt.money($0.value, $0.key) }).joined(separator: " · ")
    }

    private func rename(_ c: Client) {
        if let n = askName("Rename client", c.name) { vm.onRenameClient?(c.id, n) }
    }
}

/// One project's details: time, what it auto-adds, rename and delete.
private struct ProjectPanel: View {
    @ObservedObject var vm: SettingsViewModel
    let project: Project

    private var rules: [ProjectRule] { vm.projectRules.filter { $0.projectID == project.id } }

    private var rateText: String {
        if let r = project.rate { return "Own rate · \(Fmt.money(r, project.currency)) / h" }
        if let r = project.clientRate { return "Client rate · \(Fmt.money(r, project.currency)) / h" }
        return "No rate · hours only"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if let c = project.clientName { Text(c).font(.system(size: 12)).foregroundStyle(Theme.textMuted) }
                    Text(project.name).font(.system(size: 24, weight: .light))
                }
                Spacer()
                Button { vm.openProject = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textMuted)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Close")
                .keyboardShortcut(.cancelAction)
            }
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Durations.format(vm.projectMonth[project.id] ?? 0)).font(.system(size: 22, weight: .light).monospacedDigit())
                    Text("this month").font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                }
                if let money = vm.amount(project), let rate = project.hourlyRate {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(money).font(.system(size: 22, weight: .light).monospacedDigit())
                        Text("at \(Fmt.money(rate, project.currency)) / h").font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                    }
                }
            }
            HStack(spacing: 6) {
                Text(rateText).font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                Button("Change") { vm.onEditProjectRate?(project) }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("AUTO-ADDS").eyebrow()
                Text("Blocks matching these go to \(project.name) by themselves.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if rules.isEmpty {
                    Text("Nothing yet. Pick \(project.name) on a block and choose Always.")
                        .font(.system(size: 13)).foregroundStyle(Theme.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(rules.enumerated()), id: \.element.id) { i, r in
                            HStack(spacing: 10) {
                                Text(r.kind == .titleContains ? "Title" : r.kind.label)
                                    .font(.system(size: 11)).foregroundStyle(Theme.textMuted).frame(width: 34, alignment: .leading)
                                Text(r.pattern).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 4)
                                Button { vm.onDeleteProjectRule?(r.id) } label: {
                                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textFaint)
                                        .frame(width: 20, height: 20).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Stop adding these to \(project.name)")
                                .accessibilityLabel("Remove \(r.pattern)")
                            }
                            .padding(.horizontal, 12).frame(height: 36)
                            .overlay(alignment: .top) { Rectangle().fill(i == 0 ? .clear : Theme.border).frame(height: 1) }
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
                    Text("Removing one keeps past blocks you moved by hand where they are.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Button("Export hours") { vm.onExportProject?(project) }
                    .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                Menu {
                    Button("No client") { vm.onMoveProject?(project, nil) }.disabled(project.clientID == nil)
                    Divider()
                    ForEach(vm.clients) { c in
                        Button(c.name) { vm.onMoveProject?(project, c) }.disabled(c.id == project.clientID)
                    }
                } label: {
                    Text("Move to client").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                Button(project.isArchived ? "Unarchive" : "Archive") { vm.onArchiveProject?(project, !project.isArchived) }
                    .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    .help(project.isArchived ? "Back in the pickers; its auto-adds add new work again"
                          : "Hides it from pickers and stops its auto-adds; its past time stays")
                Button("Rename") {
                    if let n = askName("Rename project", project.name) { vm.onRenameProject?(project.id, n) }
                }
                .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                Button("Delete project") { vm.onDeleteProject?(project) }
                    .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.danger)
            }
        }
        .padding(.top, 24).padding(.horizontal, 24).padding(.bottom, 24)
        .frame(width: 320, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white.opacity(0.02))
        .overlay(alignment: .leading) { Rectangle().fill(Theme.border).frame(width: 1) }
    }
}

/// A small name prompt (rename); nil when cancelled or left empty.
@MainActor
private func askName(_ title: String, _ current: String) -> String? {
    let alert = NSAlert()
    alert.messageText = title
    let field = NSTextField(string: current)
    field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
    alert.accessoryView = field
    alert.addButton(withTitle: "Rename")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = field
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    let name = field.stringValue.trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? nil : name
}

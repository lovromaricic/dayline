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
                }
                group("TRACKING") {
                    SettingRow(title: "Count me as away after", subtitle: "No keyboard or mouse activity for this long pauses the clock.",
                               first: true) {
                        select(minutesLabel(vm.idleMinutes), options: vm.idleChoices, label: minutesLabel) { vm.onSetIdleMinutes?($0) }
                    }
                    SettingRow(title: "Count calls as active",
                               subtitle: "Mic or camera in use keeps you tracked as a Meeting, even if you are not typing.") {
                        toggle("Count calls as active", vm.callsActive, vm.onSetCallsActive)
                    }
                    SettingRow(title: "Read Chrome tab titles", subtitle: "Uses the window title, so no extension is needed.") {
                        toggle("Read Chrome tab titles", vm.chromeTitles, vm.onSetChromeTitles)
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
            .padding(.top, 16).padding(.horizontal, 40).padding(.bottom, 32)
        }
    }
}

// MARK: - Privacy & data (screen 10)

struct PrivacyPage: View {
    @ObservedObject var vm: SettingsViewModel
    @State private var adding = false
    @State private var kind = Rule.Kind.app
    @State private var site = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageHeader("Privacy & data", "Everything stays on this Mac. Decide what Dayline ignores and what it keeps.")
                group("NEVER TRACK") {
                    SettingRow(title: "Private browsing windows",
                               subtitle: vm.skipPrivate ? "Chrome Incognito windows are skipped." : "Chrome Incognito windows are recorded like any other window.",
                               first: true) {
                        toggle("Skip private browsing windows", vm.skipPrivate, vm.onSetSkipPrivate)
                    }
                    ForEach(vm.exclusions) { e in
                        HStack(spacing: 14) {
                            kindChip(e.kind).frame(width: 52, alignment: .leading)
                            Text(e.label).font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading)
                            Button(action: { vm.onDeleteExclusion?(e.id) }) {
                                Image(systemName: "xmark").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textMuted)
                                    .frame(width: 32, height: 32).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Stop excluding \(e.label)")
                        }
                        .padding(.leading, 20).padding(.trailing, 12).padding(.vertical, 8)
                        .frame(minHeight: 46)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
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
                        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
                    }
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
                        outlineButton("Delete all data…", color: Theme.danger, border: Theme.danger.opacity(0.4)) { vm.onDeleteAll?() }
                    }
                }
            }
            .padding(.top, 16).padding(.horizontal, 40).padding(.bottom, 32)
        }
    }

    private func retentionLabel(_ days: Int?) -> String {
        switch days {
        case nil: "Forever"
        case 365: "1 year"
        case let d?: "\(d) days"
        }
    }

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
                        Button(app.1) { vm.onAddExclusion?(.app, app.0); adding = false }
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
        vm.onAddExclusion?(.site, p)
        site = ""
        adding = false
    }
}

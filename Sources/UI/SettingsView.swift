import Domain
import SwiftUI

public enum SettingsSection: String, CaseIterable, Sendable {
    case general = "General"
    case categories = "Categories & rules"
    case projects = "Projects"
    case privacy = "Privacy & data"
}

/// A built-in rule as the read-only list shows it.
public struct BuiltinRuleRow: Hashable, Sendable {
    public var kind: Rule.Kind
    public var label: String
    public var category: ActivityCategory

    public init(kind: Rule.Kind, label: String, category: ActivityCategory) {
        self.kind = kind
        self.label = label
        self.category = category
    }
}

public final class SettingsViewModel: ObservableObject {
    @Published public var section = SettingsSection.categories
    @Published public var categories: [ActivityCategory] = []
    @Published public var rules: [Rule] = []
    /// Bundle id -> app name, for app rules and the Add rule picker.
    @Published public var appNames: [String: String] = [:]
    /// Apps seen recently, most used first: (bundle id, name).
    @Published public var recentApps: [(String, String)] = []
    @Published public var builtins: [BuiltinRuleRow] = []
    /// "Needs a category": uncategorized apps and sites from the last week.
    @Published public var unsorted: [Unsorted] = []
    /// Adds a rule for the app or site.
    public var onSort: ((Unsorted, Int64) -> Void)?

    public var onBack: (() -> Void)?
    public var onAddRule: ((Rule.Kind, String, Int64) -> Void)?
    public var onSetRuleCategory: ((Int64, Int64) -> Void)?
    public var onDeleteRule: ((Int64) -> Void)?
    public var onAddCategory: ((String, String) -> Void)?
    public var onUpdateCategory: ((ActivityCategory) -> Void)?
    /// The app confirms first and asks where the time goes (Uncategorized by default).
    public var onDeleteCategory: ((ActivityCategory) -> Void)?

    // General (screen 08)
    @Published public var startAtLogin = false
    @Published public var startAtLoginError: String?
    @Published public var showTotal = true
    /// "Break reminder" and its "Remind me after" minutes.
    @Published public var breakReminder = false
    @Published public var breakMinutes = 60
    public var breakChoices = [30, 45, 60, 90]
    public var onSetBreakReminder: ((Bool) -> Void)?
    public var onSetBreakMinutes: ((Int) -> Void)?

    /// End-of-day recap hour; nil is off.
    @Published public var recapHour: Int?
    public var recapHours = [17, 18, 19, 20]
    public var onSetRecapHour: ((Int?) -> Void)?
    @Published public var idleMinutes = 2
    public var idleChoices = [1, 2, 3, 5, 10]
    @Published public var callsActive = true
    @Published public var chromeTitles = true
    @Published public var accessibilityGranted = false
    public var onSetStartAtLogin: ((Bool) -> Void)?
    public var onSetShowTotal: ((Bool) -> Void)?
    public var onSetIdleMinutes: ((Int) -> Void)?
    public var onSetCallsActive: ((Bool) -> Void)?
    public var onSetChromeTitles: ((Bool) -> Void)?
    public var onOpenSystemSettings: (() -> Void)?

    // Privacy & data (screen 10)
    public struct Exclusion: Identifiable, Equatable, Sendable {
        public var id: Int64
        public var kind: Rule.Kind
        public var label: String
        public var mode: ExclusionMode
        public init(id: Int64, kind: Rule.Kind, label: String, mode: ExclusionMode = .skip) {
            self.id = id
            self.kind = kind
            self.label = label
            self.mode = mode
        }
    }
    @Published public var skipPrivate = true
    /// Both lists: Don't track (`.skip`) and Never save titles for (`.titles`).
    @Published public var exclusions: [Exclusion] = []
    @Published public var titlesOnScreen = TitlesOnScreen.never
    public var onSetTitlesOnScreen: ((TitlesOnScreen) -> Void)?
    /// nil = forever
    @Published public var retentionDays: Int?
    public var retentionChoices: [Int?] = [nil, 365, 90]
    /// "4.2 MB since 9 Nov"
    @Published public var storageText = ""
    public var onSetSkipPrivate: ((Bool) -> Void)?
    public var onAddExclusion: ((Rule.Kind, String, ExclusionMode) -> Void)?
    public var onDeleteExclusion: ((Int64) -> Void)?
    public var onSetRetention: ((Int?) -> Void)?
    public var onShowInFinder: (() -> Void)?
    public var onExport: ((ExportFormat) -> Void)?
    public var onDeleteAll: (() -> Void)?

    // Projects
    @Published public var clients: [Client] = []
    /// Grouped by client, no client last.
    @Published public var projects: [Project] = []
    @Published public var projectRules: [ProjectRule] = []
    /// Time this month per project id.
    @Published public var projectMonth: [Int64: Int64] = [:]
    /// The project whose panel is open.
    @Published public var openProject: Int64?
    /// Name and client name (an existing one or a new one); empty is no client.
    public var onAddProject: ((String, String) -> Void)?
    public var onAddClient: ((String) -> Void)?
    public var onRenameProject: ((Int64, String) -> Void)?
    public var onRenameClient: ((Int64, String) -> Void)?
    /// The app confirms first.
    public var onDeleteProject: ((Project) -> Void)?
    public var onDeleteClient: ((Client) -> Void)?
    public var onDeleteProjectRule: ((Int64) -> Void)?

    public init() {}

    /// The category list without the system Uncategorized, for chips.
    var userCategories: [ActivityCategory] { categories.filter { $0.id != ActivityCategory.uncategorized.id } }

    func category(_ id: Int64) -> ActivityCategory {
        categories.first { $0.id == id } ?? .uncategorized
    }

    func displayName(_ rule: Rule) -> String {
        rule.kind == .app ? appNames[rule.pattern] ?? rule.pattern : rule.pattern
    }
}

/// The Settings window (spec 5.4). M4 builds Categories & rules; General and
/// Privacy & data arrive in M6.
public struct SettingsView: View {
    @ObservedObject var vm: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        vm = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            Text("SETTINGS").font(.system(size: 12, weight: .medium)).tracking(1.44).foregroundStyle(Theme.textMuted)
                .frame(maxWidth: .infinity).frame(height: 38)
                .background(Theme.surfaceWindow)
                .zIndex(1)
            HStack(spacing: 0) {
                sidebar
                Group {
                    switch vm.section {
                    case .categories: CategoriesPage(vm: vm)
                    case .general: GeneralPage(vm: vm)
                    case .projects: ProjectsPage(vm: vm)
                    case .privacy: PrivacyPage(vm: vm)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 860, minHeight: 600)
        .background(Theme.surfaceWindow)
        .foregroundStyle(Theme.text)
        .environment(\.colorScheme, .dark)
        // Our own 38 pt header sits in the title bar, beside the window buttons.
        .ignoresSafeArea(edges: .top)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { vm.onBack?() }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left").font(.system(size: 12, weight: .medium))
                    Text("Back to Dayline").font(.system(size: 14))
                }
                .padding(.horizontal, 12).frame(height: 38).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
            ForEach(SettingsSection.allCases, id: \.self) { s in
                Button(action: { vm.section = s }) {
                    Text(s.rawValue).font(.system(size: 14))
                        .foregroundStyle(vm.section == s ? Theme.text : Theme.textMuted)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(vm.section == s ? Color.white.opacity(0.07) : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(vm.section == s ? .isSelected : [])
            }
            Spacer()
        }
        .padding(16)
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .background(Color.white.opacity(0.02))
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 1) }
    }
}

// MARK: - Categories & rules (screen 09)

private struct CategoriesPage: View {
    @ObservedObject var vm: SettingsViewModel
    @State private var adding = false
    @State private var showBuiltins = false
    @State private var newCategory: String?
    @State private var newColor = ActivityCategory.palette[6]
    @State private var renaming: Int64?
    @State private var renameText = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Categories & rules").font(.system(size: 30, weight: .light)).tracking(-0.3)
                    Text("Dayline guesses a category from the app and site. Your rules always win.")
                        .font(.system(size: 14)).foregroundStyle(Theme.textMuted)
                }
                categoriesSection
                if !vm.unsorted.isEmpty { unsortedSection }
                rulesSection
                neverTrackSection
            }
            .padding(.top, 16).padding(.horizontal, 40).padding(.bottom, 32).darkScroller()
            // A click on empty space ends naming; leaving the field saves it.
            .contentShape(Rectangle())
            .onTapGesture { editorFocused = false }
        }
    }

    /// Esc: drop the new or renamed name.
    private func cancelEditing() {
        renaming = nil
        newCategory = nil
    }

    // MARK: Categories

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CATEGORIES").eyebrow()
            FlowLayout(spacing: 8) {
                ForEach(vm.userCategories) { c in
                    if renaming == c.id {
                        chipEditor(text: $renameText, color: c.color) {
                            // Return and the focus loss that follows both land here.
                            guard renaming == c.id else { return }
                            renaming = nil
                            var updated = c
                            updated.name = renameText.trimmingCharacters(in: .whitespaces)
                            let taken = vm.categories.contains {
                                $0.id != c.id && $0.name.caseInsensitiveCompare(updated.name) == .orderedSame
                            }
                            if !updated.name.isEmpty && !taken && updated.name != c.name { vm.onUpdateCategory?(updated) }
                        }
                    } else {
                        chip(c)
                    }
                }
                if newCategory != nil {
                    // The field writes its text back after Return; once saved, that
                    // must not reopen the editor.
                    chipEditor(text: Binding(get: { newCategory ?? "" }, set: { if newCategory != nil { newCategory = $0 } }), color: newColor, colorPicker: true) {
                        // Read the state, not `name`: the text field keeps the closure
                        // from its first render, when the name was still empty.
                        guard let typed = newCategory else { return }
                        newCategory = nil
                        let n = typed.trimmingCharacters(in: .whitespaces)
                        let taken = vm.categories.contains { $0.name.caseInsensitiveCompare(n) == .orderedSame }
                        if !n.isEmpty && !taken { vm.onAddCategory?(n, newColor) }
                    }
                } else {
                    Button(action: { newCategory = "" }) {
                        Text("+ New category").font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                            .padding(.horizontal, 14).frame(height: 32)
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func chip(_ c: ActivityCategory) -> some View {
        // A click opens the menu too: right-click alone hid Delete.
        Menu {
            chipMenu(c)
        } label: {
            HStack(spacing: 8) {
                Circle().fill(Color(hexString: c.color)).frame(width: 8, height: 8)
                Text(c.name).font(.system(size: 13))
            }
            .padding(.horizontal, 14).frame(height: 32)
            .overlay(Capsule().strokeBorder(Theme.border))
            .contentShape(Capsule())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .contextMenu { chipMenu(c) }
        .help("Rename, recolor or delete")
        .accessibilityLabel("\(c.name) category")
    }

    @ViewBuilder private func chipMenu(_ c: ActivityCategory) -> some View {
        Button("Rename…") { renameText = c.name; renaming = c.id }
        Menu("Color") {
            ColorChoices(selected: c.color) { hex in var u = c; u.color = hex; vm.onUpdateCategory?(u) }
        }
        Divider()
        Button("Delete…") { vm.onDeleteCategory?(c) }
    }

    private func chipEditor(text: Binding<String>, color: String, colorPicker: Bool = false,
                            commit: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            if colorPicker {
                Menu {
                    ColorChoices(selected: newColor) { newColor = $0 }
                } label: {
                    Circle().fill(Color(hexString: color)).frame(width: 10, height: 10)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help("Color")
            } else {
                Circle().fill(Color(hexString: color)).frame(width: 8, height: 8)
            }
            TextField("Name", text: text)
                .onSubmit(commit)
                .textFieldStyle(.plain).font(.system(size: 13)).frame(width: 140)
                .focused($editorFocused)
                .onAppear { editorFocused = true }
                // The field editor eats Esc before onExitCommand, so catch the key itself.
                .onKeyPress(.escape) { cancelEditing(); return .handled }
                .onChange(of: editorFocused) { _, focused in if !focused { commit() } }
        }
        .padding(.horizontal, 14).frame(height: 32)
        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.45)))
    }

    // MARK: Needs a category

    /// Same card as Your rules; a pick adds a rule and the row moves down there.
    private var unsortedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NEEDS A CATEGORY · \(vm.unsorted.count)").eyebrow().frame(height: 32)
            VStack(spacing: 0) {
                ForEach(Array(vm.unsorted.enumerated()), id: \.element.id) { i, u in
                    unsortedRow(u).overlay(alignment: .top) {
                        Rectangle().fill(i == 0 ? .clear : Theme.border).frame(height: 1)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.02)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
        }
    }

    private func unsortedRow(_ u: Unsorted) -> some View {
        HStack(spacing: 14) {
            kindChip(u.kind).frame(width: 150, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(u.name).font(.system(size: 14)).lineLimit(1)
                Text([u.via, "\(u.blocks) block\(u.blocks == 1 ? "" : "s")"].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Durations.format(u.total)).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.textMuted)
                .lineLimit(1).fixedSize()
            CategoryPicker(categories: vm.userCategories, selected: nil, onNew: { newCategory = "" },
                           onNeverTrack: { vm.onAddExclusion?(u.kind, u.pattern, .skip) }) {
                vm.onSort?(u, $0.id)
            }
            .frame(width: 200)
            // Lines up with the rule rows' delete button.
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.leading, 20).padding(.trailing, 12).padding(.vertical, 10)
        .frame(minHeight: 56)
        .accessibilityElement(children: .contain)
    }

    // MARK: Never track

    private var neverTrackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(vm.exclusions.allSatisfy { $0.mode != .skip } ? "NEVER TRACK" : "NEVER TRACK · \(vm.exclusions.filter { $0.mode == .skip }.count)").eyebrow()
                Spacer()
                Text("Time in these is not recorded.").font(.system(size: 12)).foregroundStyle(Theme.textFaint)
            }
            .frame(height: 32)
            NeverTrackList(vm: vm)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.02)))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
        }
    }

    // MARK: Rules

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOUR RULES · \(vm.rules.count)").eyebrow()
                Spacer()
                Button(action: { adding = true }) {
                    Text("Add rule").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 14).frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(adding)
            }
            VStack(spacing: 0) {
                if adding {
                    AddRuleRow(vm: vm) { adding = false }
                }
                if vm.rules.isEmpty && !adding {
                    Text("No rules yet. Correct a block's category in the timeline and choose Always, or add one here.")
                        .font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 20).padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(vm.rules.enumerated()), id: \.element.id) { i, rule in
                    ruleRow(rule).overlay(alignment: .top) {
                        Rectangle().fill(i == 0 && !adding ? .clear : Theme.border).frame(height: 1)
                    }
                }
                footer.overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
                if showBuiltins { builtinList }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.02)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
        }
    }

    private func ruleRow(_ rule: Rule) -> some View {
        HStack(spacing: 14) {
            kindChip(rule.kind).frame(width: 150, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(vm.displayName(rule)).font(.system(size: 14)).lineLimit(1)
                Text("\(rule.origin == .correction ? "From your correction" : "Created by you") · \(shortDate(rule.createdAt))")
                    .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right").font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            CategoryPicker(categories: vm.categories, selected: vm.category(rule.categoryID)) {
                vm.onSetRuleCategory?(rule.id, $0.id)
            }
            .frame(width: 200)
            Button(action: { vm.onDeleteRule?(rule.id) }) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textMuted)
                    .frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete rule")
            .accessibilityLabel("Delete rule for \(vm.displayName(rule))")
        }
        .padding(.leading, 20).padding(.trailing, 12).padding(.vertical, 10)
        .frame(minHeight: 56)
    }

    private var footer: some View {
        HStack {
            Text("\(vm.builtins.count) built-in rules for common apps and sites sit below yours.")
                .font(.system(size: 13)).foregroundStyle(Theme.textMuted)
            Spacer()
            Button(showBuiltins ? "Hide built-in rules" : "Show built-in rules") { showBuiltins.toggle() }
                .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var builtinList: some View {
        LazyVStack(spacing: 0) {
            ForEach(vm.builtins, id: \.self) { b in
                HStack(spacing: 14) {
                    Text(b.kind.label).font(.system(size: 12)).foregroundStyle(Theme.textMuted).frame(width: 150, alignment: .leading)
                    Text(b.label).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        Circle().fill(Color(hexString: b.category.color)).frame(width: 8, height: 8)
                        Text(b.category.name).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(width: 246, alignment: .leading)
                }
                .padding(.horizontal, 20).frame(height: 32)
            }
        }
        .padding(.bottom, 8)
    }

    private func shortDate(_ t: Int64) -> String {
        Fmt.date(t).formatted(.dateTime.day().month(.abbreviated))
    }
}

func kindChip(_ kind: Rule.Kind) -> some View {
    Text(kind.label).font(.system(size: 12)).foregroundStyle(Theme.textMuted)
        .padding(.horizontal, 10).frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.06)))
        .fixedSize()
}

/// The select used in rule rows: dot, name, chevron.
struct CategoryPicker: View {
    var categories: [ActivityCategory]
    /// nil shows "Pick a category".
    var selected: ActivityCategory?
    /// Adds "New category…" at the bottom, which opens the + New category field.
    var onNew: (() -> Void)?
    /// Adds "Never track" under it: stop recording the app or site.
    var onNeverTrack: (() -> Void)?
    var onPick: (ActivityCategory) -> Void

    var body: some View {
        Menu {
            ForEach(categories) { c in Button(c.name) { onPick(c) } }
            if let onNew {
                Divider()
                Button("New category…", action: onNew)
            }
            if let onNeverTrack {
                Button("Never track", action: onNeverTrack)
            }
        } label: {
            HStack(spacing: 8) {
                if let selected {
                    Circle().fill(Color(hexString: selected.color)).frame(width: 8, height: 8)
                }
                Text(selected?.name ?? "Pick a category").font(.system(size: 13)).lineLimit(1)
                    .foregroundStyle(selected == nil ? Theme.textMuted : Theme.text)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textMuted)
            }
            .padding(.leading, 12).padding(.trailing, 14).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surfaceControl))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .accessibilityLabel(selected.map { "Category, \($0.name)" } ?? "Pick a category")
    }
}

/// Inline editor for a new rule: type, pattern, category.
private struct AddRuleRow: View {
    @ObservedObject var vm: SettingsViewModel
    var done: () -> Void
    @State private var kind = Rule.Kind.site
    @State private var pattern = ""
    @State private var appID: String?
    @State private var category: ActivityCategory?

    var body: some View {
        HStack(spacing: 14) {
            Menu {
                ForEach(Rule.Kind.allCases, id: \.self) { k in Button(k.label) { kind = k } }
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
            .frame(width: 150, alignment: .leading)
            Group {
                if kind == .app {
                    Menu {
                        ForEach(vm.recentApps, id: \.0) { app in Button(app.1) { appID = app.0 } }
                    } label: {
                        Text(appID.flatMap { vm.appNames[$0] } ?? "Choose an app")
                            .font(.system(size: 14)).foregroundStyle(appID == nil ? Theme.textMuted : Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                } else {
                    TextField(kind == .site ? "example.com" : "Text in the window title", text: $pattern, onCommit: add)
                        .textFieldStyle(.plain).font(.system(size: 14))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CategoryPicker(categories: vm.categories, selected: category ?? vm.categories.first ?? .uncategorized) { category = $0 }
                .frame(width: 200)
            Button(action: add) {
                Text("Add").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent.opacity(isValid ? 1 : 0.4)))
            }
            .buttonStyle(.plain).disabled(!isValid)
            Button(action: done) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textMuted)
                    .frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Cancel")
        }
        .padding(.leading, 20).padding(.trailing, 12).padding(.vertical, 10)
        .frame(minHeight: 56)
        .background(Theme.accent.opacity(0.04))
        .onExitCommand(perform: done)
    }

    /// "https://www.Example.com/path" -> "example.com"
    private var normalized: String {
        var p = pattern.trimmingCharacters(in: .whitespaces)
        guard kind == .site else { return p }
        p = p.lowercased()
        if let r = p.range(of: "://") { p = String(p[r.upperBound...]) }
        if let slash = p.firstIndex(of: "/") { p = String(p[..<slash]) }
        if p.hasPrefix("www.") { p.removeFirst(4) }
        return p
    }

    private var isValid: Bool { kind == .app ? appID != nil : !normalized.isEmpty }

    private func add() {
        guard isValid else { return }
        let c = category ?? vm.categories.first ?? .uncategorized
        vm.onAddRule?(kind, kind == .app ? appID! : normalized, c.id)
        done()
    }
}

/// Wraps chips onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += s.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

/// The category palette as menu items: a coloured dot and a plain name, the
/// current one checked. Menus draw SF Symbols in grey, so the dots are images.
private struct ColorChoices: View {
    let selected: String
    let pick: (String) -> Void

    static let names: [String: String] = [
        "#4EA7FC": "Blue", "#FC7840": "Orange", "#E8789E": "Pink", "#27A644": "Green",
        "#00B8CC": "Teal", "#F0BF00": "Yellow", "#9B7CFF": "Purple", "#5E6AD2": "Indigo",
        "#B4E04E": "Lime", "#FF5F5F": "Red", "#D9A066": "Tan", "#8A8F98": "Grey",
    ]

    var body: some View {
        ForEach(ActivityCategory.palette, id: \.self) { hex in
            Toggle(isOn: Binding(get: { hex.caseInsensitiveCompare(selected) == .orderedSame }, set: { _ in pick(hex) })) {
                Label { Text(Self.names[hex] ?? hex) } icon: { Image(nsImage: Self.dot(hex)) }
            }
        }
    }

    static func dot(_ hex: String) -> NSImage {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0x8A8F98
        let color = NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255,
                            blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

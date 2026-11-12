import Domain
import SwiftUI

public enum SettingsSection: String, CaseIterable, Sendable {
    case general = "General"
    case categories = "Categories & rules"
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

    public var onBack: (() -> Void)?
    public var onAddRule: ((Rule.Kind, String, Int64) -> Void)?
    public var onSetRuleCategory: ((Int64, Int64) -> Void)?
    public var onDeleteRule: ((Int64) -> Void)?
    public var onAddCategory: ((String, String) -> Void)?
    public var onUpdateCategory: ((ActivityCategory) -> Void)?
    public var onMergeCategory: ((ActivityCategory, ActivityCategory) -> Void)?
    /// The app confirms first; deleting moves the time to Uncategorized.
    public var onDeleteCategory: ((ActivityCategory) -> Void)?

    // General (screen 08)
    @Published public var startAtLogin = false
    @Published public var startAtLoginError: String?
    @Published public var showTotal = true
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
        public init(id: Int64, kind: Rule.Kind, label: String) {
            self.id = id
            self.kind = kind
            self.label = label
        }
    }
    @Published public var skipPrivate = true
    @Published public var exclusions: [Exclusion] = []
    /// nil = forever
    @Published public var retentionDays: Int?
    public var retentionChoices: [Int?] = [nil, 365, 90]
    /// "4.2 MB since 9 Nov"
    @Published public var storageText = ""
    public var onSetSkipPrivate: ((Bool) -> Void)?
    public var onAddExclusion: ((Rule.Kind, String) -> Void)?
    public var onDeleteExclusion: ((Int64) -> Void)?
    public var onSetRetention: ((Int?) -> Void)?
    public var onShowInFinder: (() -> Void)?
    public var onExport: ((ExportFormat) -> Void)?
    public var onDeleteAll: (() -> Void)?

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Categories & rules").font(.system(size: 30, weight: .light)).tracking(-0.3)
                    Text("Dayline guesses a category from the app and site. Your rules always win.")
                        .font(.system(size: 14)).foregroundStyle(Theme.textMuted)
                }
                categoriesSection
                rulesSection
            }
            .padding(.top, 16).padding(.horizontal, 40).padding(.bottom, 32)
        }
    }

    // MARK: Categories

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CATEGORIES").eyebrow()
            FlowLayout(spacing: 8) {
                ForEach(vm.userCategories) { c in
                    if renaming == c.id {
                        chipEditor(text: $renameText, color: c.color) {
                            var updated = c
                            updated.name = renameText.trimmingCharacters(in: .whitespaces)
                            if !updated.name.isEmpty { vm.onUpdateCategory?(updated) }
                            renaming = nil
                        }
                    } else {
                        chip(c)
                    }
                }
                if let name = newCategory {
                    chipEditor(text: Binding(get: { name }, set: { newCategory = $0 }), color: newColor, colorPicker: true) {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        if !n.isEmpty { vm.onAddCategory?(n, newColor) }
                        newCategory = nil
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
        HStack(spacing: 8) {
            Circle().fill(Color(hexString: c.color)).frame(width: 8, height: 8)
            Text(c.name).font(.system(size: 13))
        }
        .padding(.horizontal, 14).frame(height: 32)
        .overlay(Capsule().strokeBorder(Theme.border))
        .contentShape(Capsule())
        .contextMenu {
            Button("Rename…") { renameText = c.name; renaming = c.id }
            Menu("Color") {
                ForEach(ActivityCategory.palette, id: \.self) { hex in
                    Button(action: { var u = c; u.color = hex; vm.onUpdateCategory?(u) }) {
                        Label(hex, systemImage: hex == c.color ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
            }
            Menu("Merge into") {
                ForEach(vm.categories.filter { $0 != c }) { other in
                    Button(other.name) { vm.onMergeCategory?(c, other) }
                }
            }
            Divider()
            Button("Delete…") { vm.onDeleteCategory?(c) }
        }
        .help("Right-click to rename, recolor, merge or delete")
    }

    private func chipEditor(text: Binding<String>, color: String, colorPicker: Bool = false,
                            commit: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            if colorPicker {
                Menu {
                    ForEach(ActivityCategory.palette, id: \.self) { hex in
                        Button(hex) { newColor = hex }
                    }
                } label: {
                    Circle().fill(Color(hexString: color)).frame(width: 10, height: 10)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help("Color")
            } else {
                Circle().fill(Color(hexString: color)).frame(width: 8, height: 8)
            }
            TextField("Name", text: text, onCommit: commit)
                .textFieldStyle(.plain).font(.system(size: 13)).frame(width: 140)
                .onExitCommand { renaming = nil; newCategory = nil }
        }
        .padding(.horizontal, 14).frame(height: 32)
        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.45)))
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
    var selected: ActivityCategory
    var onPick: (ActivityCategory) -> Void

    var body: some View {
        Menu {
            ForEach(categories) { c in Button(c.name) { onPick(c) } }
        } label: {
            HStack(spacing: 8) {
                Circle().fill(Color(hexString: selected.color)).frame(width: 8, height: 8)
                Text(selected.name).font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textMuted)
            }
            .padding(.leading, 12).padding(.trailing, 14).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surfaceControl))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .accessibilityLabel("Category, \(selected.name)")
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

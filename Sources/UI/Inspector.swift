import Domain
import SwiftUI

/// Right column, 320 pt (spec 5.3, screens 01 and 02).
struct Inspector: View {
    @ObservedObject var vm: HomeViewModel
    /// The block whose "Delete" is waiting for a yes; another selection drops it.
    @State private var confirmingDelete: Int64?
    @State private var deleteHover = false
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Group {
            if let b = vm.selectedBlock {
                selected(b)
            } else {
                empty
            }
        }
        .padding(.top, 16).padding(.horizontal, 24).padding(.bottom, 24)
        .frame(width: 320, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white.opacity(0.02))
        .overlay(alignment: .leading) { Rectangle().fill(Theme.border).frame(width: 1) }
    }

    // MARK: - Selected block

    /// "SELECTED BLOCK" with a quiet Delete; asking turns the row into the question.
    /// The block still being recorded has no Delete: it is not finished yet.
    @ViewBuilder
    private func header(_ b: Block) -> some View {
        if confirmingDelete == b.id {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Delete \(Fmt.longDuration(b.duration))?").font(.system(size: 13)).foregroundStyle(Theme.text)
                    Spacer()
                    Button("Cancel") { confirmingDelete = nil }
                        .buttonStyle(.plain).font(.system(size: 12))
                        .padding(.horizontal, 10).frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.railFill))
                        .keyboardShortcut(.cancelAction)
                    Button("Delete") { confirmingDelete = nil; vm.deleteBlock(b) }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.white)
                        .padding(.horizontal, 10).frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.danger))
                }
                Text("The time becomes a gap. This can't be undone.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            }
        } else {
            HStack {
                Text("SELECTED BLOCK").eyebrow()
                Spacer()
                if !b.isOpen {
                    Button("Delete") { confirmingDelete = b.id }
                        .buttonStyle(.plain).font(.system(size: 12))
                        .foregroundStyle(deleteHover ? Theme.danger : Theme.textFaint)
                        .onHover { deleteHover = $0 }
                        .accessibilityHint("Asks before deleting this block's time")
                }
            }
        }
    }

    private func selected(_ b: Block) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 2) {
                header(b)
                Text(Fmt.range(b.start, b.end, open: b.isOpen))
                    .font(.system(size: 26, weight: .light).monospacedDigit())
                    .padding(.top, 6)
                Text(Fmt.longDuration(b.duration)).font(.system(size: 13)).foregroundStyle(Theme.textMuted)
            }
            if let call = b.call {
                VStack(alignment: .leading, spacing: 16) {
                    field("Call", call.name)
                    proof(call, in: b)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    field("App", b.appName)
                    // "App: Claude, Window title: Claude" says nothing twice.
                    if let title = b.title, title != b.appName {
                        field(b.host == nil ? "Window title" : "Tab title", title)
                    }
                    if let host = b.host { field("Site", host) }
                }
            }
            categorySelect(b)
            // Nothing about projects shows until one exists.
            if !vm.projects.isEmpty { projectSelect(b) }
            if let c = vm.pendingProjectRule, c.blockID == b.id { projectPrompt(c) }
            NoteField(vm: vm, block: b)
            if let call = vm.splitCall(containing: b) { wholeCall(call) }
            if let c = vm.pendingCorrection, c.blockID == b.id {
                prompt(c)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selected block")
    }

    private func categorySelect(_ b: Block) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Category").font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            Menu {
                if b.call != nil {
                    Button("What I was doing") { vm.splitCall(b) }
                    Divider()
                }
                ForEach(vm.categories) { c in
                    Button {
                        vm.setCategory(b, c)
                    } label: {
                        if c == b.category { Label(c.name, systemImage: "checkmark") } else { Text(c.name) }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(Color(hexString: b.category.color)).frame(width: 8, height: 8)
                    Text(b.category.name).font(.system(size: 14))
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textMuted)
                }
                .padding(.leading, 12).padding(.trailing, 14)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surfaceControl))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel("Category, \(b.category.name)")
            if b.edited {
                Text("Changed from \(b.guess.name)").font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            }
        }
    }

    /// "Erste · Krediti", grouped by client, with No project first.
    private func projectSelect(_ b: Block) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Project").font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            Menu {
                Button { vm.setProject(b, nil) } label: {
                    if b.project == nil { Label("No project", systemImage: "checkmark") } else { Text("No project") }
                }
                ForEach(projectGroups, id: \.0) { client, projects in
                    Divider()
                    Section(client ?? "No client") {
                        ForEach(projects) { p in
                            Button { vm.setProject(b, p) } label: {
                                if p == b.project { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if let p = b.project {
                        (Text(p.clientName.map { "\($0) · " } ?? "").foregroundColor(Theme.textMuted) + Text(p.name))
                            .font(.system(size: 14)).lineLimit(1)
                    } else {
                        Text("No project").font(.system(size: 14)).foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textMuted)
                }
                .padding(.leading, 12).padding(.trailing, 14)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surfaceControl))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel("Project, \(b.project?.fullName ?? "none")")
            // Why it is there, so a wrong guess can be traced and fixed.
            if let rule = b.projectRule, let p = b.project, vm.pendingProjectRule?.blockID != b.id {
                HStack(spacing: 4) {
                    Text("Always goes to \(p.name) ·").foregroundStyle(Theme.textMuted)
                        .help("Auto-add: “\(rule.pattern)” goes to \(p.name)")
                    Button("Remove") { vm.stopProjectRule(rule) }
                        .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                        .help("Remove this auto-add. What it added goes back to no project.")
                }
                .font(.system(size: 12))
                .lineLimit(1)
                Button("See \(p.name)’s auto-adds") { vm.onShowProject?(p) }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    .padding(.top, -6)
            }
        }
    }

    /// Projects by client, in the order the store gives them (no client last).
    private var projectGroups: [(String?, [Project])] {
        var groups: [(String?, [Project])] = []
        for p in vm.projects {
            if let i = groups.firstIndex(where: { $0.0 == p.clientName }) { groups[i].1.append(p) } else { groups.append((p.clientName, [p])) }
        }
        return groups
    }

    private func projectPrompt(_ c: ProjectCorrection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Always put \(c.pattern) in \(c.project.name)?")
                .font(.system(size: 14, weight: .medium))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(c.kind == .site ? "Time on this site counts there in any day, past ones too."
                 : "Counts in any app, past days too.")
                .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            HStack(spacing: 8) {
                Button(action: vm.projectAlways) {
                    Text("Always").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button(action: { vm.pendingProjectRule = nil }) {
                    Text("Just this time").font(.system(size: 14))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.accent.opacity(0.35)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent.opacity(0.35)))
    }

    /// The point of a call block: what you got done while on it, by category
    /// ("Design 3m"), with the files and tabs under each. The call window
    /// itself is left out; the call is the whole block.
    private func proof(_ call: CallDetail, in b: Block) -> some View {
        let work = call.totals.filter { $0.category != b.category }
        var order: [ActivityCategory] = []
        for p in work where !order.contains(p.category) { order.append(p.category) }
        let span = CGFloat(max(1, b.duration))
        return VStack(alignment: .leading, spacing: 10) {
            Text("Work during the call").font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            if order.isEmpty {
                Text("Only the call: nothing else was on screen.").font(.system(size: 14)).foregroundStyle(Theme.textMuted)
            } else {
                // The whole call, with the work in its colors; the rest stays dim.
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(order, id: \.self) { c in
                            Rectangle().fill(Color(hexString: c.color))
                                .frame(width: geo.size.width * CGFloat(minutes(work, c)) / span)
                        }
                        Spacer(minLength: 0)
                    }
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                .frame(height: 4)
                .accessibilityHidden(true)
                ForEach(order, id: \.self) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Circle().fill(Color(hexString: c.color)).frame(width: 8, height: 8)
                            Text(c.name)
                            Spacer()
                            Text(Durations.format(minutes(work, c))).monospacedDigit()
                        }
                        .font(.system(size: 14))
                        let items = work.filter { $0.category == c }
                        ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, p in
                            HStack(spacing: 8) {
                                // "Amazon.de · amazon.de" says it twice.
                                let source = p.source.flatMap { $0.lowercased() == p.label.lowercased() ? nil : $0 }
                                Text(source.map { "\(p.label) · \($0)" } ?? p.label).lineLimit(1).truncationMode(.tail)
                                Spacer()
                                // One item has the category's minutes already.
                                if items.count > 1 { Text(Durations.format(p.duration)).monospacedDigit() }
                            }
                            .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                            .padding(.leading, 16)
                        }
                    }
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Remove from this call", role: .destructive) { removeFromCall(b, c) }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAction(named: "Remove from this call") { removeFromCall(b, c) }
                }
            }
        }
    }

    /// The row goes; its time stays the call's. ⌘Z brings it back.
    private func removeFromCall(_ b: Block, _ c: ActivityCategory) {
        let ids = vm.countAsCall(b, c)
        guard !ids.isEmpty else { return }
        undoManager?.registerUndo(withTarget: vm) { $0.unpinSegments(ids) }
        undoManager?.setActionName("Remove from Call")
    }

    private func minutes(_ parts: [CallDetail.Part], _ c: ActivityCategory) -> Int64 {
        parts.filter { $0.category == c }.reduce(0) { $0 + $1.duration }
    }

    /// A block from a call you split: one click puts the whole call back.
    private func wholeCall(_ call: DayReport.Call) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("On a call: \(call.title), \(Fmt.range(call.start, call.end))")
                .font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button { vm.wholeCall(call) } label: {
                Text("Count the whole call as Meetings").font(.system(size: 13))
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surfaceControl))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func prompt(_ c: Correction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Always categorize \(c.subject) as \(c.category.name)?")
                .font(.system(size: 14, weight: .medium))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            // Equal halves; Just this time takes the card's own lime border.
            HStack(spacing: 8) {
                Button(action: vm.always) {
                    Text("Always").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button(action: { vm.pendingCorrection = nil }) {
                    Text("Just this time").font(.system(size: 14))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.accent.opacity(0.35)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            // Three buttons do not fit the inspector; Cancel is a plain text button.
            Button(action: vm.cancelCorrection) {
                Text("Cancel").font(.system(size: 13)).foregroundStyle(Theme.text)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .help("Put the block back in \(c.previous.name)")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent.opacity(0.35)))
    }

    private func field(_ label: String, _ value: String, dot: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            HStack(spacing: 8) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(value).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Nothing selected

    /// In the week and month views the panel sums those instead of the day.
    private var week: WeekReport? { vm.period == .day ? nil : vm.week }
    private var topApps: [DayReport.AppTotal] { week?.topApps ?? vm.report.topApps }
    private var longestFocus: DayReport.Focus? { week.map { $0.longestFocus } ?? vm.report.longestFocus }
    private var topAppsTitle: String {
        if let week { return week.containsToday ? (week.isMonth ? "TOP APPS THIS MONTH" : "TOP APPS THIS WEEK") : "TOP APPS" }
        return vm.report.isToday ? "TOP APPS TODAY" : "TOP APPS"
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 28) {
            if !topApps.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text(topAppsTitle).eyebrow()
                    let apps = Array(topApps.prefix(4))
                    let maxTotal = Double(apps.first?.total ?? 1)
                    ForEach(apps, id: \.appName) { app in
                        VStack(spacing: 6) {
                            HStack {
                                Text(app.appName)
                                Spacer()
                                Text(Durations.format(app.total)).monospacedDigit().foregroundStyle(Theme.textMuted).lineLimit(1).fixedSize()
                            }
                            .font(.system(size: 14))
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.06))
                                    RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.30))
                                        .frame(width: geo.size.width * Double(app.total) / maxTotal)
                                }
                            }
                            .frame(height: 3)
                            .accessibilityHidden(true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("LONGEST FOCUS").eyebrow()
                if let f = longestFocus {
                    // Same headline style as the selected block's time range.
                    Text(Durations.format(f.duration)).font(.system(size: 26, weight: .light).monospacedDigit()).padding(.top, 6)
                    // A week needs the day too: "in Xcode · Thu 10:19 – 14:39".
                    let day = week == nil ? "" : Fmt.date(f.start).formatted(.dateTime.weekday(.abbreviated)) + " "
                    Text("in \(f.appName) · \(day)\(Fmt.range(f.start, f.end))").font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                    if let t = f.title {
                        Text(t).font(.system(size: 13)).foregroundStyle(Theme.textMuted).lineLimit(1).truncationMode(.tail)
                    }
                } else {
                    Text("Not enough yet").font(.system(size: 26, weight: .light)).padding(.top, 6)
                    Text("Stretches of 25 minutes or more in one app show up here. Calls don’t count.")
                        .font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            // A first-run hint, so it sits at the bottom rather than above the data.
            Text(week == nil ? "Click a block to inspect it or fix its category." : "Click a day to open it.")
                .font(.system(size: 12)).foregroundStyle(Theme.textFaint).lineSpacing(2)
        }
    }
}

/// "Note": a line on what you did, saved when you press Return, leave the
/// field or pick another block.
private struct NoteField: View {
    @ObservedObject var vm: HomeViewModel
    var block: Block
    @State private var text = ""
    /// The block the text belongs to, so a switch saves to the right one.
    @State private var editing: Block?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Note").font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            TextField("What did you work on?", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, 12).padding(.vertical, 11)
                .frame(minHeight: 40)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surfaceControl))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(focused ? Theme.textFaint : Theme.border))
                .onSubmit { save(); focused = false }
                .onExitCommand { text = editing?.note ?? ""; focused = false }
                .accessibilityLabel("Note")
        }
        .onAppear { load(block) }
        .onChange(of: block.id) { save(); load(block) }
        .onChange(of: focused) { if !focused { save() } }
        .onDisappear { save() }
    }

    private func load(_ b: Block) {
        editing = b
        text = b.note ?? ""
    }

    private func save() {
        guard let b = editing else { return }
        let new = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard new != (b.note ?? "") else { return }
        editing?.note = new.isEmpty ? nil : new
        vm.setNote(b, new)
    }
}

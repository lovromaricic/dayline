import Domain
import SwiftUI

/// "Blocks · N today" with search and category filter (spec 5.3).
struct BlocksList: View {
    @ObservedObject var vm: HomeViewModel
    var searchFocus: FocusState<Bool>.Binding

    /// The scroll target for a block's row in the list.
    static func rowID(_ id: Int64) -> String { "row-\(id)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Text(title).eyebrow()
                if !vm.isSearchingAllDays, vm.isFiltering, let total = filteredTotal {
                    // The time those blocks add up to, brighter than the eyebrow.
                    (Text("· ").foregroundColor(Theme.textMuted) + Text(Durations.format(total)).foregroundColor(Theme.text))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .tracking(0.96)
                        .padding(.leading, -12)
                    // Time in this category during calls: shown, never added (it is the calls').
                    let onCalls = vm.filteredBlocks.reduce(0) { $0 + vm.callMinutes($1) }
                    if onCalls > 0 {
                        Text("+ \(Durations.format(onCalls)) ON CALLS")
                            .font(.system(size: 12, weight: .medium).monospacedDigit()).tracking(0.96)
                            .foregroundStyle(Theme.textMuted)
                            .padding(.leading, -8)
                    }
                }
                Spacer()
                TextField("Search", text: $vm.search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused(searchFocus)
                    .padding(.horizontal, 12)
                    .frame(width: 200, height: 32)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.railFill))
                    .accessibilityLabel("Search blocks by title, app, site or note")
                    .onExitCommand { vm.search = ""; searchFocus.wrappedValue = false }
                // Always there, so the search field doesn't jump when you type.
                scopeSwitch
                Menu {
                    Button("All categories") { vm.categoryFilter = nil }
                    Divider()
                    // The day's categories, or every category across all days.
                    ForEach(vm.searchAllDays ? vm.categories : vm.report.lanes.map(\.category), id: \.self) { c in
                        Button(c.name) { vm.categoryFilter = c }
                    }
                } label: {
                    Text(vm.categoryFilter?.name ?? "All categories")
                        .font(.system(size: 13))
                        .foregroundStyle(vm.categoryFilter == nil ? Theme.textMuted : Theme.text)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.railFill))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            if vm.isSearchingAllDays { allDays } else { dayRows }
        }
    }

    /// This day | All days, beside the search field.
    private var scopeSwitch: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { all in
                let on = vm.searchAllDays == all
                Button(action: { vm.searchAllDays = all }) {
                    Text(all ? "All days" : "This day").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(on ? Theme.text : Theme.textMuted)
                        .padding(.horizontal, 10).frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 5).fill(on ? Theme.surfaceControl : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.railFill))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search this day or all days")
    }

    // MARK: - All days

    private var allDays: some View {
        let days = vm.allDaysVisible
        return VStack(spacing: 0) {
            if vm.allDaysResults == nil {
                Text("Searching…").font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 12).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
            } else if days.isEmpty {
                Text(vm.allDaysOlder == nil ? "No blocks match on any day." : "No matches in this category so far.").font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 12).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
            }
            ForEach(days, id: \.dayStart) { day in
                HStack {
                    Text(day.isToday ? "TODAY · \(Fmt.dayEyebrow(day.dayStart))" : Fmt.dayEyebrow(day.dayStart)).eyebrow()
                    Spacer()
                    Text(Durations.format(day.total)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.textFaint)
                }
                .padding(.horizontal, 12).padding(.top, 18).padding(.bottom, 6)
                .accessibilityElement(children: .combine)
                ForEach(Array(day.blocks.enumerated()), id: \.element.id) { i, b in
                    BlockRow(block: b, selected: false, alsoIn: nil, alsoMinutes: 0, hideTopBorder: false)
                        .onTapGesture { vm.openResult(day, b) }
                        .accessibilityAction { vm.openResult(day, b) }
                        .accessibilityHint("Opens this day with the block selected")
                        .help("Open this day")
                }
            }
            // One month at a time; older months on request, skipping ones with no match.
            if let older = vm.allDaysOlder {
                Button(action: vm.showOlderMonth) {
                    Text("Show \(Fmt.date(older).formatted(Calendar.current.isDate(Fmt.date(older), equalTo: Date(), toGranularity: .year) ? .dateTime.month(.wide) : .dateTime.month(.wide).year()))")
                        .font(.system(size: 13)).foregroundStyle(Theme.text)
                        .padding(.horizontal, 12).frame(height: 32)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("Add the next older month with a match")
            }
        }
    }

    /// Right-click: move a block without opening the inspector.
    @ViewBuilder
    private func blockMenu(_ b: Block) -> some View {
        if !vm.projects.isEmpty {
            Menu("Move to project") {
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
            }
        }
        Menu("Change category") {
            ForEach(vm.categories) { c in
                Button { vm.setCategory(b, c) } label: {
                    if c == b.category { Label(c.name, systemImage: "checkmark") } else { Text(c.name) }
                }
            }
        }
    }

    private var projectGroups: [(String?, [Project])] {
        var groups: [(String?, [Project])] = []
        for p in vm.projects {
            if let i = groups.firstIndex(where: { $0.0 == p.clientName }) { groups[i].1.append(p) } else { groups.append((p.clientName, [p])) }
        }
        return groups
    }

    // MARK: - This day

    private var dayRows: some View {
            VStack(spacing: 0) {
                let rows = vm.visibleBlocks
                if rows.isEmpty {
                    Text(vm.isFiltering ? "No blocks match." : emptyText)
                        .font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 12).padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, b in
                    BlockRow(block: b, selected: vm.selection == b.id, alsoIn: vm.callMinutes(b) > 0 ? vm.categoryFilter : nil,
                             alsoMinutes: vm.callMinutes(b),
                             hideTopBorder: vm.selection == b.id || (i > 0 && vm.selection == rows[i - 1].id))
                        .onTapGesture { vm.select(vm.selection == b.id ? nil : b.id) }
                        .contextMenu { blockMenu(b) }
                        .accessibilityAction { vm.select(vm.selection == b.id ? nil : b.id) }
                        .accessibilityHint(vm.selection == b.id ? "Deselects the block" : "Shows the block in the inspector")
                        // Chart bars carry the block id too; the row's own id keeps
                        // scrollTo from jumping up to the chart.
                        .id(BlocksList.rowID(b.id))
                        // Where the selected row sits, so the window scrolls only if it is out of view.
                        .background {
                            if vm.selection == b.id {
                                GeometryReader { g in
                                    Color.clear.preference(key: SelectedRowFrame.self, value: g.frame(in: .named(SelectedRowFrame.space)))
                                }
                            }
                        }
                }
                if !vm.isFiltering, vm.filteredBlocks.count > HomeViewModel.collapsedCount {
                    Button(vm.showAllBlocks ? "Show fewer" : "Show all \(vm.filteredBlocks.count) blocks") {
                        vm.showAllBlocks.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
    }

    private var title: String {
        if vm.isSearchingAllDays, vm.allDaysResults != nil {
            let days = vm.allDaysVisible
            let n = days.reduce(0) { $0 + $1.blocks.count }
            let total = days.reduce(Int64(0)) { $0 + $1.total }
            guard n > 0 else { return vm.search.isEmpty ? "NO BLOCKS" : "NO MATCHES" }
            let noun = vm.search.isEmpty ? (n == 1 ? "BLOCK" : "BLOCKS") : (n == 1 ? "MATCH" : "MATCHES")
            let count = "\(n) \(noun) · \(Durations.format(total).uppercased()) IN \(days.count) \(days.count == 1 ? "DAY" : "DAYS")"
            return vm.categoryFilter.map { "\($0.name.uppercased()) · \(count)" } ?? count
        }
        if vm.isSearchingAllDays { return "ALL DAYS" }
        guard vm.isFiltering else {
            let n = vm.report.blocks.count
            return vm.report.isToday ? "BLOCKS · \(n) TODAY" : "BLOCKS · \(n)"
        }
        let n = vm.filteredBlocks.count
        let blocks = (vm.search.isEmpty ? "" : "MATCHING ") + (n == 1 ? "BLOCK" : "BLOCKS")
        let count = "\(n) \(blocks)"
        return vm.categoryFilter.map { "\($0.name.uppercased()) · \(count)" } ?? count
    }

    /// A category alone shows its lane total, as in the chart and popover;
    /// with a search it is the sum of the matching blocks.
    private var filteredTotal: Int64? {
        if vm.search.isEmpty, let c = vm.categoryFilter, let lane = vm.report.lanes.first(where: { $0.category == c }) {
            return lane.total
        }
        let blocks = vm.filteredBlocks.filter { vm.callMinutes($0) == 0 }
        return blocks.isEmpty ? nil : blocks.reduce(0) { $0 + $1.duration }
    }

    private var emptyText: String {
        vm.report.isToday ? "Blocks of a minute or more appear here as you work." : "No blocks this day."
    }
}

private struct BlockRow: View {
    var block: Block
    var selected: Bool
    /// A call listed under a category filter, with the time it holds of it.
    var alsoIn: ActivityCategory?
    var alsoMinutes: Int64
    var hideTopBorder: Bool

    /// A call says what you were in during it, each with its category's dot:
    /// "While in ● Novi kreditni accounti, ● amazon.de".
    private var subtitle: Text {
        guard let call = block.call else {
            return Text(block.appName) + Text(block.project.map { " · \($0.fullName)" } ?? "").foregroundColor(Theme.textSecondary)
        }
        let apps = call.totals.filter { $0.category != block.category }.prefix(2)
        guard !apps.isEmpty else { return Text("Call") }
        return apps.enumerated().reduce(Text("While in ")) { text, item in
            let (i, p) = item
            return text + Text(i == 0 ? "" : ", ")
                + Text("● ").font(.system(size: 8)).baselineOffset(1).foregroundColor(Color(hexString: p.category.color))
                + Text(p.label)
        }
    }

    /// "Meetings · 18m design" for a call under the Design filter.
    private var categoryText: Text {
        if let c = alsoIn {
            return Text("\(block.category.name) · ")
                + Text("\(Durations.format(alsoMinutes)) \(c.shortName.lowercased())").foregroundColor(Color(hexString: c.color))
        }
        return Text(block.edited ? "\(block.category.name) · edited" : block.category.name)
    }

    /// The selected row's details step up from muted, so the fill alone marks it.
    private var meta: Color { selected ? Theme.textSecondary : Theme.textMuted }

    var body: some View {
        HStack(spacing: 14) {
            Text(Fmt.range(block.start, block.end, open: block.isOpen))
                .font(.system(size: 13).monospacedDigit()).foregroundStyle(meta)
                .frame(width: 96, alignment: .leading)
            // The dot sits by the title, 8 pt away like everywhere else, on its line.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(Color(hexString: block.category.color)).frame(width: 8, height: 8)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4.5 }
                VStack(alignment: .leading, spacing: 0) {
                    Text(block.title ?? block.appName).font(.system(size: 14)).lineLimit(1).truncationMode(.tail)
                    subtitle.font(.system(size: 12)).foregroundStyle(Theme.textMuted).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            categoryText
                .font(.system(size: 13)).foregroundStyle(meta)
                .lineLimit(1).frame(width: 150, alignment: .leading)
            Text(Durations.format(block.duration)).font(.system(size: 13).monospacedDigit()).foregroundStyle(meta)
                .lineLimit(1).fixedSize()
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.white.opacity(0.09) : .clear))
        .overlay(alignment: .top) { Rectangle().fill(hideTopBorder ? .clear : Theme.border).frame(height: 1) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The selected row's frame in the home scroll view's viewport.
struct SelectedRowFrame: PreferenceKey {
    static let space = "homeScroll"
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
}

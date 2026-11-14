import Domain
import SwiftUI

/// The main window ("home", spec 5.3; screens 01 and 02).
public struct HomeView: View {
    @ObservedObject var vm: HomeViewModel
    @FocusState private var searchFocused: Bool
    @State private var pickingDay = false
    @State private var pickingDayInBar = false
    /// The big header has scrolled out of view: show the compact bar.
    @State private var headerGone = false
    @State private var selectedRow: CGRect?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// ImageRenderer cannot draw ScrollView content; snapshots turn it off.
    private let scrolls: Bool

    public init(viewModel: HomeViewModel, scrolls: Bool = true) {
        vm = viewModel
        self.scrolls = scrolls
    }

    private var r: DayReport { vm.report }

    public var body: some View {
        VStack(spacing: 0) {
            titleBar
            if vm.phase == .needsPermission || vm.phase == .waitingForPermission {
                OnboardingView(vm: vm)
            } else {
                home
            }
        }
        .frame(minWidth: 1000, minHeight: 640)
        .background(Theme.surfaceWindow)
        .foregroundStyle(Theme.text)
        .environment(\.colorScheme, .dark)
        // Our own 38 pt header sits in the title bar, beside the window buttons.
        .ignoresSafeArea(edges: .top)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { if vm.period == .day { vm.moveSelection(-1) }; return .handled }
        .onKeyPress(.downArrow) { if vm.period == .day { vm.moveSelection(1) }; return .handled }
        .onKeyPress(.leftArrow) { searchFocused ? .ignored : move(-1) }
        .onKeyPress(.rightArrow) { searchFocused ? .ignored : move(1) }
        .onKeyPress(.escape) {
            if vm.selection != nil { vm.select(nil); return .handled }
            return .ignored
        }
        .background {
            // ⌘F focuses the block search (spec 6).
            Button("") { searchFocused = true }.keyboardShortcut("f").hidden()
        }
    }

    private var home: some View {
            HStack(spacing: 0) {
                if scrolls {
                    GeometryReader { viewport in
                        ScrollViewReader { proxy in
                            ScrollView { content.darkScroller() }
                                .coordinateSpace(name: SelectedRowFrame.space)
                                .onPreferenceChange(SelectedRowFrame.self) { selectedRow = $0 }
                                .onPreferenceChange(HeaderBottom.self) { bottom in
                                    let gone = bottom < 0
                                    guard gone != headerGone else { return }
                                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { headerGone = gone }
                                }
                                .overlay(alignment: .top) {
                                    if headerGone { stickyBar.transition(.opacity) }
                                }
                                .onChange(of: vm.selection) { _, id in
                                    guard let id else { return }
                                    // After layout, so the row has reported where it is.
                                    DispatchQueue.main.async {
                                        reveal(id, proxy: proxy, height: viewport.size.height)
                                    }
                                }
                        }
                    }
                } else {
                    content.frame(maxHeight: .infinity, alignment: .top)
                }
                Inspector(vm: vm)
            }
    }

    /// Selecting a chart bar brings its row into view with a short scroll,
    /// centred, so you see where you went; a row already on screen stays put.
    private func reveal(_ id: Int64, proxy: ScrollViewProxy, height: CGFloat) {
        if let f = selectedRow, f.minY >= 0, f.maxY <= height { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            proxy.scrollTo(BlocksList.rowID(id), anchor: .center)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            // App state (paused, access lost or granted) sits above the day's summary.
            StatusBanner(vm: vm)
            summaryHeader
                .background {
                    GeometryReader { g in
                        Color.clear.preference(key: HeaderBottom.self, value: g.frame(in: .named(SelectedRowFrame.space)).maxY)
                    }
                }
            if vm.period == .week, let week = vm.week {
                WeekChart(vm: vm, week: week)
            } else {
                timeline
                if vm.unsortedCount > 0 { unsortedNote }
                // A little extra room so the list reads as its own section, not chart labels.
                BlocksList(vm: vm, searchFocus: $searchFocused)
                    .padding(.top, 12)
                if r.isToday && r.tracked > 0 && r.tracked < 30 * 60 && vm.phase == .tracking {
                    firstDayHint
                }
            }
        }
        .padding(.top, 16).padding(.horizontal, 32).padding(.bottom, 24)
    }

    /// Apps and sites from the last week in Uncategorized; Sort opens
    /// Settings → Categories & rules, where each gets a category (spec 5.4).
    private var unsortedNote: some View {
        HStack(spacing: 10) {
            Circle().fill(Color(hexString: ActivityCategory.uncategorized.color)).frame(width: 8, height: 8)
            Text(vm.unsortedCount == 1 ? "1 app or site needs a category" : "\(vm.unsortedCount) apps and sites need a category")
                .foregroundStyle(Theme.textSecondary)
            + Text("  ·  \(Durations.format(vm.unsortedTotal)) this week").foregroundStyle(Theme.textFaint)
            Spacer()
            Button(action: { vm.onSortUnsorted?() }) {
                Text("Sort").font(.system(size: 13)).foregroundStyle(Theme.text)
                    .padding(.horizontal, 12).frame(height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open Categories & rules")
        }
        .font(.system(size: 13))
        .padding(.leading, 14).padding(.trailing, 10).frame(height: 46)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        .padding(.top, 8)
    }

    /// Screen 05: shown during the first half hour of a day.
    private var firstDayHint: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "info.circle").font(.system(size: 13)).accessibilityHidden(true)
            Text("Categories are guessed from the app and site. Click any block to correct one, and Dayline will offer to remember it.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 13)).foregroundStyle(Theme.textMuted)
        .padding(.horizontal, 12).padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func move(_ days: Int) -> KeyPress.Result {
        if days > 0 && atLatest { return .handled }
        vm.onMoveDay?(days)
        return .handled
    }

    // MARK: - Title bar (the system draws the window buttons)

    /// Clicks in the title bar go to the window, not to SwiftUI, so this
    /// holds only the label; Settings is in the popover and on ⌘,.
    private var titleBar: some View {
        Text("DAYLINE").font(.system(size: 12, weight: .medium)).tracking(1.44).foregroundStyle(Theme.textMuted)
            .frame(maxWidth: .infinity).frame(height: 38)
            // Opaque and on top, so scrolled blocks pass under it.
            .background(Theme.surfaceWindow)
            .zIndex(1)
    }

    // MARK: - Header

    /// One header for day and week: the same views with new values, so the
    /// big total rolls from the day's to the week's instead of swapping.
    private var summaryHeader: some View {
        if vm.period == .week, let w = vm.week {
            let (first, second) = w.headline()
            let days = "\(w.trackedDays) day\(w.trackedDays == 1 ? "" : "s")"
            let subtitle = w.trackedDays > 1 ? "\(days) · avg \(Durations.format(w.average))" : w.trackedDays == 1 ? days : "Tracked"
            return summary(first, second, total: w.tracked, subtitle: subtitle)
        }
        let (first, second) = r.headline(trackingNow: vm.phase == .tracking)
        return summary(first, second, total: r.tracked, subtitle: totalSubtitle)
    }

    /// The date line, the two-line headline and the big total; shared by day and week.
    /// Top-aligned, so the date line stays put whether the headline takes one
    /// line or two.
    private func summary(_ first: String, _ second: String, total: Int64, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                dayNavigation(picking: $pickingDay)
                // One sentence that wraps where it must; the second half is grey.
                (Text(first) + Text(" ") + Text(second).foregroundColor(Theme.textMuted))
                    .font(.system(size: 30, weight: .light))
                    .tracking(-0.3)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) {
                Text(Durations.format(total))
                    .contentTransition(.numericText(value: Double(total)))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: total)
                    .font(.system(size: 64, weight: .light).monospacedDigit())
                    .tracking(-1.92)
                    .lineLimit(1)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.textMuted)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var totalSubtitle: String {
        let tracked = r.isToday ? "Tracked today" : "Tracked"
        if r.awayTotal >= 60 { return "\(Fmt.minutes(r.awayTotal)) away from your Mac" }
        if r.isToday, let first = r.firstActivity, r.tracked < 30 * 60 { return "\(tracked) · since \(Fmt.clock(first))" }
        return tracked
    }

    /// Today, or the week that holds today: nothing later to move to.
    private var atLatest: Bool { vm.period == .week ? vm.week?.containsToday ?? true : r.isToday }

    /// Spec 5.3: the Day/Week switch, the date, and a quiet chevron pair;
    /// click the date for a picker.
    /// Two copies (header and sticky bar), each with its own date picker.
    private func dayNavigation(picking: Binding<Bool>) -> some View {
        let week = vm.period == .week
        return HStack(spacing: 6) {
            PeriodSwitch(vm: vm).padding(.trailing, 8)
            Button(action: { picking.wrappedValue = true }) {
                Text(week ? Fmt.weekEyebrow(vm.week?.weekStart ?? r.dayStart) : Fmt.dayEyebrow(r.dayStart)).eyebrow()
            }
            .buttonStyle(.plain)
            .help(week ? "Pick a week" : "Pick a day")
            .popover(isPresented: picking, arrowEdge: .bottom) {
                DatePicker("", selection: Binding(
                    get: { Fmt.date(r.dayStart) },
                    set: { vm.onPickDay?($0); picking.wrappedValue = false }),
                    in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(12)
            }
            chevron("chevron.left", label: week ? "Previous week" : "Previous day", enabled: true) { vm.onMoveDay?(-1) }
            chevron("chevron.right", label: week ? "Next week" : "Next day", enabled: !atLatest) { vm.onMoveDay?(1) }
        }
    }

    /// Once the header scrolls away: the same date line and the total, small.
    private var stickyBar: some View {
        let total = vm.period == .week ? vm.week?.tracked ?? 0 : r.tracked
        return HStack(spacing: 0) {
            dayNavigation(picking: $pickingDayInBar)
            Spacer(minLength: 16)
            Text(Durations.format(total))
                .contentTransition(.numericText(value: Double(total)))
                .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: total)
                .font(.system(size: 20, weight: .light).monospacedDigit())
                .tracking(-0.4)
                .accessibilityLabel("Total \(Durations.format(total))")
        }
        .padding(.horizontal, 32)
        .frame(height: 48)
        .background(Theme.surfaceWindow)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func chevron(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Theme.textMuted : Theme.textFaint.opacity(0.5))
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: - Timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 16) {
            // The view switch is the section heading: eyebrow-style tabs.
            HStack(spacing: 20) {
                ForEach(TimelineMode.allCases, id: \.self) { mode in
                    let on = vm.mode == mode
                    // Bars glide between their lanes and the single strip.
                    Button(mode.rawValue.uppercased()) {
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.4)) { vm.mode = mode }
                    }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .tracking(0.96)
                        .foregroundStyle(on ? Theme.text : Theme.textMuted)
                        .frame(height: 26)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(on ? Theme.text : .clear).frame(height: 1.5)
                        }
                        .contentShape(Rectangle())
                        .accessibilityLabel(mode.rawValue)
                        .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            TimelineChart(vm: vm)
        }
    }
}

/// Day | Week, at the start of the date line.
private struct PeriodSwitch: View {
    @ObservedObject var vm: HomeViewModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Period.allCases, id: \.self) { p in
                let on = vm.period == p
                Button(action: { vm.setPeriod(p) }) {
                    Text(p.rawValue).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(on ? Theme.text : Theme.textMuted)
                        .padding(.horizontal, 10).frame(height: 24)
                        .background(on ? Theme.surfaceControl : .clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show a day or a week")
    }
}

/// Where the big header ends, in the scroll view's space; below 0 it is gone.
private struct HeaderBottom: PreferenceKey {
    static let defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = min(value, nextValue()) }
}

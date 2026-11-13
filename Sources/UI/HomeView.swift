import Domain
import SwiftUI

/// The main window ("home", spec 5.3; screens 01 and 02).
public struct HomeView: View {
    @ObservedObject var vm: HomeViewModel
    @FocusState private var searchFocused: Bool
    @State private var pickingDay = false
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
                    ScrollViewReader { proxy in
                        ScrollView { content.darkScroller() }
                            .onChange(of: vm.selection) { _, id in
                                if let id { withAnimation(nil) { proxy.scrollTo(BlocksList.rowID(id)) } }
                            }
                    }
                } else {
                    content.frame(maxHeight: .infinity, alignment: .top)
                }
                Inspector(vm: vm)
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            // App state (paused, access lost or granted) sits above the day's summary.
            StatusBanner(vm: vm)
            if vm.period == .week, let week = vm.week {
                weekHeader(week)
                WeekChart(vm: vm, week: week)
            } else {
                header
                timeline
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

    private var header: some View {
        let (first, second) = r.headline(trackingNow: vm.phase == .tracking)
        return summary(first, second, total: r.tracked, subtitle: totalSubtitle)
    }

    private func weekHeader(_ w: WeekReport) -> some View {
        let (first, second) = w.headline()
        let days = "\(w.trackedDays) day\(w.trackedDays == 1 ? "" : "s")"
        let subtitle = w.trackedDays > 1 ? "\(days) · avg \(Durations.format(w.average))" : w.trackedDays == 1 ? days : "Tracked"
        return summary(first, second, total: w.tracked, subtitle: subtitle)
    }

    /// The date line, the two-line headline and the big total; shared by day and week.
    private func summary(_ first: String, _ second: String, total: Int64, subtitle: String) -> some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                dayNavigation
                (Text(first) + Text("\n") + Text(second).foregroundColor(Theme.textMuted))
                    .font(.system(size: 30, weight: .light))
                    .tracking(-0.3)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) {
                Text(Durations.format(total))
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
    private var dayNavigation: some View {
        let week = vm.period == .week
        return HStack(spacing: 6) {
            PeriodSwitch(vm: vm).padding(.trailing, 8)
            Button(action: { pickingDay = true }) {
                Text(week ? Fmt.weekEyebrow(vm.week?.weekStart ?? r.dayStart) : Fmt.dayEyebrow(r.dayStart)).eyebrow()
            }
            .buttonStyle(.plain)
            .help(week ? "Pick a week" : "Pick a day")
            .popover(isPresented: $pickingDay, arrowEdge: .bottom) {
                DatePicker("", selection: Binding(
                    get: { Fmt.date(r.dayStart) },
                    set: { vm.onPickDay?($0); pickingDay = false }),
                    in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(12)
            }
            chevron("chevron.left", label: week ? "Previous week" : "Previous day", enabled: true) { vm.onMoveDay?(-1) }
            chevron("chevron.right", label: week ? "Next week" : "Next day", enabled: !atLatest) { vm.onMoveDay?(1) }
        }
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
                    Button(mode.rawValue.uppercased()) { vm.mode = mode }
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

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
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { vm.moveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { vm.moveSelection(1); return .handled }
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
                        ScrollView { content }
                            .onChange(of: vm.selection) { _, id in
                                if let id { withAnimation(nil) { proxy.scrollTo(id) } }
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
            header
            StatusBanner(vm: vm)
            timeline
            BlocksList(vm: vm, searchFocus: $searchFocused)
            if r.isToday && r.tracked > 0 && r.tracked < 30 * 60 && vm.phase == .tracking {
                firstDayHint
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
        if days > 0 && r.isToday { return .handled }
        vm.onMoveDay?(days)
        return .handled
    }

    // MARK: - Title bar (the system draws the window buttons)

    private var titleBar: some View {
        ZStack {
            Text("DAYLINE").font(.system(size: 12, weight: .medium)).tracking(1.44).foregroundStyle(Theme.textMuted)
            HStack {
                Spacer()
                Button(action: { vm.onOpenSettings?() }) {
                    SlidersGlyph().scaleEffect(0.9).frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings (⌘,)")
                .accessibilityLabel("Settings")
            }
            .padding(.trailing, 14)
        }
        .frame(height: 48)
    }

    // MARK: - Header

    private var header: some View {
        let (first, second) = r.headline(trackingNow: vm.phase == .tracking)
        return HStack(alignment: .bottom, spacing: 24) {
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
                Text(Durations.format(r.tracked))
                    .font(.system(size: 64, weight: .light).monospacedDigit())
                    .tracking(-1.92)
                    .lineLimit(1)
                Text(totalSubtitle).font(.system(size: 13)).foregroundStyle(Theme.textMuted)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var totalSubtitle: String {
        if r.awayTotal >= 60 { return "tracked · \(Fmt.minutes(r.awayTotal)) away" }
        if r.isToday, let first = r.firstActivity, r.tracked < 30 * 60 { return "tracked · since \(Fmt.clock(first))" }
        return r.isToday ? "tracked today" : "tracked"
    }

    /// Spec 5.3: a quiet chevron pair next to the date; click the date for a picker.
    private var dayNavigation: some View {
        HStack(spacing: 6) {
            Button(action: { pickingDay = true }) {
                Text(Fmt.dayEyebrow(r.dayStart)).eyebrow()
            }
            .buttonStyle(.plain)
            .help("Pick a day")
            .popover(isPresented: $pickingDay, arrowEdge: .bottom) {
                DatePicker("", selection: Binding(
                    get: { Fmt.date(r.dayStart) },
                    set: { vm.onPickDay?($0); pickingDay = false }),
                    in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(12)
            }
            chevron("chevron.left", label: "Previous day", enabled: true) { vm.onMoveDay?(-1) }
            chevron("chevron.right", label: "Next day", enabled: !r.isToday) { vm.onMoveDay?(1) }
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
            HStack {
                Text("WHEN YOU DID WHAT").eyebrow()
                Spacer()
                HStack(spacing: 20) {
                    ForEach(TimelineMode.allCases, id: \.self) { mode in
                        let on = vm.mode == mode
                        Button(mode.rawValue) { vm.mode = mode }
                            .buttonStyle(.plain)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(on ? Theme.text : Theme.textMuted)
                            .frame(height: 26)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(on ? Theme.text : .clear).frame(height: 1.5)
                            }
                            .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            TimelineChart(vm: vm)
        }
    }
}

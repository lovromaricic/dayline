import Domain
import SwiftUI

public final class PopoverViewModel: ObservableObject {
    @Published public var model: PopoverModel
    /// Bumped each time the popover opens, to replay the opening animation.
    @Published public var opened = 0

    public init(model: PopoverModel) {
        self.model = model
    }
}

/// The menu bar popover, 320 pt wide (spec 5.2, screens 01, 03–07).
public struct PopoverView: View {
    @ObservedObject var viewModel: PopoverViewModel
    let actions: PopoverActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Opening: the content grows from 96% at the top edge (the panel fades in
    /// with it), then the category bar fills in from the left.
    @State private var shown = true
    @State private var barFill: CGFloat = 1

    public init(viewModel: PopoverViewModel, actions: PopoverActions) {
        self.viewModel = viewModel
        self.actions = actions
    }

    private var m: PopoverModel { viewModel.model }
    private var hasData: Bool { !m.summary.rails.isEmpty }
    private var isPaused: Bool { if case .paused = m.phase { true } else { false } }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // The total sits close under the status line; 16 pt between groups.
            VStack(alignment: .leading, spacing: 2) {
                header
                total
            }
            card
            if hasData && m.phase != .needsPermission && m.phase != .waitingForPermission {
                VStack(alignment: .leading, spacing: 12) {
                    CategorySplitBar(rails: m.summary.rails)
                        .opacity(isPaused ? 0.4 : 1)
                        .mask(alignment: .leading) {
                            GeometryReader { geo in Rectangle().frame(width: geo.size.width * barFill) }
                        }
                    topCategories
                }
            }
            buttons
        }
        .padding(20)
        .frame(width: 320, alignment: .leading)
        .background(Theme.surfacePopover)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
        .foregroundStyle(Theme.text)
        .environment(\.colorScheme, .dark)
        .scaleEffect(shown ? 1 : 0.96, anchor: .top)
        .onChange(of: viewModel.opened) { playOpening() }
    }

    private func playOpening() {
        guard !reduceMotion else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { shown = false; barFill = 0 }
        withAnimation(.smooth(duration: 0.18)) { shown = true }
        withAnimation(.smooth(duration: 0.4).delay(0.08)) { barFill = 1 }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            ZStack(alignment: .leading) {
                Text(statusText).eyebrow().id(statusText).transition(.swap)
            }
            Spacer()
            // Pause and Resume swap instantly; only the rest of the popover animates.
            Group {
                switch m.phase {
                case .tracking:
                    Button(action: { actions.pause(.untilResumed) }) {
                        headerButton("Pause") { PauseGlyph().frame(width: 14, height: 14) }
                    }
                    .buttonStyle(.plain)
                    .help("Pause tracking. Right-click for more options.")
                    .accessibilityLabel("Pause tracking")
                    .contextMenu { pauseMenu }
                    .transition(.identity)
                case .paused:
                    Button(action: actions.resume) {
                        headerButton("Resume") { PlayGlyph().frame(width: 12, height: 12) }
                    }
                    .buttonStyle(.plain)
                    .help("Resume tracking")
                    .accessibilityLabel("Resume tracking")
                    .contextMenu { pauseMenu }
                    .transition(.identity)
                default:
                    EmptyView()
                }
            }
            .transaction { $0.animation = nil }
            settingsButton
        }
        .frame(minHeight: 36)
    }

    /// Pause and Resume share one look: icon and label in a bordered button.
    private func headerButton(_ label: String, @ViewBuilder icon: () -> some View) -> some View {
        HStack(spacing: 8) {
            icon()
            Text(label).font(.system(size: 13, weight: .medium))
        }
        .padding(.leading, 12).padding(.trailing, 14)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        .contentShape(Rectangle())
    }

    @ViewBuilder private var pauseMenu: some View {
        ForEach(PauseLength.allCases, id: \.self) { length in
            Button("Pause \(length.title.prefix(1).lowercased() + length.title.dropFirst())") { actions.pause(length) }
        }
    }

    private var statusText: String {
        switch m.phase {
        case .needsPermission: "NOT TRACKING YET"
        case .waitingForPermission: "WAITING FOR PERMISSION"
        case .tracking: "TRACKING"
        case .paused: "PAUSED"
        case .permissionLost: "TRACKING STOPPED"
        }
    }

    // MARK: - Total

    private var total: some View {
        let muted = m.phase == .needsPermission || m.phase == .waitingForPermission
        // The number gets a fixed 56 pt slot (its line height minus descender
        // room the digits never use), so "Tracked today" sits at the same
        // place whatever the number is doing, rolling digits included.
        return VStack(alignment: .leading, spacing: 0) {
            Text(Durations.format(m.summary.tracked))
                .contentTransition(.numericText(value: Double(m.summary.tracked)))
                .font(.system(size: 52, weight: .light).monospacedDigit())
                .tracking(-1.56)
                .foregroundStyle(muted ? Color(hex: 0xF4F3F7, opacity: 0.32) : Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: 56, alignment: .top)
            caption.font(.system(size: 13)).foregroundStyle(Theme.textMuted)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Tracked today", plus a note in the ring's colour on a long day.
    private var caption: Text {
        let note: (String, Color)? = switch m.summary.length {
        case .normal: nil
        case .long: ("a long day", Theme.long)
        case .veryLong: ("over 10 hours", Theme.veryLong)
        }
        guard let note, m.phase == .tracking || isPaused else { return Text("Tracked today") }
        return Text("Tracked today · ") + Text(note.0).foregroundColor(note.1)
    }

    // MARK: - Card

    private var card: some View {
        let c = cardContent
        // Overlaid so the old and new content swap in place.
        return ZStack(alignment: .topLeading) {
            cardBody(c).id(c.eyebrow + "|" + c.title + "|" + (c.dot?.description ?? ""))
                .transition(.swap)
        }
        .padding(14)
        // Top-aligned: when the text needs another line the card grows downward.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
        .accessibilityElement(children: .combine)
    }

    private func cardBody(_ c: (eyebrow: String, title: String, detail: String, dot: Color?)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(c.eyebrow).eyebrow()
            Text(c.title).font(.system(size: 14, weight: .medium)).lineLimit(1).truncationMode(.tail)
            if let dot = c.dot {
                HStack(spacing: 8) {
                    Circle().fill(dot).frame(width: 8, height: 8)
                    Text(c.detail).lineLimit(1).contentTransition(.numericText())
                }
                .font(.system(size: 13)).foregroundStyle(Theme.textMuted)
            } else {
                Text(c.detail).font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var cardContent: (eyebrow: String, title: String, detail: String, dot: Color?) {
        switch m.phase {
        case .needsPermission:
            return ("ONE STEP LEFT", "Accessibility access",
                    "Needed to see which app and tab you're in. Turn Dayline on under Privacy & Security, then tracking starts by itself.", nil)
        case .waitingForPermission:
            return ("WAITING", "Looking for Dayline in Accessibility",
                    "Turn the switch on and this updates by itself. No need to restart.", nil)
        case .permissionLost:
            return ("ONE STEP LEFT", "Accessibility access was turned off",
                    "Switch Dayline back on under Privacy & Security. Tracking restarts by itself.", nil)
        case .paused(let since, let until):
            let detail: String
            if let until {
                let sameDay = Calendar.current.isDate(date(until), inSameDayAs: date(m.now))
                detail = sameDay ? "Dayline resumes by itself at \(clock(until))." : "Dayline resumes by itself tomorrow."
            } else {
                detail = "Resume when you're ready."
            }
            return ("PAUSED SINCE \(clock(since))", "Nothing is being recorded", detail, nil)
        case .tracking:
            if let cur = m.summary.current {
                // The app name once: a title that is just the app is not repeated below it.
                let app = cur.title == cur.appName ? "" : "\(cur.appName) · "
                return ("NOW", cur.title, "\(app)\(cur.category.name) · \(minutesText(m.now - cur.since))",
                        Color(hexString: cur.category.color))
            }
            switch m.nowStatus {
            case .away(let since):
                return ("AWAY", "Away since \(clock(since))", "Time counts again when you're back.", nil)
            case .hidden:
                return ("NOW", "Nothing is being recorded", "Private windows and excluded apps are skipped.", nil)
            case .none:
                return ("NOW", "Starting up", "Your current app appears here in a moment.", nil)
            }
        }
    }

    /// "for 12m", "for 1h 05m"; "just started" in the first minute.
    private func minutesText(_ seconds: Int64) -> String {
        seconds < 60 ? "just started" : "for \(Durations.format(seconds))"
    }

    // MARK: - Top categories

    private var topCategories: some View {
        VStack(spacing: 10) {
            ForEach(m.summary.rails.prefix(3), id: \.category) { rail in
                HStack {
                    HStack(spacing: 8) {
                        Circle().fill(Color(hexString: rail.category.color)).frame(width: 8, height: 8)
                        // A step below the Now card, so the total and now lead.
                        Text(rail.category.name).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Text(Durations.format(rail.total)).monospacedDigit().foregroundStyle(Theme.textMuted).lineLimit(1).fixedSize()
                        .contentTransition(.numericText(value: Double(rail.total)))
                }
                .font(.system(size: 14))
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Buttons

    /// Lime only while a permission step is the thing to do; Open timeline is
    /// quiet like Pause, so the total leads.
    private var buttons: some View {
        let loud = !m.phase.canPause
        return Button(action: primaryAction) {
            Text(primaryTitle)
                .font(.system(size: 14, weight: loud ? .semibold : .medium))
                .foregroundStyle(loud ? Theme.onAccent : Theme.text)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(loud ? Theme.accent : Theme.cardFill))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(loud ? .clear : Theme.border))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
    }

    private var settingsButton: some View {
        Button(action: actions.openSettings) {
            SlidersGlyph()
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.cardFill))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Settings")
        .accessibilityLabel("Settings")
    }

    private var primaryTitle: String {
        switch m.phase {
        case .needsPermission, .permissionLost: "Open System Settings"
        case .waitingForPermission: "Open System Settings again"
        case .tracking, .paused: "Open timeline"
        }
    }

    private func primaryAction() {
        switch m.phase {
        case .needsPermission, .waitingForPermission, .permissionLost: actions.openSystemSettings()
        case .tracking, .paused: actions.openTimeline()
        }
    }

    // MARK: - Formatting

    private func date(_ t: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(t)) }

    private func clock(_ t: Int64) -> String { Fmt.clock(t) }
}

extension AnyTransition {
    /// Text that changes: the old fades out quickly, then the new fades in
    /// and settles 3 pt, so two lines never sit on top of each other.
    static var swap: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: 3)).animation(.smooth(duration: 0.22).delay(0.1)),
                    removal: .opacity.animation(.easeOut(duration: 0.1)))
    }
}

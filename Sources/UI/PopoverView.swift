import Domain
import SwiftUI

public final class PopoverViewModel: ObservableObject {
    @Published public var model: PopoverModel

    public init(model: PopoverModel) {
        self.model = model
    }
}

/// The menu bar popover, 320 pt wide (spec 5.2, screens 01, 03–07).
public struct PopoverView: View {
    @ObservedObject var viewModel: PopoverViewModel
    let actions: PopoverActions

    public init(viewModel: PopoverViewModel, actions: PopoverActions) {
        self.viewModel = viewModel
        self.actions = actions
    }

    private var m: PopoverModel { viewModel.model }
    private var hasData: Bool { !m.summary.rails.isEmpty }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            total
            card
            if hasData && m.phase != .needsPermission && m.phase != .waitingForPermission {
                DayBarcode(summary: m.summary, nowLine: m.phase == .tracking ? m.now : nil)
                topCategories
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
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Circle().fill(statusDot).frame(width: 7, height: 7)
                Text(statusText).eyebrow()
            }
            .accessibilityElement(children: .combine)
            Spacer()
            switch m.phase {
            case .tracking:
                Button(action: { actions.pause(.untilResumed) }) {
                    PauseGlyph().frame(width: 16, height: 16)
                        .frame(width: 44, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Pause tracking. Right-click for more options.")
                .accessibilityLabel("Pause tracking")
                .contextMenu { pauseMenu }
            case .paused:
                Button(action: actions.resume) {
                    HStack(spacing: 8) {
                        PlayGlyph().frame(width: 14, height: 14)
                        Text("Resume").font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.leading, 14).padding(.trailing, 16)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.10)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent.opacity(0.45)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Resume tracking")
                .contextMenu { pauseMenu }
            default:
                EmptyView()
            }
        }
        .frame(minHeight: 44)
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

    private var statusDot: Color {
        switch m.phase {
        case .tracking: Theme.ok
        case .permissionLost: Theme.danger
        default: Color.white.opacity(0.3)
        }
    }

    // MARK: - Total

    private var total: some View {
        let muted = m.phase == .needsPermission || m.phase == .waitingForPermission
        return VStack(alignment: .leading, spacing: 4) {
            Text(Durations.format(m.summary.tracked))
                .font(.system(size: 64, weight: .light).monospacedDigit())
                .tracking(-1.92)
                .foregroundStyle(muted ? Color(hex: 0xF4F3F7, opacity: 0.32) : Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("tracked today").font(.system(size: 13)).foregroundStyle(Theme.textMuted)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Card

    private var card: some View {
        let c = cardContent
        return VStack(alignment: .leading, spacing: 4) {
            Text(c.eyebrow).eyebrow()
            Text(c.title).font(.system(size: 14, weight: .medium)).lineLimit(1).truncationMode(.tail)
            if let dot = c.dot {
                HStack(spacing: 8) {
                    Circle().fill(dot).frame(width: 8, height: 8)
                    Text(c.detail).lineLimit(1)
                }
                .font(.system(size: 13)).foregroundStyle(Theme.textMuted)
            } else {
                Text(c.detail).font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
        .accessibilityElement(children: .combine)
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
                return ("NOW", cur.title, "\(cur.appName) · \(cur.category.name) · \(minutesText(m.now - cur.since))",
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

    /// "8 min", "1h 05m".
    private func minutesText(_ seconds: Int64) -> String {
        seconds >= 3600 ? Durations.format(seconds) : "\(max(0, seconds) / 60) min"
    }

    // MARK: - Top categories

    private var topCategories: some View {
        VStack(spacing: 10) {
            ForEach(m.summary.rails.prefix(3), id: \.category) { rail in
                HStack {
                    HStack(spacing: 8) {
                        Circle().fill(Color(hexString: rail.category.color)).frame(width: 8, height: 8)
                        Text(rail.category.name)
                    }
                    Spacer()
                    Text(Durations.format(rail.total)).monospacedDigit().foregroundStyle(Theme.textMuted)
                }
                .font(.system(size: 14))
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Buttons

    private var buttons: some View {
        HStack(spacing: 8) {
            Button(action: primaryAction) {
                Text(primaryTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            Button(action: actions.openSettings) {
                SlidersGlyph()
                    .frame(width: 48, height: 48)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
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

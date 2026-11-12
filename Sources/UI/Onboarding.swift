import Domain
import SwiftUI

/// First launch and waiting for permission (spec 5, screens 03 and 04).
struct OnboardingView: View {
    @ObservedObject var vm: HomeViewModel

    private var waiting: Bool { vm.phase == .waitingForPermission }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                header
                VStack(alignment: .leading, spacing: 14) {
                    Text("SET UP").eyebrow()
                    VStack(spacing: 12) {
                        accessibilityStep
                        step(2, "Start at login", optional: true, "So tracking is always on without you thinking about it.") {
                            Toggle("", isOn: Binding(get: { vm.startAtLogin }, set: { vm.onSetStartAtLogin?($0) }))
                                .toggleStyle(LimeSwitch())
                                .accessibilityLabel("Start at login")
                        }
                        step(3, "Count me as away after", optional: true,
                             "No keyboard or mouse activity for this long pauses the clock.") {
                            Menu {
                                ForEach(vm.idleChoices, id: \.self) { m in
                                    Button("\(m) minute\(m == 1 ? "" : "s")") { vm.onSetIdleMinutes?(m) }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text("\(vm.idleMinutes) minute\(vm.idleMinutes == 1 ? "" : "s")").font(.system(size: 13))
                                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.textMuted)
                                }
                                .padding(.horizontal, 12).frame(height: 32)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.railFill))
                            }
                            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                            .accessibilityLabel("Count me as away after \(vm.idleMinutes) minutes")
                        }
                        if let error = vm.startAtLoginError {
                            Text("Start at login: \(error)").font(.system(size: 12)).foregroundStyle(Theme.danger)
                        }
                    }
                }
                ghostTimeline
                Spacer(minLength: 0)
            }
            .padding(.top, 16).padding(.horizontal, 32).padding(.bottom, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            privacyPanel
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("WELCOME TO DAYLINE").eyebrow()
                (Text(waiting ? "Almost there." : "Your days, tracked on their own.") + Text("\n")
                    + Text(waiting ? "Switch Dayline on, and tracking begins." : "One permission, then you’re set.")
                        .foregroundColor(Theme.textMuted))
                    .font(.system(size: 30, weight: .light)).tracking(-0.3).lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: -6) {
                Text("0m").font(.system(size: 64, weight: .light).monospacedDigit()).tracking(-1.92)
                    .foregroundStyle(Color(hex: 0xF4F3F7, opacity: 0.32))
                Text("Tracked today").font(.system(size: 13)).foregroundStyle(Theme.textMuted)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var accessibilityStep: some View {
        HStack(spacing: 16) {
            Text("1").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.onAccent)
                .frame(width: 28, height: 28).background(Circle().fill(Theme.accent))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(waiting ? "Switch Dayline on in System Settings" : "Allow Accessibility access").font(.system(size: 16))
                Text(waiting ? "Find Dayline under Privacy & Security → Accessibility. This screen updates by itself."
                     : "Lets Dayline read window titles, including Chrome tab titles. Nothing leaves your Mac.")
                    .font(.system(size: 13)).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if waiting {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).tint(Theme.accent)
                    Text("Waiting for permission").font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                }
                .help("Click to open System Settings again")
                .onTapGesture { vm.onOpenSystemSettings?() }
            } else {
                Button(action: { vm.onOpenSystemSettings?() }) {
                    Text("Open System Settings").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 16).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent.opacity(0.35)))
        .accessibilityElement(children: .contain)
    }

    private func step(_ n: Int, _ title: String, optional: Bool, _ detail: String,
                      @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 16) {
            Text("\(n)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textMuted)
                .frame(width: 28, height: 28).overlay(Circle().strokeBorder(Theme.border))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    Text(title).font(.system(size: 16))
                    if optional { Text("Optional").font(.system(size: 12)).tracking(0.48).foregroundStyle(Theme.textMuted) }
                }
                Text(detail).font(.system(size: 13)).foregroundStyle(Theme.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
    }

    private var ghostTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR DAY").eyebrow()
            VStack(spacing: 10) {
                VStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { _ in RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.045)).frame(height: 8) }
                }
                HStack {
                    ForEach(["8:00", "10:00", "12:00", "14:00", "16:00"], id: \.self) { t in
                        Text(t)
                        if t != "16:00" { Spacer() }
                    }
                }
                .font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .overlay {
                Text("Your day appears here once tracking starts").font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.surfaceWindow))
                    .overlay(Capsule().strokeBorder(Theme.border))
                    .offset(y: -8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your day appears here once tracking starts")
        }
    }

    private var privacyPanel: some View {
        VStack(alignment: .leading, spacing: 32) {
            list("WHAT DAYLINE SEES", ok: true, ["Which app you are in", "Window and Chrome tab titles", "When you are active or away"])
            list("WHAT IT NEVER SEES", ok: false, ["Screenshots or screen contents", "Keystrokes or clipboard", "Page contents"])
            Spacer(minLength: 0)
            Text("Everything is stored on this Mac. You can exclude any app or site in Settings.")
                .font(.system(size: 13)).foregroundStyle(Theme.textMuted).lineSpacing(2)
                .padding(.top, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        }
        .padding(.top, 16).padding(.horizontal, 24).padding(.bottom, 24)
        .frame(width: 320, alignment: .topLeading)
        .frame(maxHeight: .infinity)
        .background(Color.white.opacity(0.02))
        .overlay(alignment: .leading) { Rectangle().fill(Theme.border).frame(width: 1) }
    }

    private func list(_ title: String, ok: Bool, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).eyebrow()
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: ok ? "checkmark" : "xmark").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ok ? Theme.ok : Theme.textMuted)
                        .frame(width: 14)
                    Text(item).font(.system(size: 14))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// 44 × 26 switch: lime track, dark thumb (spec 8, ToggleSwitch).
struct LimeSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: { configuration.isOn.toggle() }) {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? Theme.accent : Theme.surfaceControl)
                    .overlay(Capsule().strokeBorder(configuration.isOn ? .clear : Theme.border))
                Circle().fill(configuration.isOn ? Theme.onAccent : Theme.textMuted).frame(width: 20, height: 20).padding(3)
            }
            .frame(width: 44, height: 26)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

/// Banners at the top of the timeline, above the day header (StatusBanner in spec 8): granted, paused, lost.
struct StatusBanner: View {
    @ObservedObject var vm: HomeViewModel

    var body: some View {
        switch vm.phase {
        case .paused(let since, let until):
            banner(icon: "pause.fill", iconColor: Theme.textMuted, border: Color.white.opacity(0.14), fill: Color.white.opacity(0.05),
                   text: pausedText(since: since, until: until)) {
                actionButton("Resume now") { vm.onResume?() }
            }
        case .permissionLost(let at):
            banner(icon: "exclamationmark.circle", iconColor: Theme.danger, border: Theme.danger.opacity(0.30), fill: Theme.danger.opacity(0.07),
                   text: "Dayline lost Accessibility access at \(Fmt.clock(at)). Tracking has stopped.") {
                actionButton("Open System Settings") { vm.onOpenSystemSettings?() }
            }
        case .tracking where vm.showGrantedBanner:
            banner(icon: "checkmark.circle", iconColor: Theme.ok, border: Theme.ok.opacity(0.28), fill: Theme.ok.opacity(0.07),
                   text: "Accessibility access granted. Dayline now tracks in the background, so you can close this window.") {
                Button(action: { vm.showGrantedBanner = false }) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textMuted)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        default:
            EmptyView()
        }
    }

    private func pausedText(since: Int64, until: Int64?) -> String {
        guard let until else { return "Paused at \(Fmt.clock(since)). Resume whenever you're ready." }
        let sameDay = Calendar.current.isDate(Fmt.date(until), inSameDayAs: Fmt.date(since))
        return sameDay ? "Paused at \(Fmt.clock(since)). Tracking resumes automatically at \(Fmt.clock(until))."
            : "Paused at \(Fmt.clock(since)). Tracking resumes automatically tomorrow."
    }

    private func banner(icon: String, iconColor: Color, border: Color, fill: Color, text: String,
                        @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(iconColor).accessibilityHidden(true)
            Text(text).font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 10)
        .frame(minHeight: 52)
        .background(RoundedRectangle(cornerRadius: 8).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(border))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 14).frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

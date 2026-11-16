import Domain
import SwiftUI

/// Right column, 320 pt (spec 5.3, screens 01 and 02).
struct Inspector: View {
    @ObservedObject var vm: HomeViewModel

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

    private func selected(_ b: Block) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SELECTED BLOCK").eyebrow()
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
                    .accessibilityElement(children: .combine)
                }
            }
        }
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

    /// In the week view the panel sums the week instead of the day.
    private var week: WeekReport? { vm.period == .week ? vm.week : nil }
    private var topApps: [DayReport.AppTotal] { week?.topApps ?? vm.report.topApps }
    private var longestFocus: DayReport.Focus? { week.map { $0.longestFocus } ?? vm.report.longestFocus }
    private var topAppsTitle: String {
        if let week { return week.containsToday ? "TOP APPS THIS WEEK" : "TOP APPS" }
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

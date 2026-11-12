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
            VStack(alignment: .leading, spacing: 14) {
                field("App", b.appName)
                if let title = b.title {
                    field(b.host == nil ? "Window title" : "Tab title", title)
                }
                if let host = b.host { field("Site", host) }
            }
            categorySelect(b)
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

    private func prompt(_ c: Correction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Always categorize \(c.subject) as \(c.category.name)?")
                .font(.system(size: 14, weight: .medium))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(action: vm.always) {
                    Text("Always").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 16).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button(action: { vm.pendingCorrection = nil }) {
                    Text("Just this block").font(.system(size: 14))
                        .padding(.horizontal, 16).frame(height: 40)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
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

    private func field(_ label: String, _ value: String, dot: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            HStack(spacing: 8) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(value).font(.system(size: 16)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Nothing selected

    private var empty: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Click a block to inspect it or fix its category.")
                .font(.system(size: 13)).foregroundStyle(Theme.textMuted).lineSpacing(2)
            if !vm.report.topApps.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text(vm.report.isToday ? "TOP APPS TODAY" : "TOP APPS").eyebrow()
                    let apps = Array(vm.report.topApps.prefix(4))
                    let maxTotal = Double(apps.first?.total ?? 1)
                    ForEach(apps, id: \.appName) { app in
                        VStack(spacing: 6) {
                            HStack {
                                Text(app.appName)
                                Spacer()
                                Text(Durations.format(app.total)).monospacedDigit().foregroundStyle(Theme.textMuted)
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
                if let f = vm.report.longestFocus {
                    Text("\(Durations.format(f.duration)) in \(f.appName)").font(.system(size: 22, weight: .light)).padding(.top, 4)
                    Text([Fmt.range(f.start, f.end), f.title].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13)).foregroundStyle(Theme.textMuted).lineLimit(2)
                } else {
                    Text("Not enough yet").font(.system(size: 22, weight: .light)).padding(.top, 4)
                    Text("Stretches of 25 minutes or more in one app show up here.")
                        .font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
    }
}

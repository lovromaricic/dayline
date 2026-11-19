import Domain
import SwiftUI

/// "When you did what" (spec 5.3): one 30 pt lane per category, or a single
/// strip in Timeline mode. Bars are blocks; click selects, click empty space
/// deselects. AWAY and NOT TRACKED regions are hatched across all lanes.
struct TimelineChart: View {
    @ObservedObject var vm: HomeViewModel

    private let labelWidth: CGFloat = 170
    private let totalWidth: CGFloat = 56
    private let laneHeight: CGFloat = 30

    private var r: DayReport { vm.report }

    /// A bar being dragged to another lane (spec 4: drag-to-correct).
    @State private var drag: (blockID: Int64, dy: CGFloat)?
    /// Bars grow in from the left, lane by lane, when a day loads.
    @State private var revealed = true
    /// A bar keeps its identity between its lane and the Timeline strip, so
    /// switching views glides it instead of swapping.
    @Namespace private var barSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Row: Identifiable {
        var id: String
        var label: String
        /// nil for the single Timeline strip, where dragging is off.
        var category: ActivityCategory?
        var color: Color?
        var total: Int64
        var blocks: [Block]
        /// A By project lane: clicking its name shows only that project.
        var project: Project?
        var faint = false
    }

    private var rows: [Row] {
        switch vm.mode {
        case .timeline:
            return [Row(id: "all", label: "All activity", category: nil, color: nil, total: r.tracked, blocks: r.blocks)]
        case .byCategory:
            let lanes = vm.showAllLanes ? r.lanes : Array(r.lanes.prefix(HomeViewModel.laneCap))
            return lanes.map { Row(id: $0.category.name, label: $0.category.name, category: $0.category,
                                   color: Color(hexString: $0.category.color), total: $0.total, blocks: $0.blocks) }
        case .byProject:
            return projectRows
        }
    }

    /// One lane per project, largest first, No project last. The lane names
    /// the project, so bars keep their category colours.
    private var projectRows: [Row] {
        var byID: [Int64: (Project, [Block])] = [:]
        var none: [Block] = []
        for b in r.blocks {
            if let p = b.project { byID[p.id, default: (p, [])].1.append(b) } else { none.append(b) }
        }
        let total = { (bs: [Block]) in bs.reduce(Int64(0)) { $0 + $1.duration } }
        var rows = byID.values.sorted { total($0.1) > total($1.1) }.map { p, bs in
            Row(id: "p\(p.id)", label: vm.scope == nil ? p.fullName : p.name, category: nil, color: nil,
                total: total(bs), blocks: bs, project: p)
        }
        if !none.isEmpty {
            rows.append(Row(id: "none", label: "No project", category: nil, color: nil, total: total(none), blocks: none, faint: true))
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Spacer().frame(width: labelWidth)
                GeometryReader { geo in regionLabels(width: geo.size.width) }.frame(height: 16)
                Spacer().frame(width: totalWidth)
            }
            if rows.isEmpty {
                emptyLane
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        if let c = row.color { Circle().fill(c).frame(width: 8, height: 8) }
                        Text(row.label).font(.system(size: 13)).lineLimit(1)
                            .foregroundStyle(row.faint ? Theme.textMuted : Theme.text)
                    }
                    .frame(width: labelWidth, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { if let p = row.project, vm.scope == nil { vm.setScope(.project(p)) } }
                    .help(row.project != nil && vm.scope == nil ? "Show only \(row.label)" : "")
                    GeometryReader { geo in lane(row, index: index, width: geo.size.width) }.frame(height: laneHeight)
                    Text(Durations.format(row.total))
                        .font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.textMuted)
                        .contentTransition(.numericText(value: Double(row.total)))
                        .animation(reduceMotion ? nil : .smooth, value: row.total)
                        .lineLimit(1).fixedSize()
                        .frame(width: totalWidth, alignment: .trailing)
                }
                .frame(height: laneHeight)
                .background(dropTarget == index ? Color.white.opacity(0.04) : .clear)
                .zIndex(row.blocks.contains { $0.id == drag?.blockID } ? 1 : 0)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.label) \(Durations.format(row.total)), \(row.blocks.count) block\(row.blocks.count == 1 ? "" : "s")")
                .accessibilityHint("Each block is also listed under Blocks, where you can select it")
            }
            if vm.mode == .byCategory, r.lanes.count > HomeViewModel.laneCap {
                Button(vm.showAllLanes ? "Show fewer" : "+\(r.lanes.count - HomeViewModel.laneCap) more") {
                    vm.showAllLanes.toggle()
                }
                .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                .frame(height: laneHeight)
            }
            HStack(spacing: 12) {
                Spacer().frame(width: labelWidth)
                GeometryReader { geo in axisLabels(width: geo.size.width) }.frame(height: 18)
                Spacer().frame(width: totalWidth)
            }
            .padding(.top, 6)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Today by category")
        .onAppear(perform: grow)
        .onChange(of: vm.replay) { grow() }
    }

    /// Only once the app has loaded something (`replay` > 0); a still render
    /// such as a snapshot shows the bars at rest.
    private func grow() {
        guard !reduceMotion, vm.replay > 0 else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { revealed = false }
        DispatchQueue.main.async { revealed = true }
    }

    // MARK: - Lanes

    /// The lane the dragged bar is over, if it is not its own.
    private var dropTarget: Int? {
        guard let d = drag, let from = rows.firstIndex(where: { $0.blocks.contains { $0.id == d.blockID } }) else { return nil }
        let to = from + Int((d.dy / laneHeight).rounded())
        return to != from && rows.indices.contains(to) ? to : nil
    }

    private func lane(_ row: Row, index: Int, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle()).onTapGesture { vm.select(nil) }
            ForEach(hours, id: \.self) { h in
                Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1).offset(x: x(h, width))
            }
            // Every break is drawn, so no gap is left unexplained: hatched where
            // there is room for stripes, a faint fill where they would be noise.
            ForEach(Array((r.away.map { ($0, "Away") } + r.untracked.map { ($0, "Not tracked") }).enumerated()),
                    id: \.offset) { _, item in
                let (region, label) = item
                let w = max(1, x(region.upperBound, width) - x(region.lowerBound, width))
                Group {
                    if w >= 10 {
                        Hatch(color: Color.white.opacity(0.05), stripe: 3, period: 7)
                    } else {
                        Rectangle().fill(Color.white.opacity(0.05))
                    }
                }
                .frame(width: w)
                .contentShape(Rectangle())
                .onTapGesture { vm.select(nil) }
                .help("\(label) · \(Fmt.minutes(region.upperBound - region.lowerBound)) · \(Fmt.range(region.lowerBound, region.upperBound, open: false))")
                .offset(x: x(region.lowerBound, width))
            }
            ZStack(alignment: .topLeading) {
                ForEach(row.blocks) { b in bar(b, row: row, width: width) }
            }
            .frame(width: width, height: laneHeight, alignment: .topLeading)
            // Tall, so a bar dragged to another lane is not cut off.
            .mask(alignment: .leading) {
                Rectangle().frame(width: revealed ? width : 0, height: 2000)
                    .animation(.smooth(duration: 0.45).delay(Double(index) * 0.04), value: revealed)
            }
            if r.isToday {
                Rectangle().fill(Theme.accent.opacity(0.9)).frame(width: 2)
                    .offset(x: x(r.now, width) - 1)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: laneHeight, alignment: .topLeading)
    }

    private func bar(_ b: Block, row: Row, width: CGFloat) -> some View {
        let selected = vm.selection == b.id
        return RoundedRectangle(cornerRadius: 5)
            .fill(Color(hexString: b.category.color))
            .overlay(alignment: .bottom) { if let call = b.call { proof(call, in: b) } }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.text, lineWidth: selected ? 1.5 : 0))
            .frame(width: max(3, x(b.end, width) - x(b.start, width) - 3), height: 22)
            .matchedGeometryEffect(id: b.id, in: barSpace)
            .offset(x: x(b.start, width), y: 4 + (drag?.blockID == b.id ? drag!.dy : 0))
            .shadow(color: .black.opacity(drag?.blockID == b.id ? 0.5 : 0), radius: 6, y: 2)
            .onTapGesture { vm.select(selected ? nil : b.id) }
            .gesture(row.category == nil ? nil : DragGesture(minimumDistance: 4)
                .onChanged { drag = (b.id, $0.translation.height) }
                .onEnded { _ in
                    if let to = dropTarget, let c = rows[to].category { vm.setCategory(b, c) }
                    drag = nil
                })
            .help(help(b))
    }

    private func help(_ b: Block) -> String {
        let base = "\(b.title ?? b.appName) · \(Fmt.range(b.start, b.end, open: b.isOpen))"
        guard let call = b.call else { return base }
        return base + "\nOn screen: " + call.totals.map { "\($0.label) \(Durations.format($0.duration))" }.joined(separator: ", ")
    }

    /// A call's proof: a strip along the bottom of its bar, in the colors of
    /// what was in front. The call window itself is a darker shade of the bar.
    private func proof(_ call: CallDetail, in b: Block) -> some View {
        GeometryReader { geo in
            let span = CGFloat(max(1, b.end - b.start))
            ZStack(alignment: .topLeading) {
                ForEach(Array(call.parts.enumerated()), id: \.offset) { _, p in
                    Rectangle()
                        .fill(p.category == b.category ? Color.black.opacity(0.22) : Color(hexString: p.category.color))
                        .frame(width: max(1, geo.size.width * CGFloat(p.end - p.start) / span))
                        .offset(x: geo.size.width * CGFloat(p.start - b.start) / span)
                }
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    private var emptyLane: some View {
        HStack(spacing: 12) {
            Spacer().frame(width: labelWidth)
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    ForEach(hours, id: \.self) { h in
                        Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1).offset(x: x(h, geo.size.width))
                    }
                    Text(r.isToday ? "Your day appears here once you start working" : "Nothing was tracked this day")
                        .font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: laneHeight * 2)
            Spacer().frame(width: totalWidth)
        }
    }

    // MARK: - Labels and axis

    private struct RegionLabel: Identifiable {
        var id: String
        var text: String
        var center: CGFloat
        var color: Color
        var weight: Font.Weight
    }

    /// NOW always shows; AWAY and NOT TRACKED only where the region is wide
    /// enough for the word and the word does not collide with NOW.
    private func placedLabels(width: CGFloat) -> [RegionLabel] {
        // 12 pt with 0.1em tracking is about 8.5 pt per character.
        func half(_ text: String) -> CGFloat { CGFloat(text.count) * 4.25 + 4 }
        var labels: [RegionLabel] = []
        if r.isToday {
            labels.append(RegionLabel(id: "now", text: "NOW", center: x(r.now, width), color: Theme.accent, weight: .medium))
        }
        let regions = r.away.map { ("AWAY", $0) } + r.untracked.map { ("NOT TRACKED", $0) }
        for (i, (text, region)) in regions.enumerated() {
            let lo = x(region.lowerBound, width), hi = x(region.upperBound, width)
            let center = (lo + hi) / 2
            guard hi - lo >= 2 * half(text),
                  !labels.contains(where: { abs($0.center - center) < half($0.text) + half(text) + 6 }) else { continue }
            labels.append(RegionLabel(id: "\(text)\(i)", text: text, center: center, color: Theme.textMuted, weight: .regular))
        }
        return labels
    }

    private func regionLabels(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(placedLabels(width: width)) { l in
                Text(l.text).font(.system(size: 12, weight: l.weight)).tracking(1.2).foregroundStyle(l.color)
                    .fixedSize()
                    .frame(width: 120)
                    .offset(x: l.center - 60)
            }
        }
        .frame(width: width, height: 16, alignment: .topLeading)
    }

    private func axisLabels(width: CGFloat) -> some View {
        let step = hourStep(width: width)
        return ZStack(alignment: .topLeading) {
            ForEach(hours.dropLast(), id: \.self) { h in
                if ((h - r.axis.lowerBound) / 3600) % Int64(step) == 0 {
                    Text(hourText(h)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.textMuted)
                        .fixedSize()
                        .offset(x: x(h, width) + 5)
                }
            }
        }
        .frame(width: width, height: 18, alignment: .topLeading)
    }

    /// Label every hour while there is room, else every 2 or 3 hours.
    private func hourStep(width: CGFloat) -> Int {
        let perHour = width / CGFloat(max(1, (r.axis.upperBound - r.axis.lowerBound) / 3600))
        return perHour >= 44 ? 1 : perHour >= 22 ? 2 : 3
    }

    private var hours: [Int64] { Array(stride(from: r.axis.lowerBound, through: r.axis.upperBound, by: 3600)) }

    private func hourText(_ t: Int64) -> String {
        let h = (t - r.dayStart) / 3600
        return "\(h):00"
    }

    private func x(_ t: Int64, _ width: CGFloat) -> CGFloat {
        let span = Double(r.axis.upperBound - r.axis.lowerBound)
        let f = Double(min(max(t, r.axis.lowerBound), r.axis.upperBound) - r.axis.lowerBound) / span
        return CGFloat(f) * width
    }
}

/// 135° stripes.
struct Hatch: View {
    var color: Color
    var stripe: CGFloat
    var period: CGFloat

    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += period * 1.414
            }
            ctx.stroke(p, with: .color(color), lineWidth: stripe)
        }
        .clipped()
    }
}

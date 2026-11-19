import AppKit
import Categorize
import Store
import Domain
import SwiftUI
import UI

// Renders the popover in every state with sample data, for comparing
// against the design screens. Usage: ui-snapshots [output-dir] [--today | --animate]

// --today renders your real day from the Dayline database (stays in build/, git-ignored).
let realDay = CommandLine.arguments.contains("--today")
let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first { !$0.hasPrefix("--") } ?? "build/snapshots")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let cal = Calendar.current
let dayStart = Int64(cal.startOfDay(for: Date()).timeIntervalSince1970)
func at(_ h: Int, _ m: Int) -> Int64 { dayStart + Int64(h * 3600 + m * 60) }

// Unique ids: DayReport caches categories by segment id.
var segID: Int64 = 1000
func seg(_ s: Int64, _ e: Int64, _ app: String, _ title: String? = nil, _ kind: SegmentKind = .active, call: Bool = false) -> Segment {
    segID += 1
    return Segment(id: segID, start: s, end: e, kind: kind, appBundleID: app, appName: app, title: title, call: call)
}
let palette: [String: ActivityCategory] = ["Xcode": .development, "Figma": .design, "Zoom": .meetings,
                                           "Notion": .writing, "Slack": .communication, "Chrome": .browsing]
let day = [
    seg(at(8, 35), at(9, 0), "Slack", "#general"),
    seg(at(9, 5), at(10, 35), "Figma", "Onboarding"),
    seg(at(10, 35), at(11, 0), "Chrome", "Swift Concurrency — Apple Developer"),
    seg(at(11, 0), at(11, 30), "Figma", "Onboarding"),
    seg(at(11, 30), at(12, 10), "Zoom", "Standup", call: true),
    seg(at(12, 10), at(12, 50), "Xcode", nil, .away),
    seg(at(12, 50), at(15, 0), "Xcode", "CaptureService.swift — Dayline"),
    seg(at(15, 0), at(15, 35), "Notion", "Spec"),
    seg(at(15, 35), at(16, 10), "Xcode", "Pull request #42 · GitHub"),
]
let now = at(16, 10)
func summary(_ segs: [Segment], now: Int64) -> DaySummary {
    DaySummary(segments: segs, dayStart: dayStart, now: now) { palette[$0.appName] ?? .uncategorized }
}
let paused = Array(day.prefix(5)) + [seg(at(12, 10), at(12, 40), "", nil, .untracked)]
let noop = PopoverActions(pause: { _ in }, resume: {}, openTimeline: {}, openSettings: {}, openSystemSettings: {})

let states: [(String, PopoverModel)] = [
    ("01-tracking", PopoverModel(phase: .tracking, summary: summary(day, now: now), nowStatus: .none, now: now)),
    ("03-needs-permission", PopoverModel(phase: .needsPermission, summary: summary([], now: now), nowStatus: .none, now: now)),
    ("04-waiting", PopoverModel(phase: .waitingForPermission, summary: summary([], now: now), nowStatus: .none, now: now)),
    ("05-first-minutes", PopoverModel(phase: .tracking, summary: summary([seg(at(9, 0), at(9, 12), "Chrome", "Docs"),
        seg(at(9, 12), at(9, 20), "Xcode", "CaptureService.swift — Dayline")], now: at(9, 20)), nowStatus: .none, now: at(9, 20))),
    ("06-paused", PopoverModel(phase: .paused(since: at(12, 10), until: at(13, 10)), summary: summary(paused, now: at(12, 40)), nowStatus: .none, now: at(12, 40))),
    ("07-permission-lost", PopoverModel(phase: .permissionLost(at: at(12, 10)), summary: summary(paused, now: at(12, 40)), nowStatus: .none, now: at(12, 40))),
    ("tracking-away", PopoverModel(phase: .tracking, summary: summary(Array(day.prefix(6)), now: at(12, 40)), nowStatus: .away(since: at(12, 10)), now: at(12, 40))),
    ("tracking-private", PopoverModel(phase: .tracking, summary: summary(Array(day.prefix(5)), now: at(12, 20)), nowStatus: .hidden, now: at(12, 20))),
]

// --animate: frames of the popover's transitions while it is open (pause,
// a minute ticking over, switching apps), to judge the motion.
if CommandLine.arguments.contains("--animate") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let t0 = at(16, 10)
    let base = PopoverModel(phase: .tracking, summary: summary(day, now: t0), nowStatus: .none, now: t0)
    let longer = day.dropLast() + [seg(at(15, 35), at(16, 11), "Xcode", "Pull request #42 · GitHub")]
    let ticked = PopoverModel(phase: .tracking, summary: summary(Array(longer), now: t0 + 60), nowStatus: .none, now: t0 + 60)
    let switched = PopoverModel(phase: .tracking, summary: summary(Array(longer) + [seg(at(16, 11), at(16, 11) + 5, "Slack", "#design")],
                                                                     now: t0 + 65), nowStatus: .none, now: t0 + 65)
    let pausedNow = PopoverModel(phase: .paused(since: t0 + 70, until: nil), summary: summary(Array(longer), now: t0 + 70),
                                 nowStatus: .none, now: t0 + 70)
    let vm = PopoverViewModel(model: base)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 640), styleMask: .borderless, backing: .buffered, defer: false)
    // Hosted like the app's PopoverPanel: a twin measures, the window keeps its
    // top edge, and the visible content is pinned top-left.
    let measure = NSHostingView(rootView: PopoverView(viewModel: vm, actions: noop))
    measure.sizingOptions = [.intrinsicContentSize]
    let host = NSHostingView(rootView: GeometryReader { _ in PopoverView(viewModel: vm, actions: noop) })
    host.sizingOptions = []
    window.contentView = host
    window.setContentSize(measure.fittingSize)
    window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
    func refit() {
        let size = measure.fittingSize
        window.setFrame(NSRect(x: window.frame.minX, y: window.frame.maxY - size.height, width: size.width, height: size.height), display: true)
    }
    window.orderFrontRegardless()
    // Away has a two-line card, so pausing from it changes the popover's height.
    let away = PopoverModel(phase: .tracking, summary: summary(Array(longer), now: t0 + 80), nowStatus: .away(since: t0), now: t0 + 80)
    // Starting up has a two-line card, so the card has to grow.
    let starting = PopoverModel(phase: .tracking, summary: summary(Array(day.prefix(5)), now: t0 + 90), nowStatus: .none, now: t0 + 90)
    let steps: [(String, PopoverModel)] = [("tick", ticked), ("switch", switched), ("pause", pausedNow), ("resume", ticked),
                                           ("away", away), ("pause2", pausedNow), ("grow", starting)]
    func grab(_ name: String) {
        let v = window.contentView!
        let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])!.write(to: out.appending(path: "anim-\(name).png"))
    }
    var t = 0.5
    for (name, model) in steps {
        DispatchQueue.main.asyncAfter(deadline: .now() + t) { withAnimation(.smooth(duration: 0.35)) { vm.model = model }
            DispatchQueue.main.async { refit() } }
        for ms in stride(from: 0, through: 500, by: 25) {
            DispatchQueue.main.asyncAfter(deadline: .now() + t + Double(ms) / 1000) { grab("\(name)-\(ms)") }
        }
        t += 1
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + t) { exit(0) }
    app.run()
}

// Main window, data shaped like screens 01/02.
var homeID: Int64 = 0
func hseg(_ s: Int64, _ e: Int64, _ app: String, _ title: String?, host: String? = nil, _ kind: SegmentKind = .active) -> Segment {
    homeID += 1
    return Segment(id: homeID, start: s, end: e, kind: kind, appBundleID: app, appName: app, title: title, host: host, domain: host)
}
let homeCats: [String: ActivityCategory] = ["Slack": .communication, "Figma": .design, "Zoom": .meetings, "Xcode": .development]
func homeCategory(_ s: Segment) -> ActivityCategory {
    if let h = s.host { return h.contains("docs") ? .writing : h.contains("github") || h.contains("apple") ? .development : .browsing }
    return homeCats[s.appName] ?? .uncategorized
}
let homeDay = [
    hseg(at(8, 35), at(9, 5), "Slack", "#design-feedback — Slack"),
    hseg(at(9, 5), at(10, 35), "Figma", "Onboarding – Figma"),
    hseg(at(10, 35), at(10, 50), "Chrome", "Swift Concurrency — Apple Developer", host: "news.ycombinator.com"),
    hseg(at(10, 50), at(11, 20), "Figma", "Onboarding – Figma"),
    hseg(at(11, 20), at(12, 0), "Zoom", "Standup"),
    hseg(at(12, 0), at(12, 50), "", nil, .away),
    hseg(at(12, 50), at(14, 40), "Xcode", "CaptureService.swift — Dayline"),
    hseg(at(14, 40), at(15, 0), "Chrome", "NSWorkspace | Apple Developer Documentation", host: "developer.apple.com"),
    hseg(at(15, 0), at(15, 35), "Chrome", "Product notes – Google Docs", host: "docs.google.com"),
    hseg(at(15, 35), at(16, 10), "Chrome", "Pull request #42 · GitHub", host: "github.com"),
]
let homeReport = DayReport(segments: homeDay, dayStart: dayStart, now: now, category: homeCategory)
let firstReport = DayReport(segments: [hseg(at(9, 0), at(9, 12), "Chrome", "Apple Developer Documentation", host: "developer.apple.com"),
                                       hseg(at(9, 12), at(9, 20), "Xcode", "CaptureService.swift — Dayline")],
                            dayStart: dayStart, now: at(9, 20), category: homeCategory)
// Screen 01: the developer.apple.com block was corrected from Browsing to Development.
let correctedReport = DayReport(segments: homeDay, dayStart: dayStart, now: now) { seg in
    let c = homeCategory(seg)
    return seg.host == "developer.apple.com" ? CategoryResolution(category: c, guess: .browsing, edited: true)
        : CategoryResolution(category: c, guess: c, edited: false)
}
let selectedVM = HomeViewModel(report: correctedReport)
let corrected = correctedReport.blocks.first { $0.host == "developer.apple.com" }!
selectedVM.selection = corrected.id
selectedVM.pendingCorrection = Correction.subject(for: corrected, category: .development)
func vm(_ report: DayReport, _ phase: TrackingPhase, granted: Bool = false) -> HomeViewModel {
    let v = HomeViewModel(report: report)
    v.phase = phase
    v.showGrantedBanner = granted
    return v
}
let morning = DayReport(segments: Array(homeDay.prefix(5)) + [hseg(at(12, 0), at(12, 40), "", nil, .untracked)],
                        dayStart: dayStart, now: at(12, 40), category: homeCategory)
let empty = DayReport(segments: [], dayStart: dayStart, now: at(9, 0), category: homeCategory)
let filteredVM = HomeViewModel(report: homeReport)
filteredVM.categoryFilter = homeReport.lanes.first?.category
// Week view: the sample day repeated through the week, longer midweek.
let weekStart = Int64(cal.dateInterval(of: .weekOfYear, for: Date())!.start.timeIntervalSince1970)
let weekStarts = (0..<7).map { Int64(cal.startOfDay(for: cal.date(byAdding: .day, value: $0, to: Date(timeIntervalSince1970: TimeInterval(weekStart)))!).timeIntervalSince1970) }
let weekReports = weekStarts.enumerated().filter { $0.element <= dayStart }.map { i, start in
    let shift = start - dayStart
    var segs = homeDay.map { s -> Segment in
        var c = s; c.id += Int64(i) * 100; c.start += shift; c.end += shift; return c
    }
    // Wednesday and Thursday run into the evening.
    if i == 2 || i == 3 { segs.append(hseg(at(16, 10) + shift, at(16, 10) + shift + Int64(i) * 3600, "Zoom", "Planning")) }
    return DayReport(segments: segs, dayStart: start, now: start == dayStart ? now : start + 86_399, category: homeCategory)
}
let weekVM = HomeViewModel(report: homeReport)
weekVM.setPeriod(.week)
weekVM.week = WeekReport(weekStart: weekStarts[0], reports: weekReports, dayStarts: weekStarts, today: dayStart)
// Month view: the sample day on weekdays up to today, a varying length each day.
let monthStart = Int64(cal.dateInterval(of: .month, for: Date())!.start.timeIntervalSince1970)
let monthStarts = (0..<cal.range(of: .day, in: .month, for: Date())!.count).map {
    Int64(cal.startOfDay(for: cal.date(byAdding: .day, value: $0, to: Date(timeIntervalSince1970: TimeInterval(monthStart)))!).timeIntervalSince1970)
}
let monthReports = monthStarts.enumerated().filter { $0.element <= dayStart }.compactMap { i, start -> DayReport? in
    let weekday = cal.component(.weekday, from: Date(timeIntervalSince1970: TimeInterval(start)))
    if weekday == 1 || weekday == 7 { return nil }
    let shift = start - dayStart
    var segs = Array(homeDay.prefix(3 + i % 5)).map { s -> Segment in
        var c = s; c.id += Int64(i) * 100; c.start += shift; c.end += shift; return c
    }
    if i % 6 == 2 { segs.append(hseg(at(16, 10) + shift, at(16, 10) + shift + 4 * 3600, "Zoom", "Planning")) }
    return DayReport(segments: segs, dayStart: start, now: start == dayStart ? now : start + 86_399, category: homeCategory)
}
let monthVM = HomeViewModel(report: homeReport)
monthVM.setPeriod(.month)
monthVM.week = WeekReport(weekStart: monthStarts[0], reports: monthReports, dayStarts: monthStarts, today: dayStart, isMonth: true)
let unsortedVM = HomeViewModel(report: homeReport)
unsortedVM.unsortedCount = 3
unsortedVM.unsortedTotal = 3 * 3600 + 27 * 60
// A Slack huddle while designing in Figma: one Meetings block with its proof.
func callSeg(_ s: Int64, _ e: Int64, _ title: String?, host: String?) -> Segment {
    var x = hseg(s, e, "Google Chrome", title, host: host)
    x.appBundleID = "com.google.Chrome"
    x.call = true
    return x
}
let huddle = "Alex - Acme - Slack"
let callDay = Array(homeDay.prefix(4)) + [
    hseg(at(11, 20), at(12, 0), "Zoom", "Standup"),
    hseg(at(12, 0), at(12, 50), "", nil, .away),
    hseg(at(12, 50), at(14, 23), "Xcode", "CaptureService.swift — Dayline"),
    callSeg(at(14, 23), at(14, 27), huddle, host: nil),
    callSeg(at(14, 27), at(14, 50), "Onboarding – Figma", host: "www.figma.com"),
    callSeg(at(14, 50), at(14, 54), "Amazon.de", host: "www.amazon.de"),
    callSeg(at(14, 54), at(15, 13), "Onboarding – Figma", host: "www.figma.com"),
    callSeg(at(15, 13), at(15, 16), huddle, host: nil),
    hseg(at(15, 16), at(16, 10), "Xcode", "CaptureService.swift — Dayline"),
].map { s -> Segment in
    var s = s
    if s.host != nil { s.domain = PublicSuffix.shared.registrableDomain(of: s.host!) }
    return s
}
let callCategorizer = Categorizer()
func callResolve(_ s: Segment) -> CategoryResolution {
    if s.appBundleID == "com.google.Chrome" || s.wholeCall { return callCategorizer.resolve(s) }
    let c = homeCategory(s)
    return CategoryResolution(category: c, guess: c, edited: false)
}
let callReport = DayReport(segments: callDay, dayStart: dayStart, now: now, resolve: callResolve)
let callVM = HomeViewModel(report: callReport)
callVM.selection = callReport.blocks.first { $0.call != nil }?.id
// The same call split into what you were doing: its segments pinned.
let splitDay = callDay.map { s -> Segment in
    var s = s
    if s.call { s.manualCategoryID = callCategorizer.resolve(Segment.narrowingCalls([s])[0], ignoringManual: true).category.id }
    return s
}
let splitReport = DayReport(segments: splitDay, dayStart: dayStart, now: now, resolve: callResolve)
let splitVM = HomeViewModel(report: splitReport)
splitVM.selection = splitReport.blocks.first { $0.host == "www.figma.com" }?.id
let callFilterVM = HomeViewModel(report: callReport)
callFilterVM.categoryFilter = .design
let homes: [(String, HomeViewModel)] = [
    ("home-11-call", callVM),
    ("home-13-call-filter", callFilterVM),
    ("home-12-call-split", splitVM),
    ("home-10-unsorted", unsortedVM),
    ("home-09-week", weekVM),
    ("home-09-month", monthVM),
    ("home-08-filtered", filteredVM),
    ("home-01-selected", selectedVM),
    ("home-02-nothing-selected", HomeViewModel(report: homeReport)),
    ("home-03-first-launch", vm(empty, .needsPermission)),
    ("home-04-waiting", vm(empty, .waitingForPermission)),
    ("home-05-first-minutes", vm(firstReport, .tracking, granted: true)),
    ("home-06-paused", vm(morning, .paused(since: at(12, 0), until: at(13, 0)))),
    ("home-07-permission-lost", vm(morning, .permissionLost(at: at(12, 0)))),
]

MainActor.assumeIsolated {
    for (name, vm) in homes {
        let renderer = ImageRenderer(content: HomeView(viewModel: vm, scrolls: false).frame(width: 1200, height: 716))
        renderer.scale = 2
        guard let cg = renderer.cgImage else { print("failed \(name)"); continue }
        try! NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: out.appending(path: "\(name).png"))
        print("wrote \(name).png")
    }
    for (name, model) in states {
        let view = PopoverView(viewModel: PopoverViewModel(model: model), actions: noop)
            .padding(24).background(Theme.bg)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { print("failed \(name)"); continue }
        let rep = NSBitmapImageRep(cgImage: cg)
        try! rep.representation(using: .png, properties: [:])!.write(to: out.appending(path: "\(name).png"))
        print("wrote \(name).png")
    }
}

// Settings has scroll views, which ImageRenderer leaves blank: draw a real
// hosting view in an off-screen window instead.
MainActor.assumeIsolated {
    let s = SettingsViewModel()
    s.section = .categories
    s.categories = ActivityCategory.defaults
    s.rules = [Rule(id: 1, kind: .site, pattern: "figma.com", categoryID: ActivityCategory.design.id, origin: .correction, createdAt: at(10, 0))]
    s.unsorted = [
        Unsorted(kind: .site, pattern: "notion.so", name: "notion.so", via: "Google Chrome", blocks: 14, total: 2 * 3600 + 600),
        Unsorted(kind: .app, pattern: "com.linear", name: "Linear", via: nil, blocks: 6, total: 3900),
        Unsorted(kind: .app, pattern: "com.raycast.macos", name: "Raycast", via: nil, blocks: 9, total: 720),
    ]
    s.exclusions = [.init(id: 1, kind: .app, label: "Finder"), .init(id: 2, kind: .app, label: "1Password"),
                    .init(id: 3, kind: .site, label: "figma.com", mode: .titles)]
    s.titlesOnScreen = .calls
    s.storageText = "4.2 MB since 9 Nov"
    s.builtins = BuiltinRules.all.map { BuiltinRuleRow(kind: $0.kind, label: $0.label, category: $0.category) }
    for (name, section, height) in [("settings-categories-unsorted", SettingsSection.categories, 1000.0),
                                    ("settings-privacy", .privacy, 900)] {
        s.section = section
        let host = NSHostingView(rootView: SettingsView(viewModel: s).frame(width: 1200, height: height))
        let win = NSWindow(contentRect: NSRect(x: -4000, y: 0, width: 1200, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: out.appending(path: "\(name).png"))
        print("wrote \(name).png")
    }
}

// The README's screens: drawn in a real hosting view, so the search field
// and scrolling content render as in the app.
MainActor.assumeIsolated {
    // The day with a block selected, without the "Always categorize" prompt.
    let readmeDay = HomeViewModel(report: correctedReport)
    readmeDay.selection = corrected.id
    for (name, vm) in [("readme-day", readmeDay), ("readme-week", weekVM)] {
        let host = NSHostingView(rootView: HomeView(viewModel: vm).frame(width: 1200, height: 716))
        let win = NSWindow(contentRect: NSRect(x: -4000, y: 0, width: 1200, height: 716), styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: out.appending(path: "\(name).png"))
        print("wrote \(name).png")
    }
}

if realDay {
    MainActor.assumeIsolated {
        let db = try! DaylineDatabase()
        var categorizer = Categorizer(categories: (try? db.categories()) ?? [], rules: (try? db.rules()) ?? [])
        categorizer.aliases = (try? db.categoryAliases()) ?? [:]
        let now = Int64(Date().timeIntervalSince1970)
        let segs = (try? SegmentStore(database: db).segments(from: dayStart, to: dayStart + 86_400)) ?? []
        let report = DayReport(segments: segs, dayStart: dayStart, now: now, resolve: { categorizer.resolve($0) })
        let pop = PopoverView(viewModel: PopoverViewModel(model: PopoverModel(phase: .tracking, summary: DaySummary(report: report),
                                                                              nowStatus: .none, now: now)), actions: noop)
            .padding(24).background(Theme.bg)
        let home = HomeView(viewModel: HomeViewModel(report: report), scrolls: false).frame(width: 1200, height: 716)
        for (name, view) in [("real-popover", AnyView(pop)), ("real-home", AnyView(home))] {
            let r = ImageRenderer(content: view)
            r.scale = 2
            try! NSBitmapImageRep(cgImage: r.cgImage!).representation(using: .png, properties: [:])!.write(to: out.appending(path: "\(name).png"))
            print("wrote \(name).png")
        }
    }
}

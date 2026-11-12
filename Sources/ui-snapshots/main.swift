import AppKit
import Categorize
import Store
import Domain
import SwiftUI
import UI

// Renders the popover in every state with sample data, for comparing
// against design/screens. Usage: ui-snapshots [output-dir]

// --today renders your real day from the Dayline database (stays in build/, git-ignored).
let realDay = CommandLine.arguments.contains("--today")
let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first { !$0.hasPrefix("--") } ?? "build/snapshots")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let cal = Calendar.current
let dayStart = Int64(cal.startOfDay(for: Date()).timeIntervalSince1970)
func at(_ h: Int, _ m: Int) -> Int64 { dayStart + Int64(h * 3600 + m * 60) }

func seg(_ s: Int64, _ e: Int64, _ app: String, _ title: String? = nil, _ kind: SegmentKind = .active, call: Bool = false) -> Segment {
    Segment(id: 0, start: s, end: e, kind: kind, appBundleID: app, appName: app, title: title, call: call)
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
let homes: [(String, HomeViewModel)] = [
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

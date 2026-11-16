import Domain
import Foundation

/// Day or week, switched next to the date (spec 5.3).
public enum Period: String, CaseIterable, Sendable {
    case day = "Day"
    case week = "Week"
}

public enum TimelineMode: String, CaseIterable, Sendable {
    case byCategory = "By category"
    case timeline = "Timeline"
}

/// "Always categorize developer.apple.com as Development?" (spec 4, screen 01).
public struct Correction: Equatable, Sendable {
    public var blockID: Int64
    public var kind: Rule.Kind
    /// Host for sites, bundle id for apps.
    public var pattern: String
    /// What the prompt calls it: the host, or the app's name.
    public var subject: String
    public var category: ActivityCategory
    /// The block's category before the change, for Cancel.
    public var previous: ActivityCategory

    public init(blockID: Int64, kind: Rule.Kind, pattern: String, subject: String, category: ActivityCategory,
                previous: ActivityCategory) {
        self.blockID = blockID
        self.kind = kind
        self.pattern = pattern
        self.subject = subject
        self.category = category
        self.previous = previous
    }

    /// Browser blocks are about the site; everything else about the app.
    public static func subject(for b: Block, category: ActivityCategory) -> Correction {
        if let host = b.host {
            return Correction(blockID: b.id, kind: .site, pattern: host, subject: host, category: category,
                              previous: b.category)
        }
        return Correction(blockID: b.id, kind: .app, pattern: b.appBundleID, subject: b.appName, category: category,
                          previous: b.category)
    }
}

/// State of the main window. The app sets `report`; the view owns the rest.
public final class HomeViewModel: ObservableObject {
    @Published public var report: DayReport
    @Published public private(set) var period = Period.day
    /// Set by the app while the week view is shown.
    @Published public var week: WeekReport?
    @Published public var selection: Int64?
    @Published public var mode = TimelineMode.byCategory
    @Published public var search = ""
    @Published public var categoryFilter: ActivityCategory?
    @Published public var showAllBlocks = false
    @Published public var showAllLanes = false
    /// All categories, for the inspector's select.
    @Published public var categories: [ActivityCategory] = ActivityCategory.defaults
    /// Shown under the select after a correction, until answered or deselected.
    @Published public var pendingCorrection: Correction?

    // Tracking state (spec 2.2) and onboarding settings (screens 03–07).
    @Published public var phase: TrackingPhase = .tracking
    /// "Accessibility access granted" banner, after a grant in this session.
    @Published public var showGrantedBanner = false
    @Published public var idleMinutes = 2
    public var idleChoices = [1, 2, 3, 5, 10]
    @Published public var startAtLogin = true
    /// Shown under the Start at login switch when macOS refused the change.
    @Published public var startAtLoginError: String?

    public var onOpenSystemSettings: (() -> Void)?
    public var onResume: (() -> Void)?
    public var onSetIdleMinutes: ((Int) -> Void)?
    public var onSetStartAtLogin: ((Bool) -> Void)?

    /// Move by whole days; the app reloads `report`.
    /// Apps and sites from the last week still in Uncategorized, for the Sort note.
    /// Bumped when a day or week is (re)loaded into view: the window opens,
    /// another day or week, Day ↔ Week. The charts replay their grow-in.
    @Published public var replay = 0
    @Published public var unsortedCount = 0
    @Published public var unsortedTotal: Int64 = 0
    /// Opens Settings → Categories & rules.
    public var onSortUnsorted: (() -> Void)?
    public var onMoveDay: ((Int) -> Void)?
    public var onPickDay: ((Date) -> Void)?
    /// The app loads the week (or the day) after a switch.
    public var onSetPeriod: ((Period) -> Void)?
    /// Re-categorize just this block (the app writes the override and reloads).
    public var onSetCategory: ((Block, ActivityCategory) -> Void)?
    /// "Always": turn the correction into a rule.
    public var onAlways: ((Correction) -> Void)?
    /// "What I was doing": a whole call goes back to what was in front.
    public var onSplitCall: ((Block) -> Void)?
    /// A split call counts as one Meetings block again.
    public var onWholeCall: ((DayReport.Call) -> Void)?

    /// "Delete": the block's time is removed and becomes a gap.
    public var onDeleteBlock: ((Block) -> Void)?

    public func deleteBlock(_ block: Block) {
        selection = nil
        pendingCorrection = nil
        onDeleteBlock?(block)
    }

    public func splitCall(_ block: Block) {
        selection = block.id
        pendingCorrection = nil
        onSplitCall?(block)
    }

    public func wholeCall(_ call: DayReport.Call) {
        pendingCorrection = nil
        onWholeCall?(call)
    }

    /// The split call a block was part of, for "Count the whole call as Meetings".
    public func splitCall(containing b: Block) -> DayReport.Call? {
        guard b.call == nil, let first = b.segmentIDs.first else { return nil }
        return report.calls.first { $0.split && $0.segmentIDs.contains(first) }
    }

    /// The inspector select or a drag to another lane.
    public func setCategory(_ block: Block, _ category: ActivityCategory) {
        guard category != block.category else { return }
        // Set before the reload, so update() can follow the block if it merges.
        selection = block.id
        // Picking Dayline's own guess again is an undo, not a correction.
        // A call is not an app or site to make a rule for.
        pendingCorrection = category == block.guess || block.call != nil ? nil : Correction.subject(for: block, category: category)
        onSetCategory?(block, category)
    }

    public func always() {
        guard let c = pendingCorrection else { return }
        onAlways?(c)
        pendingCorrection = nil
    }

    /// Cancel: put the block back in the category it had before the change.
    public func cancelCorrection() {
        guard let c = pendingCorrection else { return }
        pendingCorrection = nil
        if let b = report.blocks.first(where: { $0.id == c.blockID }) { onSetCategory?(b, c.previous) }
    }

    public func setPeriod(_ p: Period) {
        guard p != period else { return }
        period = p
        select(nil)
        onSetPeriod?(p)
    }

    /// A day row in the week view: open that day.
    public func openDay(_ dayStart: Int64) {
        period = .day
        onSetPeriod?(.day)
        onPickDay?(Date(timeIntervalSince1970: TimeInterval(dayStart)))
    }

    public init(report: DayReport) {
        self.report = report
    }

    /// Spec 5.3: lists show the 3 most recent blocks until expanded.
    public static let collapsedCount = 3
    /// Spec 5.3: at most 8 lanes before "+N more".
    public static let laneCap = 8

    public var isFiltering: Bool { !search.isEmpty || categoryFilter != nil }

    /// Time in the filtered category done during a call (Design on a huddle);
    /// 0 for any other block. It stays the call's in every total.
    public func callMinutes(_ b: Block) -> Int64 {
        guard let c = categoryFilter, b.category != c, let call = b.call else { return 0 }
        return call.totals.filter { $0.category == c }.reduce(0) { $0 + $1.duration }
    }

    /// Newest first, after search and category filter. A category also lists
    /// the calls you worked in it on.
    public var filteredBlocks: [Block] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return report.blocks.reversed().filter { b in
            (categoryFilter == nil || b.category == categoryFilter || callMinutes(b) > 0)
                && (q.isEmpty || [b.title, b.appName, b.host].contains { $0?.localizedCaseInsensitiveContains(q) ?? false })
        }
    }

    public var visibleBlocks: [Block] {
        let all = filteredBlocks
        return showAllBlocks || isFiltering ? all : Array(all.prefix(Self.collapsedCount))
    }

    public var selectedBlock: Block? {
        selection.flatMap { id in report.blocks.first { $0.id == id } }
    }

    public func select(_ id: Int64?) {
        if id != selection { pendingCorrection = nil }
        selection = id
        // Keep the selected row visible in the list.
        if let id, !visibleBlocks.contains(where: { $0.id == id }) {
            search = ""
            categoryFilter = nil
            showAllBlocks = true
        }
    }

    /// ↑ / ↓: move through blocks in list order (newest first).
    public func moveSelection(_ delta: Int) {
        let list = filteredBlocks
        guard !list.isEmpty else { return }
        guard let id = selection, let i = list.firstIndex(where: { $0.id == id }) else {
            select(list.first?.id)
            return
        }
        select(list[min(max(i + delta, 0), list.count - 1)].id)
    }

    /// Replaces the report, keeping the selection if the block still exists.
    public func update(_ new: DayReport) {
        if new.dayStart != report.dayStart {
            selection = nil
            showAllBlocks = false
            showAllLanes = false
            search = ""
            categoryFilter = nil
            pendingCorrection = nil
        } else if let id = selection, !new.blocks.contains(where: { $0.id == id }) {
            // A correction can merge the block into a neighbour; follow its segments.
            let moved = new.blocks.first { $0.segmentIDs.contains(id) }?.id
            selection = moved
            if let moved { pendingCorrection?.blockID = moved } else { pendingCorrection = nil }
        }
        if new != report { report = new }
    }
}

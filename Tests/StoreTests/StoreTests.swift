import Domain
import Foundation
import Testing
@testable import Store

@Suite struct StoreTests {
    func makeStore() throws -> SegmentStore {
        let url = FileManager.default.temporaryDirectory.appending(path: "dayline-test-\(UUID().uuidString).sqlite")
        return SegmentStore(database: try DaylineDatabase(url: url))
    }

    @Test func segmenterChangesRoundTrip() throws {
        let store = try makeStore()
        var seg = Segmenter()
        let xcode = Activity(appBundleID: "com.apple.dt.Xcode", appName: "Xcode", title: "a.swift")
        let gh = Activity.browser(appBundleID: "com.google.Chrome", appName: "Google Chrome", title: "PRs",
                                  url: URL(string: "https://github.com/pulls"))
        try store.apply(seg.handle(.startTracking, at: 1000))
        try store.apply(seg.handle(.activity(xcode), at: 1000))
        try store.apply(seg.handle(.tick, at: 1030))
        try store.apply(seg.handle(.activity(gh), at: 1060))
        try store.apply(seg.handle(.suspend(.lock), at: 1100))
        try store.apply(seg.handle(.resume(.lock), at: 1400))
        try store.apply(seg.handle(.tick, at: 1410))

        let rows = try store.segments(from: 0, to: 2000)
        #expect(rows.map(\.kind) == [.active, .active, .away, .active])
        #expect(rows.map(\.start) == [1000, 1060, 1100, 1400])
        #expect(rows.map(\.end) == [1060, 1100, 1400, 1410])
        #expect(rows[1].host == "github.com" && rows[1].domain == "github.com")
        #expect(rows[2].appBundleID == "" && rows[2].title == nil)
    }

    @Test func discardDeletesOpenRow() throws {
        let store = try makeStore()
        try store.apply([.begin(SegmentDraft(start: 5, kind: .active, activity: Activity(appBundleID: "a", appName: "A")))])
        try store.apply([.discard, .begin(SegmentDraft(start: 5, kind: .away))])
        let rows = try store.segments(from: 0, to: 100)
        #expect(rows.map(\.kind) == [.away])
    }

    @Test func seedsCategories() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "dayline-test-\(UUID().uuidString).sqlite")
        let db = try DaylineDatabase(url: url)
        let n = try db.pool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM category") }
        #expect(n == ActivityCategory.defaults.count)
    }
}

@Suite struct SettingTests {
    @Test func setReadAndRemove() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "dayline-test-\(UUID().uuidString).sqlite")
        let db = try DaylineDatabase(url: url)
        #expect(try db.setting("pause.since") == nil)
        try db.setSetting("pause.since", "100")
        try db.setSetting("pause.since", "200")
        #expect(try db.setting("pause.since") == "200")
        try db.setSetting("pause.since", nil)
        #expect(try db.setting("pause.since") == nil)
    }
}

@Suite struct RuleStoreTests {
    func db() throws -> DaylineDatabase {
        try DaylineDatabase(url: FileManager.default.temporaryDirectory.appending(path: "dayline-test-\(UUID().uuidString).sqlite"))
    }

    @Test func seedCategoryIdsMatchDomain() throws {
        let cats = try db().categories()
        #expect(cats.first { $0.name == "Development" }?.id == ActivityCategory.development.id)
        #expect(cats.first { $0.name == "Uncategorized" }?.id == ActivityCategory.uncategorized.id)
    }

    @Test func addingTheSameRuleTwiceReplacesIt() throws {
        let d = try db()
        try d.addRule(kind: .site, pattern: "github.com", categoryID: 2, origin: .correction, at: 1)
        try d.addRule(kind: .site, pattern: "GitHub.com", categoryID: 3, origin: .correction, at: 2)
        let rules = try d.rules()
        #expect(rules.count == 1)
        #expect(rules[0].categoryID == 3)
        try d.deleteRule(id: rules[0].id)
        #expect(try d.rules().isEmpty)
    }

    @Test func manualCategoryRoundTrips() throws {
        let d = try db()
        let store = SegmentStore(database: d)
        try store.apply([.begin(SegmentDraft(start: 10, kind: .active, activity: Activity(appBundleID: "a", appName: "A"))), .end(at: 20)])
        let id = try store.segments(from: 0, to: 100)[0].id
        try store.setManualCategory(segmentIDs: [id], categoryID: 3)
        #expect(try store.segments(from: 0, to: 100)[0].manualCategoryID == 3)
        try store.setManualCategory(segmentIDs: [id], categoryID: nil)
        #expect(try store.segments(from: 0, to: 100)[0].manualCategoryID == nil)
    }

    @Test func deletingABlockLeavesAGap() throws {
        let store = SegmentStore(database: try db())
        let a = Activity(appBundleID: "a", appName: "A"), b = Activity(appBundleID: "b", appName: "B")
        try store.apply([.begin(SegmentDraft(start: 10, kind: .active, activity: a)), .end(at: 20),
                         .begin(SegmentDraft(start: 20, kind: .active, activity: b)), .end(at: 30)])
        let rows = try store.segments(from: 0, to: 100)
        try store.deleteSegments(ids: [rows[0].id])
        #expect(try store.segments(from: 0, to: 100).map(\.start) == [20])
    }

    @Test func notesRoundTripAndClear() throws {
        let store = SegmentStore(database: try db())
        try store.apply([.begin(SegmentDraft(start: 10, kind: .active, activity: Activity(appBundleID: "a", appName: "A"))), .end(at: 20)])
        let id = try store.segments(from: 0, to: 100)[0].id
        try store.setNote(segmentIDs: [id], note: "  Loan flow  ")
        #expect(try store.segments(from: 0, to: 100)[0].note == "Loan flow")
        try store.setNote(segmentIDs: [id], note: " ")
        #expect(try store.segments(from: 0, to: 100)[0].note == nil)
    }

    @Test func searchFindsTitlesAndNotesAnyCase() throws {
        let store = SegmentStore(database: try db())
        try store.apply([.begin(SegmentDraft(start: 10, kind: .active, activity: Activity(appBundleID: "a", appName: "Figma", title: "Čarobni loan flow"))), .end(at: 20),
                         .begin(SegmentDraft(start: 30, kind: .active, activity: Activity(appBundleID: "b", appName: "Slack"))), .end(at: 40),
                         .begin(SegmentDraft(start: 50, kind: .active, activity: Activity(appBundleID: "c", appName: "Mail"))), .end(at: 60)])
        try store.setNote(segmentIDs: [try store.segments(from: 0, to: 100)[1].id], note: "Loan review")
        #expect(try store.starts(matching: "LOAN") == [30, 10])
        #expect(try store.starts(matching: "čarobni") == [10])
        #expect(try store.starts(matching: "nothing").isEmpty)
    }

    @Test func newCategoryAndRename() throws {
        let d = try db()
        var c = try d.addCategory(name: "Admin", color: "#9B7CFF")
        c.name = "Admin and finance"
        try d.updateCategory(c)
        #expect(try d.categories().contains(c))
    }
}

@Suite struct DataStoreTests {
    func db() throws -> DaylineDatabase {
        try DaylineDatabase(url: FileManager.default.temporaryDirectory.appending(path: "dayline-test-\(UUID().uuidString).sqlite"))
    }

    func addSegment(_ store: SegmentStore, _ start: Int64, _ end: Int64) throws {
        try store.apply([.begin(SegmentDraft(start: start, kind: .active, activity: Activity(appBundleID: "a", appName: "A"))),
                         .end(at: end)])
    }

    @Test func retentionDropsOldSegments() throws {
        let d = try db()
        let store = SegmentStore(database: d)
        try addSegment(store, 10, 20)
        try addSegment(store, 1000, 2000)
        #expect(try d.deleteSegments(endedBefore: 500) == 1)
        #expect(try store.segments(from: 0, to: 5000).map(\.start) == [1000])
    }

    @Test func deleteAllEmptiesDataAndResetsCategories() throws {
        let d = try db()
        let store = SegmentStore(database: d)
        try addSegment(store, 10, 20)
        try d.addRule(kind: .site, pattern: "x.com", categoryID: 2, origin: .user, at: 1)
        try d.addExclusion(kind: .app, pattern: "com.example")
        try d.addCategory(name: "Extra", color: "#000000")
        try d.updateCategory(ActivityCategory(id: 1, name: "Code", color: "#111111"))
        try d.setSetting("idle.minutes", "5")
        try d.deleteAll()
        #expect(try store.segments(from: 0, to: 100).isEmpty)
        #expect(try d.rules().isEmpty)
        #expect(try d.exclusionRows().isEmpty)
        #expect(try d.categories() == ActivityCategory.defaults)
        #expect(try d.setting("idle.minutes") == "5")
    }

    @Test func mergeMovesRulesAndAliases() throws {
        let d = try db()
        try d.addRule(kind: .site, pattern: "x.com", categoryID: ActivityCategory.writing.id, origin: .user, at: 1)
        try d.mergeCategory(ActivityCategory.writing.id, into: ActivityCategory.design.id)
        #expect(try d.rules()[0].categoryID == ActivityCategory.design.id)
        #expect(try d.categoryAliases() == [ActivityCategory.writing.id: ActivityCategory.design.id])
        #expect(try !d.categories().contains { $0.id == ActivityCategory.writing.id })
    }

    @Test func newCategoryCanBeDeleted() throws {
        let d = try db()
        let c = try d.addCategory(name: "Admin", color: "#9B7CFF")
        #expect(try d.categories().contains(c))
        try d.mergeCategory(c.id, into: ActivityCategory.uncategorized.id)
        #expect(try !d.categories().contains { $0.id == c.id })
    }

    @Test func exclusionsRoundTrip() throws {
        let d = try db()
        try d.addExclusion(kind: .site, pattern: "bank.example")
        try d.addExclusion(kind: .app, pattern: "com.1password.1password")
        #expect(try d.exclusions().excludes(Activity(appBundleID: "com.1password.1password", appName: "1Password")))
        let rows = try d.exclusionRows()
        try d.deleteExclusion(id: rows[0].id)
        #expect(try d.exclusionRows().count == 1)
    }
}

extension StoreTests {
    @Test func hiddenTitlesGetStableLabels() throws {
        let d = try DaylineDatabase(url: FileManager.default.temporaryDirectory.appending(path: "dayline-test-\(UUID().uuidString).sqlite"))
        try d.addExclusion(kind: .site, pattern: "figma.com", mode: .titles)
        let ex = try d.exclusions()
        let file = Activity.browser(appBundleID: "com.google.Chrome", appName: "Google Chrome", title: "Enes Projekt broj 2 – FigJam",
                                    url: URL(string: "https://www.figma.com/board/x"))
        #expect(ex.hidesTitle(file) && !ex.excludes(file))
        #expect(try d.hiddenTitle("Enes Projekt broj 2 – FigJam", scope: "figma.com") == "Hidden title A")
        #expect(try d.hiddenTitle("Other file – Figma", scope: "figma.com") == "Hidden title B")
        #expect(try d.hiddenTitle("(2) Enes Projekt broj 2 – FigJam", scope: "figma.com") == "Hidden title A")  // badges don't matter
        #expect(try d.hiddenTitle("Enes Projekt broj 2 – FigJam", scope: "com.figma.Desktop") == "Hidden title A")  // own letters per app
        #expect(DaylineDatabase.letters(26) == "AA")
        // One mode per site: moving it to Don't track takes it off the titles list.
        try d.addExclusion(kind: .site, pattern: "figma.com")
        #expect(try d.exclusionRows().map(\.mode) == [ExclusionMode.skip])
    }

    @Test func savedTitlesCanBeReplaced() throws {
        let d = try DaylineDatabase(url: FileManager.default.temporaryDirectory.appending(path: "dayline-test-\(UUID().uuidString).sqlite"))
        let store = SegmentStore(database: d)
        let file = Activity.browser(appBundleID: "com.google.Chrome", appName: "Google Chrome", title: "Secret plan – Figma",
                                    url: URL(string: "https://www.figma.com/file/x"))
        let other = Activity.browser(appBundleID: "com.google.Chrome", appName: "Google Chrome", title: "News",
                                     url: URL(string: "https://example.com"))
        try store.apply([.begin(SegmentDraft(start: 0, kind: .active, activity: file)), .end(at: 10),
                         .begin(SegmentDraft(start: 10, kind: .active, activity: other)), .end(at: 20)])
        #expect(try d.hideSavedTitles(kind: .site, pattern: "figma.com") == 1)
        #expect(try store.segments(from: 0, to: 100).map(\.title) == ["Hidden title A", "News"])
        #expect(try d.hideSavedTitles(kind: .site, pattern: "figma.com") == 0)   // already hidden
    }
}

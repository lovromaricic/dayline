import Foundation
import Testing
@testable import Domain

@Suite struct ProjectTests {
    let krediti = Project(id: 1, name: "Krediti", clientID: 9, clientName: "Erste")
    let george = Project(id: 2, name: "George app", clientID: 9, clientName: "Erste")

    func seg(_ id: Int64, _ start: Int64, _ end: Int64, _ title: String, manual: Int64? = nil) -> Segment {
        Segment(id: id, start: start, end: end, kind: .active, appBundleID: "figma", appName: "Figma", title: title, manualProjectID: manual)
    }

    @Test func handPickedBeatsRulesAndNewerRuleWins() {
        let r = ProjectResolver(projects: [krediti, george], rules: [
            ProjectRule(id: 1, projectID: 1, kind: .titleContains, pattern: "kreditni", createdAt: 10),
            ProjectRule(id: 2, projectID: 2, kind: .titleContains, pattern: "George kreditni kalkulator", createdAt: 20)])
        #expect(r.resolve(seg(1, 0, 10, "Kreditni limiti – FigJam"))?.project == krediti)
        #expect(r.resolve(seg(2, 0, 10, "George kreditni kalkulator – Figma"))?.project == george)
        #expect(r.resolve(seg(3, 0, 10, "Kreditni limiti", manual: 2))?.project == george)
        #expect(r.resolve(seg(4, 0, 10, "Kreditni limiti", manual: ProjectResolver.none)) == nil)
        #expect(r.resolve(seg(5, 0, 10, "Inbox")) == nil)
    }

    @Test func aBlockTakesTheProjectOfMostOfItsTime() {
        let segs = [seg(1, 0, 600, "Kreditni limiti – FigJam"), seg(2, 600, 700, "Other – FigJam")]
        let report = DayReport(segments: segs, dayStart: 0, now: 700) { _ in .design }
        let r = ProjectResolver(projects: [krediti], rules: [ProjectRule(id: 1, projectID: 1, kind: .titleContains, pattern: "kreditni", createdAt: 1)])
        let b = report.withProjects(r, segments: segs).blocks
        #expect(b.count == 1 && b[0].project == krediti && b[0].projectRule?.pattern == "kreditni")
        // Mostly unassigned: no project.
        let segs2 = [seg(1, 0, 100, "Kreditni limiti – FigJam"), seg(2, 100, 700, "Other – FigJam")]
        let b2 = DayReport(segments: segs2, dayStart: 0, now: 700) { _ in .design }.withProjects(r, segments: segs2).blocks
        #expect(b2[0].project == nil)
    }

    @Test func anArchivedProjectKeepsItsPastButAddsNothingNew() {
        var old = krediti
        old.archivedAt = 100
        let r = ProjectResolver(projects: [old], rules: [ProjectRule(id: 1, projectID: 1, kind: .titleContains, pattern: "kreditni", createdAt: 1)])
        #expect(r.resolve(seg(1, 50, 90, "Kreditni limiti"))?.project.id == 1)
        #expect(r.resolve(seg(2, 150, 200, "Kreditni limiti")) == nil)
        #expect(r.active.isEmpty)
    }
}

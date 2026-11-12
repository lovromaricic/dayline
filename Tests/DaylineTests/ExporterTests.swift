import Categorize
import Domain
import Foundation
import Testing
import UI
@testable import Dayline

/// Acceptance test 8: an export round-trips the same totals.
@Suite struct ExporterTests {
    let segments = [
        Segment(id: 1, start: 1000, end: 4600, kind: .active, appBundleID: "com.apple.dt.Xcode", appName: "Xcode", title: "a, \"quoted\" title"),
        Segment(id: 2, start: 4600, end: 5200, kind: .away),
        Segment(id: 3, start: 5200, end: 6100, kind: .active, appBundleID: "com.google.Chrome", appName: "Google Chrome",
                title: "PR", host: "github.com", domain: "github.com"),
        Segment(id: 4, start: 6100, end: 6400, kind: .untracked),
    ]

    @Test func csvRoundTripsTotals() throws {
        let rows = Exporter.rows(segments, categorizer: Categorizer())
        let csv = String(decoding: try Exporter.data(rows, format: .csv), as: UTF8.self)
        let lines = csv.split(separator: "\n").dropFirst()
        #expect(lines.count == 4)
        // seconds is the 3rd column; titles with commas and quotes are quoted.
        #expect(csv.contains("\"a, \"\"quoted\"\" title\""))
        let report = DayReport(segments: segments, dayStart: 0, now: 100_000, category: Categorizer().category(for:))
        let active = rows.filter { $0.kind == "active" }.reduce(Int64(0)) { $0 + $1.seconds }
        #expect(active == report.tracked)
        #expect(rows.filter { $0.kind == "away" }.reduce(Int64(0)) { $0 + $1.seconds } == report.awayTotal)
    }

    @Test func jsonDecodesWithCategories() throws {
        let rows = Exporter.rows(segments, categorizer: Categorizer())
        let json = try JSONSerialization.jsonObject(with: Exporter.data(rows, format: .json)) as! [[String: Any]]
        #expect(json.count == 4)
        #expect(json[0]["category"] as? String == "Development")
        #expect(json[2]["category"] as? String == "Development")
        #expect(json[1]["category"] == nil)
        #expect(json.compactMap { $0["seconds"] as? Int }.reduce(0, +) == 5400)
    }
}

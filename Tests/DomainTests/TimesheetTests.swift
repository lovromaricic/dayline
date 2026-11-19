import Foundation
import Testing
@testable import Domain

@Suite struct TimesheetTests {
    let krediti = Project(id: 1, name: "Krediti", clientID: 1, clientName: "Erste", clientRate: 60, clientCurrency: "EUR")
    let george = Project(id: 2, name: "George app", clientID: 1, clientName: "Erste", rate: 75, clientRate: 60, clientCurrency: "EUR")

    func block(_ id: Int64, _ start: Int64, _ minutes: Int64, _ p: Project, note: String? = nil) -> Block {
        var b = Block(id: id, start: start, end: start + minutes * 60, duration: minutes * 60, appBundleID: "figma", appName: "Figma",
                      title: "File – Figma", host: nil, domain: nil, category: .design, guess: .design, edited: false, segmentIDs: [id])
        b.project = p
        b.note = note
        return b
    }

    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    @Test func dayRowsRoundAndPrice() {
        let day = Int64(1_794_441_600)  // a Monday, UTC
        let t = Timesheet(days: [(day, [block(1, day + 3600, 100, krediti, note: "Limits"), block(2, day + 9000, 7, krediti),
                                        block(3, day + 9600, 31, george)])],
                          include: { $0.clientID == 1 }, grouping: .day, round: 15, calendar: cal)
        #expect(t.rows.map(\.project) == ["Krediti", "George app"])
        #expect(t.rows[0].seconds == 105 * 60 && t.rows[0].amount == 105.0 && t.rows[0].notes == "Limits")  // 107 → 1:45 at €60
        #expect(t.rows[1].seconds == 30 * 60 && t.rows[1].amount == 37.5)  // own rate €75
        #expect(t.unrounded == 138 * 60 && t.amounts == ["EUR": 142.5])
    }

    @Test func rowsPerMonthAndPerBlock() {
        let day = Int64(1_794_441_600)
        let days = [(day, [block(1, day, 60, krediti)]), (day + 86_400, [block(2, day + 86_400, 30, krediti)])]
        #expect(Timesheet(days: days, include: { _ in true }, grouping: .month, round: 0, calendar: cal).rows.map(\.seconds) == [5400])
        let blocks = Timesheet(days: days, include: { _ in true }, grouping: .block, round: 0, calendar: cal)
        #expect(blocks.rows.count == 2 && blocks.rows[0].time != nil && blocks.rows[0].title == "File – Figma")
    }

    @Test func filesHaveTotalsAndOpenAsZip() {
        let day = Int64(1_794_441_600)
        let t = Timesheet(days: [(day, [block(1, day, 90, krediti)])], include: { _ in true }, grouping: .day, round: 0, calendar: cal)
        let csv = String(decoding: TimesheetFile.data(t, grouping: .day, format: .csv), as: UTF8.self)
        #expect(csv.contains("Date,Client,Project,Duration,Hours,Rate,Currency,Amount,Notes"))
        #expect(csv.contains("Erste,Krediti,1:30,1.5,60,EUR,90,"))
        #expect(csv.contains("Total,,,1:30,1.5,,EUR,90,"))
        let xlsx = TimesheetFile.data(t, grouping: .day, format: .xlsx)
        #expect(xlsx.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]))
        if let out = ProcessInfo.processInfo.environment["DAYLINE_XLSX_OUT"] { try? xlsx.write(to: URL(fileURLWithPath: out)) }
        #expect(Zip.crc32(Data("hello".utf8)) == 0x3610A686)
    }
}

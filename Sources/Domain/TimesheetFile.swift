import Foundation

/// A timesheet as CSV or Excel (.xlsx). Rate and Amount are plain numbers so
/// a spreadsheet can add them up; the currency has its own column.
public enum TimesheetFile {
    public enum Format: String, CaseIterable, Sendable {
        case xlsx = "Excel (.xlsx)"
        case csv = "CSV"

        public var fileExtension: String { self == .xlsx ? "xlsx" : "csv" }
    }

    enum Cell: Equatable {
        case text(String)
        case number(Double)
        case empty
    }

    /// Header, rows, and a total row.
    static func table(_ t: Timesheet, grouping: Timesheet.Grouping) -> [[Cell]] {
        let blocks = grouping == .block
        var head = ["Date"]
        if blocks { head += ["Time", "Title"] }
        head += ["Client", "Project", "Duration", "Hours", "Rate", "Currency", "Amount", "Notes"]
        var out: [[Cell]] = [head.map(Cell.text)]
        for r in t.rows {
            var row: [Cell] = [.text(r.date)]
            if blocks { row += [.text(r.time ?? ""), .text(r.title ?? "")] }
            row += [.text(r.client), .text(r.project), .text(r.clock), .number(r.hours),
                    r.rate.map(Cell.number) ?? .empty, .text(r.currency), r.amount.map(Cell.number) ?? .empty,
                    r.notes.isEmpty ? .empty : .text(r.notes)]
            out.append(row)
        }
        // One total row per currency, so euros and dollars never add up.
        let total = Timesheet.Row(date: "", client: "", project: "", seconds: t.seconds, rate: nil, currency: "", notes: "")
        let amounts = t.amounts.sorted { $0.key < $1.key }
        for (i, (currency, amount)) in (amounts.isEmpty ? [("", 0.0)] : amounts).enumerated() {
            var row: [Cell] = [.text(i == 0 ? "Total" : "")]
            if blocks { row += [.empty, .empty] }
            row += [.empty, .empty, i == 0 ? .text(total.clock) : .empty, i == 0 ? .number(total.hours) : .empty, .empty,
                    currency.isEmpty ? .empty : .text(currency), currency.isEmpty ? .empty : .number(amount), .empty]
            out.append(row)
        }
        return out
    }

    public static func data(_ t: Timesheet, grouping: Timesheet.Grouping, format: Format) -> Data {
        let table = table(t, grouping: grouping)
        switch format {
        case .csv: return csv(table)
        case .xlsx: return xlsx(table)
        }
    }

    static func csv(_ table: [[Cell]]) -> Data {
        func field(_ c: Cell) -> String {
            switch c {
            case .empty: return ""
            case .number(let n): return number(n)
            case .text(let s):
                return s.contains(where: { ",\"\n\r".contains($0) }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
            }
        }
        return Data(table.map { $0.map(field).joined(separator: ",") }.joined(separator: "\n").appending("\n").utf8)
    }

    /// Two decimals at most, no trailing zeros: 1.75, 60, 2253.75.
    static func number(_ n: Double) -> String {
        var s = String(format: "%.2f", n)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    // MARK: - Excel

    static func xlsx(_ table: [[Cell]]) -> Data {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        func column(_ i: Int) -> String {
            var n = i + 1, s = ""
            while n > 0 { s = String(UnicodeScalar(UInt8(65 + (n - 1) % 26))) + s; n = (n - 1) / 26 }
            return s
        }
        var rows = ""
        for (r, row) in table.enumerated() {
            // Header and total rows bold (style 1).
            let bold = r == 0 || { if case .text("Total") = row.first { return true }; return false }()
            rows += "<row r=\"\(r + 1)\">"
            for (c, cell) in row.enumerated() {
                let ref = "\(column(c))\(r + 1)", s = bold ? " s=\"1\"" : ""
                switch cell {
                case .empty: continue
                case .number(let n): rows += "<c r=\"\(ref)\"\(s)><v>\(number(n))</v></c>"
                case .text(let t): rows += "<c r=\"\(ref)\" t=\"inlineStr\"\(s)><is><t xml:space=\"preserve\">\(esc(t))</t></is></c>"
                }
            }
            rows += "</row>"
        }
        // Wide enough for dates and titles; Notes widest.
        let widths = (table.first ?? []).map { cell -> Int in
            if case .text(let h) = cell { return h == "Notes" ? 40 : h == "Title" ? 32 : 13 }
            return 13
        }
        let cols = "<cols>" + widths.enumerated().map { "<col min=\"\($0.offset + 1)\" max=\"\($0.offset + 1)\" width=\"\($0.element)\" customWidth=\"1\"/>" }.joined() + "</cols>"
        let head = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        let files: [(String, String)] = [
            ("[Content_Types].xml", head + """
                <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
                <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
                <Default Extension="xml" ContentType="application/xml"/>\
                <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
                <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>\
                <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\
                </Types>
                """),
            ("_rels/.rels", head + """
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
                <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
                </Relationships>
                """),
            ("xl/workbook.xml", head + """
                <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
                xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
                <sheets><sheet name="Hours" sheetId="1" r:id="rId1"/></sheets></workbook>
                """),
            ("xl/_rels/workbook.xml.rels", head + """
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
                <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>\
                <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
                </Relationships>
                """),
            ("xl/styles.xml", head + """
                <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
                <fonts count="2"><font><sz val="12"/><name val="Calibri"/></font><font><b/><sz val="12"/><name val="Calibri"/></font></fonts>\
                <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>\
                <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>\
                <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
                <cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>\
                <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>\
                </styleSheet>
                """),
            ("xl/worksheets/sheet1.xml", head + """
                <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\(cols)<sheetData>\(rows)</sheetData></worksheet>
                """),
        ]
        return Zip.stored(files.map { ($0.0, Data($0.1.utf8)) })
    }
}

/// A ZIP archive with stored (uncompressed) entries: all an .xlsx needs.
enum Zip {
    static func stored(_ entries: [(name: String, data: Data)]) -> Data {
        var out = Data(), central = Data()
        func u16(_ v: Int, _ d: inout Data) { d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF)) }
        func u32(_ v: UInt32, _ d: inout Data) { for i in 0..<4 { d.append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) } }
        for (name, data) in entries {
            let crc = crc32(data), size = UInt32(data.count), nameBytes = Data(name.utf8), offset = UInt32(out.count)
            u32(0x04034B50, &out); u16(20, &out); u16(0, &out); u16(0, &out); u16(0, &out); u16(0x21, &out)
            u32(crc, &out); u32(size, &out); u32(size, &out); u16(nameBytes.count, &out); u16(0, &out)
            out.append(nameBytes); out.append(data)
            u32(0x02014B50, &central); u16(20, &central); u16(20, &central); u16(0, &central); u16(0, &central)
            u16(0, &central); u16(0x21, &central); u32(crc, &central); u32(size, &central); u32(size, &central)
            u16(nameBytes.count, &central); u16(0, &central); u16(0, &central); u16(0, &central); u16(0, &central)
            u32(0, &central); u32(offset, &central); central.append(nameBytes)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        u32(0x06054B50, &out); u16(0, &out); u16(0, &out); u16(entries.count, &out); u16(entries.count, &out)
        u32(UInt32(central.count), &out); u32(centralOffset, &out); u16(0, &out)
        return out
    }

    static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
            table[i] = c
        }
        var crc: UInt32 = 0xFFFFFFFF
        for b in data { crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFFFFFF
    }
}

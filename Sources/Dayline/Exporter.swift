import AppKit
import Categorize
import Domain
import UI

/// "Export" (spec 5.4): every segment with its resolved category, as CSV or
/// JSON. Totals computed from the file match the app's (acceptance test 8).
enum Exporter {
    struct Row: Encodable {
        var start: String
        var end: String
        var seconds: Int64
        var kind: String
        var app: String
        var bundleID: String
        var title: String?
        var host: String?
        var domain: String?
        var category: String?
        var edited: Bool
        var call: Bool
    }

    static func rows(_ segments: [Segment], categorizer: Categorizer) -> [Row] {
        let iso = ISO8601DateFormatter()
        iso.timeZone = .current
        iso.formatOptions = [.withInternetDateTime]
        return segments.map { s in
            let r = s.kind == .active ? categorizer.resolve(s) : nil
            return Row(start: iso.string(from: Date(timeIntervalSince1970: TimeInterval(s.start))),
                       end: iso.string(from: Date(timeIntervalSince1970: TimeInterval(s.end))),
                       seconds: s.duration, kind: s.kind.rawValue, app: s.appName, bundleID: s.appBundleID,
                       title: s.title, host: s.host, domain: s.domain, category: r?.category.name,
                       edited: r?.edited ?? false, call: s.call)
        }
    }

    static func data(_ rows: [Row], format: ExportFormat) throws -> Data {
        switch format {
        case .json:
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            enc.keyEncodingStrategy = .convertToSnakeCase
            return try enc.encode(rows)
        case .csv:
            func field(_ v: String?) -> String {
                guard let v else { return "" }
                return v.contains(where: { ",\"\n\r".contains($0) }) ? "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : v
            }
            var out = "start,end,seconds,kind,app,bundle_id,title,host,domain,category,edited,call\n"
            for r in rows {
                out += [r.start, r.end, String(r.seconds), r.kind, r.app, r.bundleID, r.title, r.host, r.domain, r.category,
                        r.edited ? "1" : "0", r.call ? "1" : "0"].map(field).joined(separator: ",") + "\n"
            }
            return Data(out.utf8)
        }
    }

    /// Asks where to save, then writes. Returns the file, or nil if cancelled.
    static func run(format: ExportFormat, engine: TrackingEngine, window: NSWindow?) {
        let panel = NSSavePanel()
        let stamp = Date().formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "Dayline \(stamp).\(format == .csv ? "csv" : "json")"
        panel.allowedContentTypes = [format == .csv ? .commaSeparatedText : .json]
        let save = {
            guard let url = panel.url else { return }
            do {
                let rows = rows(try engine.database.allSegments(), categorizer: engine.categorizer)
                try data(rows, format: format).write(to: url, options: .atomic)
                Log.line("exported \(rows.count) rows as \(format.rawValue)")
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        if let window {
            panel.beginSheetModal(for: window) { if $0 == .OK { save() } }
        } else if panel.runModal() == .OK {
            save()
        }
    }
}

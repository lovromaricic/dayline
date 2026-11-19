import Domain
import Foundation
import GRDB

/// Applies the segmenter's changes. Keeps the open segment's row id; the row's
/// `end` is rewritten on every tick, so a crash loses at most one tick.
public final class SegmentStore {
    private let db: DaylineDatabase
    public private(set) var openID: Int64?

    public init(database: DaylineDatabase) {
        self.db = database
    }

    public func apply(_ changes: [SegmentChange]) throws {
        guard !changes.isEmpty else { return }
        try db.pool.write { db in
            for change in changes {
                switch change {
                case .begin(let d):
                    let a = d.activity
                    try db.execute(sql: """
                        INSERT INTO segment (start, end, app_bundle_id, app_name, title, host, domain, kind, call)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """, arguments: [d.start, d.start, a?.appBundleID ?? "", a?.appName ?? "", a?.title,
                                         a?.host, a?.domain, d.kind.rawValue, d.call])
                    openID = db.lastInsertedRowID
                case .end(let at):
                    if let id = openID { try db.execute(sql: "UPDATE segment SET end = ? WHERE id = ?", arguments: [at, id]) }
                    openID = nil
                case .discard:
                    if let id = openID { try db.execute(sql: "DELETE FROM segment WHERE id = ?", arguments: [id]) }
                    openID = nil
                case .extend(let to):
                    if let id = openID { try db.execute(sql: "UPDATE segment SET end = ? WHERE id = ?", arguments: [to, id]) }
                }
            }
        }
    }

    /// Segments overlapping [from, to), oldest first.
    public func segments(from: Int64, to: Int64) throws -> [Segment] {
        try db.pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM segment WHERE start < ? AND end > ? OR (start >= ? AND start < ?) ORDER BY start, id
                """, arguments: [to, from, from, to]).map { r in
                Segment(id: r["id"], start: r["start"], end: r["end"],
                              kind: SegmentKind(rawValue: r["kind"]) ?? .active,
                              appBundleID: r["app_bundle_id"], appName: r["app_name"], title: r["title"],
                              host: r["host"], domain: r["domain"], call: r["call"],
                              manualCategoryID: (r["category_source"] as String?) == "manual" ? r["category_id"] : nil,
                              note: r["note"])
            }
        }
    }

    /// Starts of segments whose title, app, site or note contains `query`,
    /// newest first, for search across days; every segment for an empty query.
    /// Matched in Swift, so case is ignored for any letter (SQLite's LIKE only
    /// folds ASCII).
    public func starts(matching query: String) throws -> [Int64] {
        try db.pool.read { db in
            var found: [Int64] = []
            let rows = try Row.fetchCursor(db, sql: "SELECT start, title, app_name, host, note FROM segment ORDER BY start DESC")
            while let r = try rows.next() {
                let fields: [String?] = [r["title"], r["app_name"], r["host"], r["note"]]
                if query.isEmpty || fields.contains(where: { $0?.localizedCaseInsensitiveContains(query) ?? false }) { found.append(r["start"]) }
            }
            return found
        }
    }

    /// "Just this time": pin these segments to a category, or `nil` to undo.
    public func setManualCategory(segmentIDs: [Int64], categoryID: Int64?) throws {
        guard !segmentIDs.isEmpty else { return }
        let marks = segmentIDs.map { _ in "?" }.joined(separator: ",")
        try db.pool.write { db in
            try db.execute(sql: """
                UPDATE segment SET category_id = ?, category_source = ? WHERE id IN (\(marks))
                """, arguments: StatementArguments([categoryID, categoryID == nil ? nil : "manual"] as [DatabaseValueConvertible?]
                                                   + segmentIDs.map { $0 as DatabaseValueConvertible? }))
        }
    }

    /// A block's note, on all of its segments; empty removes it.
    public func setNote(segmentIDs: [Int64], note: String) throws {
        guard !segmentIDs.isEmpty else { return }
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let marks = segmentIDs.map { _ in "?" }.joined(separator: ",")
        try db.pool.write { db in
            try db.execute(sql: "UPDATE segment SET note = ? WHERE id IN (\(marks))",
                           arguments: StatementArguments([text.isEmpty ? nil : text] as [DatabaseValueConvertible?]
                                                         + segmentIDs.map { $0 as DatabaseValueConvertible? }))
        }
    }

    /// "Delete" on a block: its time becomes a gap.
    public func deleteSegments(ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        let marks = ids.map { _ in "?" }.joined(separator: ",")
        try db.pool.write { db in
            try db.execute(sql: "DELETE FROM segment WHERE id IN (\(marks))", arguments: StatementArguments(ids))
        }
    }

    /// End of the newest segment, if any history exists.
    public func lastEnd() throws -> Int64? {
        try db.pool.read { try Int64.fetchOne($0, sql: "SELECT MAX(end) FROM segment") }
    }
}

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
                              manualCategoryID: (r["category_source"] as String?) == "manual" ? r["category_id"] : nil)
            }
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

    /// End of the newest segment, if any history exists.
    public func lastEnd() throws -> Int64? {
        try db.pool.read { try Int64.fetchOne($0, sql: "SELECT MAX(end) FROM segment") }
    }
}

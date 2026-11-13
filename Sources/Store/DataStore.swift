import Domain
import Foundation
import GRDB

/// Privacy & data (spec 5.4): exclusions, retention, size, delete, category merge.
extension DaylineDatabase {
    public struct ExclusionRow: Equatable, Identifiable, Sendable {
        public var id: Int64
        public var kind: Rule.Kind  // .app or .site
        public var pattern: String
    }

    public func exclusionRows() throws -> [ExclusionRow] {
        try pool.read { db in
            try Row.fetchAll(db, sql: "SELECT id, kind, pattern FROM exclusion ORDER BY id").compactMap { r in
                Rule.Kind(rawValue: r["kind"]).map { ExclusionRow(id: r["id"], kind: $0, pattern: r["pattern"]) }
            }
        }
    }

    public func addExclusion(kind: Rule.Kind, pattern: String) throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM exclusion WHERE kind = ? AND pattern = ? COLLATE NOCASE", arguments: [kind.rawValue, pattern])
            try db.execute(sql: "INSERT INTO exclusion (kind, pattern) VALUES (?, ?)", arguments: [kind.rawValue, pattern])
        }
    }

    public func deleteExclusion(id: Int64) throws {
        try pool.write { try $0.execute(sql: "DELETE FROM exclusion WHERE id = ?", arguments: [id]) }
    }

    /// "Keep history for": drop segments that ended before `cutoff`.
    @discardableResult
    public func deleteSegments(endedBefore cutoff: Int64) throws -> Int {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM segment WHERE end < ?", arguments: [cutoff])
            return db.changesCount
        }
    }

    /// Database plus WAL files, in bytes, and the first recorded moment.
    public func storageInfo(url: URL = DaylineDatabase.defaultURL) throws -> (bytes: Int64, since: Int64?) {
        let fm = FileManager.default
        let bytes = ["", "-wal", "-shm"].reduce(Int64(0)) { sum, suffix in
            let size = (try? fm.attributesOfItem(atPath: url.path + suffix)[.size] as? NSNumber)?.int64Value ?? 0
            return sum + size
        }
        let since = try pool.read { try Int64.fetchOne($0, sql: "SELECT MIN(start) FROM segment") }
        return (bytes, since)
    }

    /// "Delete all data": tracked time, rules, exclusions and your categories
    /// go; the seed categories return to their original names and colors.
    /// Preferences (settings table) are kept. The file is compacted after.
    public func deleteAll() throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM segment; DELETE FROM rule; DELETE FROM exclusion;")
            try db.execute(sql: "DELETE FROM setting WHERE key LIKE 'alias.%'")
            try db.execute(sql: "DELETE FROM category WHERE id > ?", arguments: [ActivityCategory.uncategorized.id])
            for (sort, c) in ActivityCategory.defaults.enumerated() {
                try db.execute(sql: "INSERT OR REPLACE INTO category (id, name, color, sort, is_system) VALUES (?, ?, ?, ?, ?)",
                               arguments: [c.id, c.name, c.color, c == .uncategorized ? 99 : sort,
                                           c == .uncategorized ? 1 : 0])
            }
        }
        try pool.writeWithoutTransaction { try $0.execute(sql: "VACUUM") }
        try pool.writeWithoutTransaction { try $0.checkpoint(.truncate) }
    }

    /// Merges `from` into `to`: rules and corrections move over, built-in rules
    /// that pointed at `from` follow via an alias, and `from` is removed.
    /// Deleting a category is merging it into Uncategorized.
    public func mergeCategory(_ from: Int64, into to: Int64) throws {
        guard from != to, from != ActivityCategory.uncategorized.id else { return }
        try pool.write { db in
            try db.execute(sql: "UPDATE rule SET category_id = ? WHERE category_id = ?", arguments: [to, from])
            try db.execute(sql: "UPDATE segment SET category_id = ? WHERE category_id = ? AND category_source = 'manual'",
                           arguments: [to, from])
            // Anything already aliased to `from` now goes to `to`.
            try db.execute(sql: "UPDATE setting SET value = ? WHERE key LIKE 'alias.%' AND value = ?",
                           arguments: [String(to), String(from)])
            try db.execute(sql: "INSERT OR REPLACE INTO setting (key, value) VALUES (?, ?)", arguments: ["alias.\(from)", String(to)])
            try db.execute(sql: "DELETE FROM category WHERE id = ?", arguments: [from])
        }
    }

    /// Removed category id -> where its time goes now.
    public func categoryAliases() throws -> [Int64: Int64] {
        try pool.read { db in
            var map: [Int64: Int64] = [:]
            for r in try Row.fetchAll(db, sql: "SELECT key, value FROM setting WHERE key LIKE 'alias.%'") {
                let key: String = r["key"], value: String = r["value"]
                if let from = Int64(key.dropFirst(6)), let to = Int64(value) { map[from] = to }
            }
            return map
        }
    }

    /// All segments, oldest first, for export.
    public func allSegments() throws -> [Segment] {
        try SegmentStore(database: self).segments(from: 0, to: Int64.max / 2)
    }
}

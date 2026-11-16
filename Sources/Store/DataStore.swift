import CryptoKit
import Domain
import Foundation
import GRDB

/// Privacy & data (spec 5.4): exclusions, retention, size, delete, category merge.
extension DaylineDatabase {
    public struct ExclusionRow: Equatable, Identifiable, Sendable {
        public var id: Int64
        public var kind: Rule.Kind  // .app or .site
        public var pattern: String
        public var mode: ExclusionMode = .skip
    }

    public func exclusionRows() throws -> [ExclusionRow] {
        try pool.read { db in
            try Row.fetchAll(db, sql: "SELECT id, kind, pattern, mode FROM exclusion ORDER BY id").compactMap { r in
                guard let kind = Rule.Kind(rawValue: r["kind"]), let mode = ExclusionMode(rawValue: r["mode"]) else { return nil }
                return ExclusionRow(id: r["id"], kind: kind, pattern: r["pattern"], mode: mode)
            }
        }
    }

    /// One mode per app or site: adding it to one list takes it off the other.
    public func addExclusion(kind: Rule.Kind, pattern: String, mode: ExclusionMode = .skip) throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM exclusion WHERE kind = ? AND pattern = ? COLLATE NOCASE", arguments: [kind.rawValue, pattern])
            try db.execute(sql: "INSERT INTO exclusion (kind, pattern, mode) VALUES (?, ?, ?)",
                           arguments: [kind.rawValue, pattern, mode.rawValue])
        }
    }

    /// The stable stand-in for a hidden title: "Hidden title A", "Hidden title B"…
    /// per app or site (`scope`). The same title always gets the same label;
    /// only a keyed hash of it is stored, never the title.
    public func hiddenTitle(_ title: String, scope: String) throws -> String {
        try pool.write { db in
            var secret = try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = 'titles.secret'")
            if secret == nil {
                let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).base64EncodedString() }
                try db.execute(sql: "INSERT INTO setting (key, value) VALUES ('titles.secret', ?)", arguments: [key])
                secret = key
            }
            let mac = HMAC<SHA256>.authenticationCode(for: Data(Titles.normalize(title).utf8),
                                                      using: SymmetricKey(data: Data(base64Encoded: secret!) ?? Data()))
            let key = scope + "|" + Data(mac).prefix(12).base64EncodedString()
            if let label = try String.fetchOne(db, sql: "SELECT label FROM title_label WHERE key = ?", arguments: [key]) {
                return label
            }
            let n = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM title_label WHERE key LIKE ?", arguments: [scope + "|%"]) ?? 0
            let label = "Hidden title " + Self.letters(n)
            try db.execute(sql: "INSERT INTO title_label (key, label) VALUES (?, ?)", arguments: [key, label])
            return label
        }
    }

    /// A, B, … Z, AA, AB, …
    static func letters(_ n: Int) -> String {
        let a = Character("A").asciiValue!
        let last = String(UnicodeScalar(a + UInt8(n % 26)))
        return n < 26 ? last : letters(n / 26 - 1) + last
    }

    /// Replaces titles already saved for an app (bundle id) or site (and its
    /// subdomains) with their hidden labels. Returns how many segments changed.
    @discardableResult
    public func hideSavedTitles(kind: Rule.Kind, pattern: String) throws -> Int {
        let match = kind == .app ? "app_bundle_id = ?" : "(host = ? OR host LIKE '%.' || ?)"
        let args: StatementArguments = kind == .app ? [pattern] : [pattern, pattern]
        let rows = try pool.read { db in
            try Row.fetchAll(db, sql: "SELECT DISTINCT title, app_bundle_id, domain FROM segment WHERE title IS NOT NULL AND \(match)",
                             arguments: args)
        }
        var changed = 0
        for r in rows {
            let title: String = r["title"]
            let scope: String = r["domain"] ?? r["app_bundle_id"]
            if title.hasPrefix("Hidden title ") { continue }
            let label = try hiddenTitle(title, scope: scope)
            try pool.write { db in
                try db.execute(sql: "UPDATE segment SET title = ? WHERE title = ? AND \(match)", arguments: [label, title] + args)
                changed += db.changesCount
            }
        }
        return changed
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
            try db.execute(sql: "DELETE FROM segment; DELETE FROM rule; DELETE FROM exclusion; DELETE FROM title_label;")
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

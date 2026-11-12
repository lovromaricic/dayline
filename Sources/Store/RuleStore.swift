import Domain
import Foundation
import GRDB

/// Categories and user rules (spec 3, 4).
extension DaylineDatabase {
    public func categories() throws -> [ActivityCategory] {
        try pool.read { db in
            try Row.fetchAll(db, sql: "SELECT id, name, color FROM category ORDER BY sort, id").map {
                ActivityCategory(id: $0["id"], name: $0["name"], color: $0["color"])
            }
        }
    }

    @discardableResult
    public func addCategory(name: String, color: String) throws -> ActivityCategory {
        try pool.write { db in
            let sort = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort), 0) + 1 FROM category WHERE is_system = 0") ?? 0
            try db.execute(sql: "INSERT INTO category (name, color, sort) VALUES (?, ?, ?)", arguments: [name, color, sort])
            return ActivityCategory(id: db.lastInsertedRowID, name: name, color: color)
        }
    }

    public func updateCategory(_ c: ActivityCategory) throws {
        try pool.write { db in
            try db.execute(sql: "UPDATE category SET name = ?, color = ? WHERE id = ?", arguments: [c.name, c.color, c.id])
        }
    }

    public func rules() throws -> [Rule] {
        try pool.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM rule ORDER BY created_at DESC, id DESC").compactMap { r in
                guard let kind = Rule.Kind(rawValue: r["kind"]), let origin = Rule.Origin(rawValue: r["origin"]) else { return nil }
                return Rule(id: r["id"], kind: kind, pattern: r["pattern"], categoryID: r["category_id"],
                            origin: origin, createdAt: r["created_at"])
            }
        }
    }

    /// Adds a rule; an existing rule with the same kind and pattern is replaced,
    /// so correcting the same site twice leaves one rule.
    @discardableResult
    public func addRule(kind: Rule.Kind, pattern: String, categoryID: Int64, origin: Rule.Origin, at: Int64) throws -> Rule {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM rule WHERE kind = ? AND pattern = ? COLLATE NOCASE", arguments: [kind.rawValue, pattern])
            try db.execute(sql: "INSERT INTO rule (kind, pattern, category_id, origin, created_at) VALUES (?, ?, ?, ?, ?)",
                           arguments: [kind.rawValue, pattern, categoryID, origin.rawValue, at])
            return Rule(id: db.lastInsertedRowID, kind: kind, pattern: pattern, categoryID: categoryID, origin: origin, createdAt: at)
        }
    }

    public func setRuleCategory(id: Int64, categoryID: Int64) throws {
        try pool.write { try $0.execute(sql: "UPDATE rule SET category_id = ? WHERE id = ?", arguments: [categoryID, id]) }
    }

    public func deleteRule(id: Int64) throws {
        try pool.write { try $0.execute(sql: "DELETE FROM rule WHERE id = ?", arguments: [id]) }
    }

    /// Apps seen recently, for the Add rule picker: (bundle id, name), most used first.
    public func recentApps(since: Int64) throws -> [(String, String)] {
        try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT app_bundle_id, app_name FROM segment
                WHERE kind = 'active' AND start >= ? AND app_bundle_id != ''
                GROUP BY app_bundle_id ORDER BY SUM(end - start) DESC LIMIT 40
                """, arguments: [since]).map { ($0["app_bundle_id"], $0["app_name"]) }
        }
    }
}

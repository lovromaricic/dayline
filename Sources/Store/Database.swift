import Domain
import Foundation
import GRDB

/// The single SQLite file. Everything stays on this Mac.
public final class DaylineDatabase {
    public let pool: DatabasePool

    /// ~/Library/Application Support/Dayline/dayline.sqlite, or $DAYLINE_DB.
    public static var defaultURL: URL {
        if let path = ProcessInfo.processInfo.environment["DAYLINE_DB"] { return URL(fileURLWithPath: path) }
        return URL.applicationSupportDirectory.appending(path: "Dayline/dayline.sqlite")
    }

    public init(url: URL = DaylineDatabase.defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        pool = try DatabasePool(path: url.path)
        try Self.migrator.migrate(pool)
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            // Spec section 3, plus `host` (full hostname shown in the UI; `domain`
            // is the registrable domain used by rules) and `call` (mic/camera in use).
            try db.execute(sql: """
                CREATE TABLE category (
                  id INTEGER PRIMARY KEY, name TEXT UNIQUE, color TEXT, sort INTEGER, is_system INTEGER DEFAULT 0);
                CREATE TABLE segment (
                  id INTEGER PRIMARY KEY,
                  start INTEGER NOT NULL,
                  end INTEGER NOT NULL,
                  app_bundle_id TEXT NOT NULL,
                  app_name TEXT NOT NULL,
                  title TEXT,
                  host TEXT,
                  domain TEXT,
                  kind TEXT NOT NULL,
                  call INTEGER NOT NULL DEFAULT 0,
                  category_id INTEGER REFERENCES category(id),
                  category_source TEXT);
                CREATE INDEX segment_start ON segment(start);
                CREATE TABLE rule (
                  id INTEGER PRIMARY KEY,
                  kind TEXT NOT NULL,
                  pattern TEXT NOT NULL,
                  category_id INTEGER NOT NULL REFERENCES category(id),
                  origin TEXT NOT NULL,
                  created_at INTEGER NOT NULL);
                CREATE TABLE exclusion (id INTEGER PRIMARY KEY, kind TEXT NOT NULL, pattern TEXT NOT NULL);
                CREATE TABLE setting (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                """)
            for (sort, c) in ActivityCategory.seed.enumerated() {
                try db.execute(sql: "INSERT INTO category (name, color, sort) VALUES (?, ?, ?)", arguments: [c.name, c.color, sort])
            }
            try db.execute(sql: "INSERT INTO category (name, color, sort, is_system) VALUES ('Uncategorized', '#62666D', 99, 1)")
        }
        m.registerMigration("v2-entertainment") { db in
            // Entertainment needs id 8, which built-in rules point at. A category
            // of yours already called Entertainment becomes it; one of yours
            // that holds id 8 under another name moves to a free id.
            let e = ActivityCategory.entertainment
            let named = try Int64.fetchOne(db, sql: "SELECT id FROM category WHERE name = ? COLLATE NOCASE", arguments: [e.name])
            if named != e.id, try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM category WHERE id = ?)", arguments: [e.id]) == true {
                let free = try Int64.fetchOne(db, sql: "SELECT MAX(id) + 1 FROM category") ?? e.id + 1
                try renumberCategory(db, from: e.id, to: free)
            }
            if let named, named != e.id {
                try renumberCategory(db, from: named, to: e.id)
            } else if named == nil {
                try db.execute(sql: "INSERT INTO category (id, name, color, sort) VALUES (?, ?, ?, ?)",
                               arguments: [e.id, e.name, e.color, ActivityCategory.seed.count])
            }
        }
        return m
    }

    /// Moves a category to a new id, with everything that points at it.
    private static func renumberCategory(_ db: GRDB.Database, from: Int64, to: Int64) throws {
        try db.execute(sql: "PRAGMA defer_foreign_keys = ON")
        try db.execute(sql: "UPDATE category SET id = ? WHERE id = ?", arguments: [to, from])
        try db.execute(sql: "UPDATE segment SET category_id = ? WHERE category_id = ?", arguments: [to, from])
        try db.execute(sql: "UPDATE rule SET category_id = ? WHERE category_id = ?", arguments: [to, from])
        try db.execute(sql: "UPDATE setting SET value = ? WHERE key LIKE 'alias.%' AND value = ?", arguments: [String(to), String(from)])
        try db.execute(sql: "UPDATE setting SET key = ? WHERE key = ?", arguments: ["alias.\(to)", "alias.\(from)"])
    }

    public func setting(_ key: String) throws -> String? {
        try pool.read { try String.fetchOne($0, sql: "SELECT value FROM setting WHERE key = ?", arguments: [key]) }
    }

    /// `nil` removes the key.
    public func setSetting(_ key: String, _ value: String?) throws {
        try pool.write { db in
            if let value {
                try db.execute(sql: "INSERT INTO setting (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                               arguments: [key, value])
            } else {
                try db.execute(sql: "DELETE FROM setting WHERE key = ?", arguments: [key])
            }
        }
    }

    public func exclusions() throws -> Exclusions {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT kind, pattern FROM exclusion")
            return Exclusions(
                apps: Set(rows.filter { $0["kind"] == "app" }.map { $0["pattern"] }),
                sites: rows.filter { $0["kind"] == "site" }.map { $0["pattern"] })
        }
    }
}

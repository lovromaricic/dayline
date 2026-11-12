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
        return m
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

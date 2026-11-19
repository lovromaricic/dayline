import Domain
import Foundation
import GRDB

/// Clients, projects and what each project learned ("Auto-adds").
extension DaylineDatabase {
    public func clients() throws -> [Client] {
        try pool.read { db in
            try Row.fetchAll(db, sql: "SELECT id, name FROM client ORDER BY name COLLATE NOCASE, id").map {
                Client(id: $0["id"], name: $0["name"])
            }
        }
    }

    /// Projects with their client's name, grouped by client (no client last).
    public func projects() throws -> [Project] {
        try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT p.id, p.name, p.client_id, c.name AS client_name FROM project p
                LEFT JOIN client c ON c.id = p.client_id
                ORDER BY c.name IS NULL, c.name COLLATE NOCASE, p.name COLLATE NOCASE, p.id
                """).map {
                Project(id: $0["id"], name: $0["name"], clientID: $0["client_id"], clientName: $0["client_name"])
            }
        }
    }

    /// Adding a client that exists (any case) returns that one.
    @discardableResult
    public func addClient(name: String, at: Int64) throws -> Client {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return try pool.write { db in
            if let row = try Row.fetchOne(db, sql: "SELECT id, name FROM client WHERE name = ? COLLATE NOCASE", arguments: [name]) {
                return Client(id: row["id"], name: row["name"])
            }
            try db.execute(sql: "INSERT INTO client (name, created_at) VALUES (?, ?)", arguments: [name, at])
            return Client(id: db.lastInsertedRowID, name: name)
        }
    }

    public func renameClient(id: Int64, name: String) throws {
        try pool.write { try $0.execute(sql: "UPDATE client SET name = ? WHERE id = ?", arguments: [name, id]) }
    }

    /// Its projects stay, without a client.
    public func deleteClient(id: Int64) throws {
        try pool.write { db in
            try db.execute(sql: "UPDATE project SET client_id = NULL WHERE client_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM client WHERE id = ?", arguments: [id])
        }
    }

    @discardableResult
    public func addProject(name: String, clientID: Int64?, at: Int64) throws -> Project {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return try pool.write { db in
            try db.execute(sql: "INSERT INTO project (name, client_id, created_at) VALUES (?, ?, ?)", arguments: [name, clientID, at])
            let client = try clientID.flatMap { try String.fetchOne(db, sql: "SELECT name FROM client WHERE id = ?", arguments: [$0]) }
            return Project(id: db.lastInsertedRowID, name: name, clientID: clientID, clientName: client)
        }
    }

    public func renameProject(id: Int64, name: String) throws {
        try pool.write { try $0.execute(sql: "UPDATE project SET name = ? WHERE id = ?", arguments: [name, id]) }
    }

    public func setProjectClient(id: Int64, clientID: Int64?) throws {
        try pool.write { try $0.execute(sql: "UPDATE project SET client_id = ? WHERE id = ?", arguments: [clientID, id]) }
    }

    /// Its blocks go back to No project and what it learned is removed; the
    /// tracked time itself stays.
    public func deleteProject(id: Int64) throws {
        try pool.write { db in
            try db.execute(sql: "UPDATE segment SET project_id = NULL WHERE project_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM project_rule WHERE project_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM project WHERE id = ?", arguments: [id])
        }
    }

    /// Newest first.
    public func projectRules() throws -> [ProjectRule] {
        try pool.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM project_rule ORDER BY created_at DESC, id DESC").compactMap { r in
                guard let kind = Rule.Kind(rawValue: r["kind"]) else { return nil }
                return ProjectRule(id: r["id"], projectID: r["project_id"], kind: kind, pattern: r["pattern"], createdAt: r["created_at"])
            }
        }
    }

    /// The same title or site taught again moves to the new project.
    @discardableResult
    public func addProjectRule(projectID: Int64, kind: Rule.Kind, pattern: String, at: Int64) throws -> ProjectRule {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM project_rule WHERE kind = ? AND pattern = ? COLLATE NOCASE", arguments: [kind.rawValue, pattern])
            try db.execute(sql: "INSERT INTO project_rule (project_id, kind, pattern, created_at) VALUES (?, ?, ?, ?)",
                           arguments: [projectID, kind.rawValue, pattern, at])
            return ProjectRule(id: db.lastInsertedRowID, projectID: projectID, kind: kind, pattern: pattern, createdAt: at)
        }
    }

    public func deleteProjectRule(id: Int64) throws {
        try pool.write { try $0.execute(sql: "DELETE FROM project_rule WHERE id = ?", arguments: [id]) }
    }

    public func projectResolver() throws -> ProjectResolver {
        ProjectResolver(projects: try projects(), rules: try projectRules())
    }
}

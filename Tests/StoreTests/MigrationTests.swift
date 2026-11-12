import Domain
import Foundation
import GRDB
import Testing
@testable import Store

@Suite struct MigrationTests {
    /// A database as v1 left it, with `setup` run on top, then fully migrated.
    func migrated(_ setup: (GRDB.Database) throws -> Void) throws -> DaylineDatabase {
        let url = FileManager.default.temporaryDirectory.appending(path: "dayline-mig-\(UUID().uuidString).sqlite")
        let pool = try DatabasePool(path: url.path)
        try DaylineDatabase.migrator.migrate(pool, upTo: "v1")
        try pool.write(setup)
        try pool.close()
        return try DaylineDatabase(url: url)
    }

    func segment(_ db: GRDB.Database, category: Int64) throws {
        try db.execute(sql: """
            INSERT INTO segment (start, end, app_bundle_id, app_name, kind, category_id, category_source)
            VALUES (0, 60, 'x', 'x', 'active', ?, 'manual')
            """, arguments: [category])
    }

    @Test func freshDatabaseHasEntertainment() throws {
        let d = try migrated { _ in }
        #expect(try d.categories() == ActivityCategory.defaults)
    }

    @Test func yourCategoryOnId8MovesAside() throws {
        let d = try migrated { db in
            try db.execute(sql: "INSERT INTO category (id, name, color, sort) VALUES (8, 'Games', '#FF5F5F', 7)")
            try segment(db, category: 8)
            try db.execute(sql: "INSERT INTO rule (kind, pattern, category_id, origin, created_at) VALUES ('app', 'x', 8, 'user', 0)")
        }
        let cats = try d.categories()
        let games = try #require(cats.first { $0.name == "Games" })
        #expect(games.id == 9)
        #expect(cats.contains(.entertainment))
        #expect(try d.rules().map(\.categoryID) == [9])
        let segCat = try d.pool.read { try Int64.fetchOne($0, sql: "SELECT category_id FROM segment") }
        #expect(segCat == 9)
    }

    @Test func yourEntertainmentBecomesTheBuiltIn() throws {
        let d = try migrated { db in
            try db.execute(sql: "INSERT INTO category (id, name, color, sort) VALUES (9, 'Entertainment', '#B4E04E', 7)")
            try segment(db, category: 9)
        }
        let cats = try d.categories()
        #expect(cats.filter { $0.name == "Entertainment" }.map(\.id) == [8])
        let segCat = try d.pool.read { try Int64.fetchOne($0, sql: "SELECT category_id FROM segment") }
        #expect(segCat == 8)
    }
}

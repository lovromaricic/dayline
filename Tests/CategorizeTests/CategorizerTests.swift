import Testing
import Domain
@testable import Categorize

@Suite struct CategorizerTests {
    func chrome(_ host: String, title: String? = nil, manual: Int64? = nil, call: Bool = false) -> Segment {
        Segment(id: 0, start: 0, end: 1, kind: .active, appBundleID: "com.google.Chrome", appName: "Google Chrome",
                title: title, host: host, domain: PublicSuffix.shared.registrableDomain(of: host), call: call,
                manualCategoryID: manual)
    }
    func app(_ id: String, title: String? = nil, call: Bool = false) -> Segment {
        Segment(id: 0, start: 0, end: 1, kind: .active, appBundleID: id, appName: id, title: title, call: call)
    }
    func rule(_ kind: Rule.Kind, _ pattern: String, _ c: ActivityCategory, at: Int64 = 0, id: Int64 = 1) -> Rule {
        Rule(id: id, kind: kind, pattern: pattern, categoryID: c.id, origin: .user, createdAt: at)
    }

    @Test func builtinsAndFallbacks() {
        let c = Categorizer()
        #expect(c.category(for: chrome("meet.google.com")) == .meetings)
        #expect(c.category(for: chrome("github.com")) == .development)
        #expect(c.category(for: chrome("news.bbc.co.uk")) == .browsing)
        #expect(c.category(for: app("com.apple.dt.Xcode")) == .development)
        #expect(c.category(for: app("com.example.unknown")) == .uncategorized)
        // A call fills in Meetings only where the app has no category of its
        // own, or is a chat app; Figma or GitHub during a call keep theirs.
        #expect(c.category(for: chrome("github.com", call: true)) == .development)
        #expect(c.category(for: app("com.figma.Desktop", call: true)) == .design)
        #expect(c.category(for: app("com.example.unknown", call: true)) == .meetings)
        #expect(c.category(for: app("com.tinyspeck.slackmacgap", call: true)) == .meetings)
        // A calendar is planning; during a call it becomes the meeting.
        #expect(c.category(for: chrome("calendar.google.com")) == .communication)
        #expect(c.category(for: chrome("calendar.google.com", call: true)) == .meetings)
        // Installed web apps have no address; their title says what they are.
        let slackApp = Segment(id: 0, start: 0, end: 1, kind: .active, appBundleID: "com.google.Chrome", appName: "Google Chrome",
                               title: "Alex, Sam - Acme - Slack")
        #expect(c.category(for: slackApp) == .communication)
        // Teams is chat until a call starts.
        #expect(c.category(for: app("com.microsoft.teams2")) == .communication)
        #expect(c.category(for: app("com.microsoft.teams2", call: true)) == .meetings)
    }

    @Test func appStoreCategoryFallback() {
        var c = Categorizer()
        c.appCategoryType = { $0 == "com.example.paint" ? "public.app-category.graphics-design" : nil }
        #expect(c.category(for: app("com.example.paint")) == .design)
    }

    @Test func siteRuleMatchesSubdomainsAndBeatsBuiltins() {
        let c = Categorizer(rules: [rule(.site, "apple.com", .design)])
        let r = c.resolve(chrome("developer.apple.com"))
        #expect(r.category == .design)
        #expect(r.guess == .development)
        #expect(r.edited)
        #expect(c.category(for: chrome("notapple.com")) == .uncategorized || c.category(for: chrome("notapple.com")) == .browsing)
    }

    @Test func siteRulesBeforeAppRulesBeforeTitleRules() {
        let c = Categorizer(rules: [
            rule(.titleContains, "standup", .meetings, at: 30, id: 1),
            rule(.app, "com.google.Chrome", .writing, at: 20, id: 2),
            rule(.site, "github.com", .design, at: 10, id: 3),
        ])
        #expect(c.category(for: chrome("github.com", title: "Standup notes")) == .design)
        #expect(c.category(for: chrome("example.com", title: "Standup notes")) == .writing)
        #expect(c.category(for: app("com.apple.Notes", title: "Daily STANDUP")) == .meetings)
    }

    @Test func newestRuleWinsWithinAKind() {
        let c = Categorizer(rules: [rule(.site, "github.com", .design, at: 10, id: 1),
                                    rule(.site, "github.com", .writing, at: 20, id: 2)])
        #expect(c.category(for: chrome("github.com")) == .writing)
    }

    @Test func manualBeatsRules() {
        let c = Categorizer(rules: [rule(.site, "github.com", .design)])
        #expect(c.category(for: chrome("github.com", manual: ActivityCategory.meetings.id)) == .meetings)
        #expect(c.resolve(chrome("github.com", manual: ActivityCategory.meetings.id), ignoringManual: true).category == .design)
    }

    @Test func renamedCategoryKeepsItsRules() {
        let renamed = ActivityCategory(id: ActivityCategory.development.id, name: "Code", color: "#123456")
        let c = Categorizer(categories: [renamed, .uncategorized])
        #expect(c.category(for: app("com.apple.dt.Xcode")).name == "Code")
    }

    @Test func builtinListIsSubstantial() {
        #expect(BuiltinRules.count >= 150)
    }
}

extension CategorizerTests {
    @Test func mergedSeedCategoryFollowsAlias() {
        var c = Categorizer(categories: [.development, .writing, .uncategorized])
        c.aliases = [ActivityCategory.design.id: ActivityCategory.writing.id]
        #expect(c.category(for: app("com.figma.Desktop")) == .writing)
        c.aliases = [:]
        // A deleted seed with no alias falls back to Uncategorized.
        #expect(c.category(for: app("com.figma.Desktop")) == .uncategorized)
    }
}

extension CategorizerTests {
    @Test func entertainmentAppsSitesAndTypes() {
        var c = Categorizer()
        c.appCategoryType = { $0 == "com.example.game" ? "public.app-category.puzzle-games" : nil }
        let music = Segment(id: 1, start: 0, end: 60, kind: .active, appBundleID: "com.apple.Music", appName: "Music", title: nil, domain: nil)
        let yt = Segment(id: 2, start: 0, end: 60, kind: .active, appBundleID: "com.google.Chrome", appName: "Google Chrome",
                         title: "Video", host: "www.youtube.com", domain: "youtube.com")
        let game = Segment(id: 3, start: 0, end: 60, kind: .active, appBundleID: "com.example.game", appName: "Game", title: nil, domain: nil)
        #expect(c.resolve(music).category == .entertainment)
        #expect(c.resolve(yt).category == .entertainment)
        #expect(c.resolve(game).category == .entertainment)
    }
}

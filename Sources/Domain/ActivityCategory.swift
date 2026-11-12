import Foundation

/// A row of the `category` table. Identity is `id`; name and color can change.
public struct ActivityCategory: Hashable, Identifiable, Sendable {
    public var id: Int64
    public var name: String
    /// "#RRGGBB"
    public var color: String

    public init(id: Int64, name: String, color: String) {
        self.id = id
        self.name = name
        self.color = color
    }

    // Seed rows; ids match the insert order of the v1 migration.
    public static let development = ActivityCategory(id: 1, name: "Development", color: "#4EA7FC")
    public static let design = ActivityCategory(id: 2, name: "Design", color: "#FC7840")
    public static let meetings = ActivityCategory(id: 3, name: "Meetings", color: "#E8789E")
    public static let writing = ActivityCategory(id: 4, name: "Writing and Docs", color: "#27A644")
    public static let communication = ActivityCategory(id: 5, name: "Communication", color: "#00B8CC")
    public static let browsing = ActivityCategory(id: 6, name: "Browsing and research", color: "#F0BF00")
    public static let uncategorized = ActivityCategory(id: 7, name: "Uncategorized", color: "#62666D")

    /// Seed order (spec section 3). Uncategorized is the system category.
    public static let seed: [ActivityCategory] = [.development, .design, .meetings, .writing, .communication, .browsing]

    /// Colors offered for new categories: the seed hues plus a few more.
    public static let palette = ["#4EA7FC", "#FC7840", "#E8789E", "#27A644", "#00B8CC", "#F0BF00",
                                 "#9B7CFF", "#5E6AD2", "#B4E04E", "#FF5F5F", "#D9A066", "#8A8F98"]
}

/// A user rule (spec 3, 4). Site rules match the host or any subdomain.
public struct Rule: Equatable, Identifiable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case site, app, titleContains = "title_contains"

        public var label: String {
            switch self {
            case .site: "Site"
            case .app: "App"
            case .titleContains: "Window title contains"
            }
        }
    }

    public enum Origin: String, Sendable {
        case user, correction
    }

    public var id: Int64
    public var kind: Kind
    /// Host for site, bundle id for app, text for title_contains.
    public var pattern: String
    public var categoryID: Int64
    public var origin: Origin
    public var createdAt: Int64

    public init(id: Int64, kind: Kind, pattern: String, categoryID: Int64, origin: Origin, createdAt: Int64) {
        self.id = id
        self.kind = kind
        self.pattern = pattern
        self.categoryID = categoryID
        self.origin = origin
        self.createdAt = createdAt
    }

    public func matches(_ s: Segment) -> Bool {
        switch kind {
        case .site:
            let p = pattern.lowercased()
            guard let host = s.host else { return false }
            return host == p || host.hasSuffix("." + p)
        case .app:
            return s.appBundleID == pattern
        case .titleContains:
            return s.title?.localizedCaseInsensitiveContains(pattern) ?? false
        }
    }
}

/// How a segment got its category.
public struct CategoryResolution: Equatable, Sendable {
    public var category: ActivityCategory
    /// What Dayline would pick without your rules or corrections.
    public var guess: ActivityCategory
    /// A rule of yours or a manual correction decided it.
    public var edited: Bool

    public init(category: ActivityCategory, guess: ActivityCategory, edited: Bool) {
        self.category = category
        self.guess = guess
        self.edited = edited
    }
}

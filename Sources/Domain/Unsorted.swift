import Foundation

/// An app or site whose time landed in Uncategorized ("Needs a category",
/// spec 5.4). One row per app or site, not per block, so a single pick (which
/// adds a rule) sorts all of its time, past and future.
public struct Unsorted: Equatable, Identifiable, Sendable {
    /// .site for browser blocks with a site, .app otherwise; the rule it becomes.
    public var kind: Rule.Kind
    /// Registrable domain or bundle id, as a rule pattern.
    public var pattern: String
    public var name: String
    /// The browser, for sites.
    public var via: String?
    public var blocks: Int
    public var total: Int64

    public var id: String { "\(kind.rawValue):\(pattern)" }

    public init(kind: Rule.Kind, pattern: String, name: String, via: String?, blocks: Int, total: Int64) {
        self.kind = kind
        self.pattern = pattern
        self.name = name
        self.via = via
        self.blocks = blocks
        self.total = total
    }

    /// Less than this in the period is not worth asking about.
    public static let minimum: Int64 = 60

    /// Largest first. Blocks you put in Uncategorized yourself are left alone.
    public static func collect(_ reports: [DayReport]) -> [Unsorted] {
        var byID: [String: Unsorted] = [:]
        for r in reports {
            for b in r.blocks where b.category.id == ActivityCategory.uncategorized.id && !b.edited {
                let site = b.domain ?? b.host
                var u = Unsorted(kind: site == nil ? .app : .site, pattern: site ?? b.appBundleID,
                                 name: site ?? b.appName, via: site == nil ? nil : b.appName, blocks: 0, total: 0)
                u = byID[u.id] ?? u
                u.blocks += 1
                u.total += b.duration
                byID[u.id] = u
            }
        }
        return byID.values.filter { $0.total >= minimum }
            .sorted { $0.total != $1.total ? $0.total > $1.total : $0.name < $1.name }
    }
}

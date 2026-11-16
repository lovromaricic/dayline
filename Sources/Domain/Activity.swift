import Foundation

/// What the user is looking at right now: the frontmost app and, for
/// browsers, the tab title and site.
public struct Activity: Equatable, Sendable {
    public var appBundleID: String
    public var appName: String
    public var title: String?
    /// Full hostname without "www.", e.g. "developer.apple.com". Shown in the UI.
    public var host: String?
    /// Registrable domain, e.g. "apple.com". Used by site rules and exclusions.
    public var domain: String?

    public init(appBundleID: String, appName: String, title: String? = nil, host: String? = nil, domain: String? = nil) {
        self.appBundleID = appBundleID
        self.appName = appName
        self.title = title
        self.host = host
        self.domain = domain
    }

    /// Browser activity. Only http(s) URLs have a site; the path is never kept.
    public static func browser(appBundleID: String, appName: String, title: String?, url: URL?) -> Activity {
        var host: String?
        if let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
           var h = url.host(percentEncoded: false)?.lowercased(), !h.isEmpty {
            if h.hasPrefix("www.") { h.removeFirst(4) }
            host = h
        }
        return Activity(appBundleID: appBundleID, appName: appName, title: title, host: host,
                        domain: host.map(PublicSuffix.shared.registrableDomain(of:)))
    }

    /// Two activities with the same identity belong to one segment, so badge
    /// counts flipping in a title ("(3) Inbox") do not split it.
    public func isSameSegment(as other: Activity) -> Bool {
        appBundleID == other.appBundleID && host == other.host
            && title.map(Titles.normalize) == other.title.map(Titles.normalize)
    }
}

public enum SegmentKind: String, Sendable {
    case active, away, untracked
}

/// A stored segment: a contiguous slice of attention.
public struct Segment: Equatable, Sendable {
    public var id: Int64
    public var start: Int64
    public var end: Int64
    public var kind: SegmentKind
    public var appBundleID: String
    public var appName: String
    public var title: String?
    public var host: String?
    public var domain: String?
    public var call: Bool
    /// Set by a manual correction ("Just this time"); nil otherwise.
    public var manualCategoryID: Int64?
    /// What you wrote on the block this segment is part of.
    public var note: String?
    /// Inside a call long enough to count as one Meetings block. Set by
    /// DayReport, never stored.
    public var wholeCall = false

    public init(id: Int64, start: Int64, end: Int64, kind: SegmentKind, appBundleID: String = "", appName: String = "",
                title: String? = nil, host: String? = nil, domain: String? = nil, call: Bool = false,
                manualCategoryID: Int64? = nil, note: String? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.kind = kind
        self.appBundleID = appBundleID
        self.appName = appName
        self.title = title
        self.host = host
        self.domain = domain
        self.call = call
        self.manualCategoryID = manualCategoryID
        self.note = note
    }

    public var duration: Int64 { end - start }
}

/// A segment as the segmenter opens it. The store assigns ids and end times.
public struct SegmentDraft: Equatable, Sendable {
    public var start: Int64
    public var kind: SegmentKind
    /// Set for `active` only.
    public var activity: Activity?
    /// The mic or camera was in use (spec 2.1, "Calls").
    public var call: Bool

    public init(start: Int64, kind: SegmentKind, activity: Activity? = nil, call: Bool = false) {
        self.start = start
        self.kind = kind
        self.activity = activity
        self.call = call
    }
}

/// What Privacy keeps of an app or site: nothing ("Don't track"), or its
/// time without the titles ("Never save titles for").
public enum ExclusionMode: String, Sendable {
    case skip
    case titles
}

/// Excluded apps and sites are treated as if they did not happen; apps and
/// sites with hidden titles keep their time but never their titles.
public struct Exclusions: Sendable {
    public var apps: Set<String>
    public var sites: [String]
    public var titleApps: Set<String>
    public var titleSites: [String]

    public init(apps: Set<String> = [], sites: [String] = [], titleApps: Set<String> = [], titleSites: [String] = []) {
        self.apps = apps
        self.sites = sites.map { $0.lowercased() }
        self.titleApps = titleApps
        self.titleSites = titleSites.map { $0.lowercased() }
    }

    public func excludes(_ a: Activity) -> Bool { Self.matches(a, apps: apps, sites: sites) }

    public func hidesTitle(_ a: Activity) -> Bool { Self.matches(a, apps: titleApps, sites: titleSites) }

    private static func matches(_ a: Activity, apps: Set<String>, sites: [String]) -> Bool {
        if apps.contains(a.appBundleID) { return true }
        guard let host = a.host else { return false }
        return sites.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

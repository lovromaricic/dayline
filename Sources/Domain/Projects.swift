import Foundation

/// Who a project is for (Erste). Optional: a project can have no client.
public struct Client: Equatable, Hashable, Identifiable, Sendable {
    public var id: Int64
    public var name: String
    /// ISO code ("EUR"); nil is your Mac's currency.
    public var currency: String?
    /// Per hour, for every project unless a project has its own.
    public var rate: Double?

    public init(id: Int64, name: String, currency: String? = nil, rate: Double? = nil) {
        self.id = id
        self.name = name
        self.currency = currency
        self.rate = rate
    }
}

/// Your Mac's currency, for clients that have none set.
public let defaultCurrency = Locale.current.currency?.identifier ?? "EUR"

/// What a block belongs to (Krediti). A block has one project or none; the
/// client follows from the project.
public struct Project: Equatable, Hashable, Identifiable, Sendable {
    public var id: Int64
    public var name: String
    public var clientID: Int64?
    /// The client's name, for "Erste · Krediti".
    public var clientName: String?
    /// Its own rate, over the client's.
    public var rate: Double?
    public var clientRate: Double?
    /// The client's currency; nil is your Mac's.
    public var clientCurrency: String?
    /// Finished: hidden from pickers, and its rules stop adding new work.
    public var archivedAt: Int64?

    public init(id: Int64, name: String, clientID: Int64? = nil, clientName: String? = nil,
                rate: Double? = nil, clientRate: Double? = nil, clientCurrency: String? = nil, archivedAt: Int64? = nil) {
        self.id = id
        self.name = name
        self.clientID = clientID
        self.clientName = clientName
        self.rate = rate
        self.clientRate = clientRate
        self.clientCurrency = clientCurrency
        self.archivedAt = archivedAt
    }

    public var isArchived: Bool { archivedAt != nil }

    /// What an hour costs: its own rate, else its client's; nil shows hours only.
    public var hourlyRate: Double? { rate ?? clientRate }
    public var currency: String { clientCurrency ?? defaultCurrency }

    /// "Erste · Krediti", or "Dayline" without a client.
    public var fullName: String { clientName.map { "\($0) · \(name)" } ?? name }
}

/// "Auto-adds": a title, site or app that puts blocks in a project by itself.
public struct ProjectRule: Equatable, Identifiable, Sendable {
    public var id: Int64
    public var projectID: Int64
    public var kind: Rule.Kind
    public var pattern: String
    public var createdAt: Int64

    public init(id: Int64, projectID: Int64, kind: Rule.Kind, pattern: String, createdAt: Int64) {
        self.id = id
        self.projectID = projectID
        self.kind = kind
        self.pattern = pattern
        self.createdAt = createdAt
    }

    public func matches(_ s: Segment) -> Bool {
        kind.matches(pattern, s)
    }
}

/// A segment's project: picked by hand, else the newest matching rule.
/// Segment.manualProjectID 0 means "No project" picked by hand, which also
/// beats the rules.
public struct ProjectResolver: Sendable {
    public static let none: Int64 = 0

    public private(set) var projects: [Int64: Project] = [:]
    /// In display order (grouped by client), archived ones included.
    public private(set) var list: [Project] = []
    /// What pickers offer: not archived.
    public var active: [Project] { list.filter { !$0.isArchived } }
    /// Newest first.
    public private(set) var rules: [ProjectRule] = []

    public init(projects: [Project] = [], rules: [ProjectRule] = []) {
        list = projects
        self.projects = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.rules = rules.filter { self.projects[$0.projectID] != nil }
            .sorted { $0.createdAt != $1.createdAt ? $0.createdAt > $1.createdAt : $0.id > $1.id }
    }

    public var isEmpty: Bool { projects.isEmpty }

    /// The project and, when a rule decided it, that rule.
    public func resolve(_ s: Segment, ignoringManual: Bool = false) -> (project: Project, rule: ProjectRule?)? {
        if !ignoringManual, let id = s.manualProjectID {
            return projects[id].map { ($0, nil) }
        }
        // An archived project keeps what its rules caught before, and nothing after.
        guard let rule = rules.first(where: { r in
            r.matches(s) && (projects[r.projectID]?.archivedAt).map { s.start < $0 } ?? true
        }), let p = projects[rule.projectID] else { return nil }
        return (p, rule)
    }
}

extension DayReport {
    /// Gives each block the project most of its time belongs to. Done after
    /// the blocks are built, so projects never split or merge blocks.
    public func withProjects(_ resolver: ProjectResolver, segments: [Segment]) -> DayReport {
        guard !resolver.isEmpty else { return self }
        var found: [Int64: (Project, ProjectRule?)] = [:]
        var duration: [Int64: Int64] = [:]
        for s in segments where s.kind == .active {
            duration[s.id] = s.duration
            if let r = resolver.resolve(s) { found[s.id] = (r.project, r.rule) }
        }
        var r = self
        func assign(_ b: inout Block) {
            var time: [Int64: Int64] = [:]
            var unassigned: Int64 = 0
            var why: [Int64: ProjectRule] = [:]
            var pick: [Int64: Project] = [:]
            for id in b.segmentIDs {
                let d = duration[id] ?? 0
                if let (p, rule) = found[id] {
                    time[p.id, default: 0] += d
                    pick[p.id] = p
                    if let rule, why[p.id] == nil { why[p.id] = rule }
                } else {
                    unassigned += d
                }
            }
            // Most of the block's time decides; mostly unassigned means no project.
            guard let best = time.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }),
                  best.value >= unassigned else {
                b.project = nil
                b.projectRule = nil
                return
            }
            b.project = pick[best.key]
            b.projectRule = why[best.key]
        }
        for i in r.blocks.indices { assign(&r.blocks[i]) }
        for l in r.lanes.indices { for i in r.lanes[l].blocks.indices { assign(&r.lanes[l].blocks[i]) } }
        return r
    }
}

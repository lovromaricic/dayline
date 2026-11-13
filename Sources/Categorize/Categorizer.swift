import Domain

/// Resolution order (spec section 4), first match wins:
/// 1. a manual correction on the segment ("Just this time")
/// 2. your rules, newest first within a kind; kinds in order site, app, title
/// 3. a call (mic/camera in use) counts as Meetings when that setting is on
/// 4. built-in rules (BuiltinRules.swift)
/// 5. the app's own LSApplicationCategoryType
/// 6. Uncategorized
public struct Categorizer: Sendable {
    /// Spec setting "Count calls as active".
    public var callsAreMeetings = true
    public private(set) var rules: [Rule] = []
    /// Category rows by id, so renamed or recolored categories show as they are now.
    public private(set) var categories: [Int64: ActivityCategory] = [:]
    /// The same, in display order (table `sort`), for pickers.
    public private(set) var categoryList: [ActivityCategory] = []
    /// Merged or deleted categories: old id -> the category that took its time.
    public var aliases: [Int64: Int64] = [:]
    /// LSApplicationCategoryType for a bundle id; supplied by the app (needs AppKit).
    public var appCategoryType: @Sendable (String) -> String? = { _ in nil }

    public init(categories: [ActivityCategory] = ActivityCategory.defaults, rules: [Rule] = []) {
        setCategories(categories)
        setRules(rules)
    }

    public mutating func setCategories(_ list: [ActivityCategory]) {
        categories = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        categoryList = list
    }

    public mutating func setRules(_ list: [Rule]) {
        let order: [Rule.Kind] = [.site, .app, .titleContains]
        rules = list.sorted {
            $0.kind != $1.kind ? order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)!
                : $0.createdAt != $1.createdAt ? $0.createdAt > $1.createdAt : $0.id > $1.id
        }
    }

    public func category(for s: Segment) -> ActivityCategory {
        resolve(s).category
    }

    public func resolve(_ s: Segment, ignoringManual: Bool = false) -> CategoryResolution {
        let guess = self.guess(s)
        if !ignoringManual, let id = s.manualCategoryID, let c = categories[id] {
            return CategoryResolution(category: c, guess: guess, edited: c != guess)
        }
        if let rule = rules.first(where: { $0.matches(s) }), let c = categories[rule.categoryID] {
            return CategoryResolution(category: c, guess: guess, edited: c != guess)
        }
        return CategoryResolution(category: guess, guess: guess, edited: false)
    }

    /// Steps 3–6: what Dayline picks without any input from you.
    public func guess(_ s: Segment) -> ActivityCategory {
        let seed: ActivityCategory
        if callsAreMeetings && s.call {
            seed = .meetings
        } else if let c = BuiltinRules.category(for: s) {
            seed = c
        } else if let type = appCategoryType(s.appBundleID), let c = BuiltinRules.appStoreCategory(type) {
            seed = c
        } else {
            seed = .uncategorized
        }
        // Built-ins point at seed rows; show them under their current name and
        // color, or wherever that row was merged to.
        var id = seed.id
        for _ in 0..<8 { guard let next = aliases[id] else { break }; id = next }
        return categories[id] ?? categories[ActivityCategory.uncategorized.id] ?? .uncategorized
    }
}

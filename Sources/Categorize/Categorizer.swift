import Domain

/// Resolution order (spec section 4), first match wins:
/// 1. a manual correction on the segment ("Just this time")
/// 2. a whole call counts as Meetings when that setting is on, whatever was
///    in front; what was in front shows as the call's proof (DayReport)
/// 3. your rules, newest first within a kind; kinds in order site, app, title
/// 4. built-in rules (BuiltinRules.swift)
/// 5. the app's own LSApplicationCategoryType
/// 6. a call counts as Meetings when that setting is on. The segment's call
///    flag is set only in the app or tab where the call started (Segmenter),
///    and only chat, browsing or uncategorized time turns into Meetings:
///    Figma stays Design. This is what a call split into "What I was doing" shows
/// 7. Uncategorized
public struct Categorizer: Sendable {
    /// Setting "Count calls as meetings".
    public var callsAreMeetings = true
    /// Whole calls start here: older data flags only the call window, so its
    /// calls would come out as slivers. Before this, step 2 is skipped.
    public var wholeCallsSince: Int64 = 0
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
        if callsAreMeetings && s.wholeCall && s.start >= wholeCallsSince {
            let m = current(.meetings)
            return CategoryResolution(category: m, guess: m, edited: false, wholeCall: true)
        }
        if let rule = rules.first(where: { $0.matches(s) }), let c = categories[rule.categoryID] {
            return CategoryResolution(category: c, guess: guess, edited: c != guess)
        }
        return CategoryResolution(category: guess, guess: guess, edited: false)
    }

    /// Steps 4–7: what Dayline picks without any input from you.
    public func guess(_ s: Segment) -> ActivityCategory {
        var seed = BuiltinRules.category(for: s)
            ?? appCategoryType(s.appBundleID).flatMap(BuiltinRules.appStoreCategory) ?? .uncategorized
        if callsAreMeetings && s.call && [ActivityCategory.uncategorized, .communication, .browsing].contains(seed) {
            seed = .meetings
        }
        return current(seed)
    }

    /// Built-ins point at seed rows; show them under their current name and
    /// color, or wherever that row was merged to.
    private func current(_ seed: ActivityCategory) -> ActivityCategory {
        var id = seed.id
        for _ in 0..<8 { guard let next = aliases[id] else { break }; id = next }
        return categories[id] ?? categories[ActivityCategory.uncategorized.id] ?? .uncategorized
    }
}

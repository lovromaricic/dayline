import AppKit

/// LSApplicationCategoryType from an app's Info.plist (spec 4, step 3), cached.
enum AppCategoryLookup {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: String?] = [:]

    @Sendable static func categoryType(for bundleID: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[bundleID] { return hit }
        let type = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String }
        cache[bundleID] = type
        return type
    }
}

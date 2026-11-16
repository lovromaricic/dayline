import ApplicationServices
import Foundation

public struct SafariSnapshot {
    var rawTitle: String?
    public var url: URL?
    public var isPrivate = false

    public var title: String? { rawTitle.map(SafariReader.cleanTitle) }
}

/// Safari's page is a WebKit AXWebArea that carries the exact URL, so no
/// address-bar parsing is needed.
public enum SafariReader {
    public static let bundleIDs: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]

    /// Private windows are titled "Page, Private Browsing".
    static func cleanTitle(_ raw: String) -> String {
        raw.replacingOccurrences(of: #", Private Browsing$"#, with: "", options: .regularExpression)
    }

    public static func read(window: AXUIElement) -> SafariSnapshot {
        var snap = SafariSnapshot()
        snap.rawTitle = AX.string(window, kAXTitleAttribute)

        // Breadth-first down to the first web area; its contents are skipped.
        // The address field says "smart search field in a private window";
        // tab titles are page text, so they are never taken as evidence.
        var queue = [window]
        var field = false
        var i = 0
        while i < queue.count, i < 2000 {
            let el = queue[i]
            i += 1
            let role = AX.role(el)
            if role == "AXWebArea" {
                if snap.url == nil { snap.url = AX.url(el, "AXURL") }
                continue
            }
            if role == kAXTextFieldRole, AX.string(el, kAXIdentifierAttribute) == "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD" {
                field = true
                snap.isPrivate = AX.string(el, kAXDescriptionAttribute)?.localizedCaseInsensitiveContains("private") ?? false
            }
            if snap.url != nil, field { break }
            queue.append(contentsOf: AX.children(el))
        }
        return snap
    }
}

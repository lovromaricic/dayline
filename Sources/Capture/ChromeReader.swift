import ApplicationServices
import Foundation

public struct ChromeSnapshot {
    var rawTitle: String?
    var incognitoEvidence: String?
    var rootURL: URL?
    var omniboxText: String?
    var omniboxFocused = false
    var nodesVisited = 0
    var millis = 0.0

    public var isIncognito: Bool { incognitoEvidence != nil }
    public var title: String? { rawTitle.map(ChromeReader.cleanTitle) }

    /// AXURL on the window's root view first (exact), omnibox text second (display form, scheme elided).
    public var bestURL: (URL, String)? {
        if let u = rootURL { return (u, "axurl") }
        if !omniboxFocused, let t = omniboxText, let u = ChromeReader.urlFromOmnibox(t) { return (u, "omnibox") }
        return nil
    }
}

public enum ChromeReader {
    public static let bundleIDs: Set<String> = ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary"]

    /// Window titles look like "Page - High memory usage - 957 MB - Google Chrome".
    /// The status suffixes are Chrome UI strings, so they are English-only here.
    private static let suffixes = [
        #" - Google Chrome( - .+)?$"#,
        #" - High memory usage - [\d.,]+ ?[KMG]B$"#,
        #" - (Audio playing|Audio muted|Camera recording|Microphone recording|Camera and microphone recording|Screen sharing|Network error|Crashed)$"#,
    ]

    public static func cleanTitle(_ raw: String) -> String {
        var t = raw
        for p in suffixes {
            t = t.replacingOccurrences(of: p, with: "", options: .regularExpression)
        }
        return t
    }

    /// Chrome's omnibox shows "github.com/foo" without a scheme.
    static func urlFromOmnibox(_ text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !t.contains(" ") else { return nil }
        if t.contains("://") { return URL(string: t) }
        guard t.contains(".") || t.hasPrefix("localhost") else { return nil }
        return URL(string: "https://" + t)
    }

    public static func read(window: AXUIElement) -> ChromeSnapshot {
        let t0 = DispatchTime.now()
        var snap = ChromeSnapshot()
        snap.rawTitle = AX.string(window, kAXTitleAttribute)

        for child in AX.children(window) {
            if let u = AX.url(child, "AXURL") { snap.rootURL = u; break }
        }

        // Breadth-first over the browser chrome. The tab strip (dozens of
        // tabs) and web content are skipped; the main toolbar is the first
        // AXToolbar and holds both the omnibox and the profile/Incognito button.
        var queue = [window]
        var mainToolbar: AXUIElement?
        var i = 0
        while i < queue.count, i < 2000 {
            let el = queue[i]
            i += 1
            let role = AX.role(el)
            if role == "AXWebArea" || role == kAXTabGroupRole { continue }
            if role == kAXToolbarRole {
                if mainToolbar != nil { continue }  // bookmarks bar
                mainToolbar = el
                for item in AX.children(el) where snap.incognitoEvidence == nil {
                    for name in [kAXTitleAttribute, kAXDescriptionAttribute] {
                        if let s = AX.string(item, name), s.localizedCaseInsensitiveContains("incognito") {
                            snap.incognitoEvidence = "\(AX.role(item) ?? "?") \(name.dropFirst(2))=\"\(s.prefix(40))\""
                            break
                        }
                    }
                }
            }
            if role == kAXTextFieldRole, snap.omniboxText == nil {
                snap.omniboxText = AX.string(el, kAXValueAttribute) ?? ""
                snap.omniboxFocused = AX.bool(el, kAXFocusedAttribute) ?? false
            }
            if snap.omniboxText != nil, mainToolbar != nil { break }
            queue.append(contentsOf: AX.children(el))
        }
        snap.nodesVisited = i
        snap.millis = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6
        return snap
    }
}

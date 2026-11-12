import Foundation

/// Spike-quality domain helpers. M1 needs a real Public Suffix List.
enum DomainName {
    private static let secondLevel: Set<String> = ["co", "com", "org", "net", "ac", "gov", "edu", "ne", "or"]

    static func host(of url: URL) -> String? {
        // chrome://newtab, file://, about:blank have no site.
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Naive eTLD+1: "developer.apple.com" -> "apple.com", "bbc.co.uk" -> "bbc.co.uk".
    static func registrable(_ host: String) -> String {
        let labels = host.split(separator: ".")
        guard labels.count > 2 else { return host }
        let tld = labels[labels.count - 1], sld = labels[labels.count - 2]
        let keep = (tld.count == 2 && secondLevel.contains(String(sld))) ? 3 : 2
        return labels.suffix(keep).joined(separator: ".")
    }

    /// Chrome's omnibox shows "github.com/foo" without a scheme.
    static func urlFromOmnibox(_ text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !t.contains(" ") else { return nil }
        if t.contains("://") { return URL(string: t) }
        guard t.contains(".") || t.hasPrefix("localhost") else { return nil }
        return URL(string: "https://" + t)
    }
}

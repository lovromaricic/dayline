import Foundation

/// Public Suffix List lookups (https://publicsuffix.org/list/), compiled in
/// from PublicSuffixData.swift. Includes the private section, so
/// "someone.github.io" and "site.framer.app" are their own registrable domains.
public struct PublicSuffix: Sendable {
    public static let shared = PublicSuffix(list: publicSuffixData)

    private let rules: Set<String>
    private let wildcards: Set<String>   // "*.ck" stored as "ck"
    private let exceptions: Set<String>  // "!www.ck" stored as "www.ck"

    public init(list: String) {
        var rules = Set<String>(), wildcards = Set<String>(), exceptions = Set<String>()
        for line in list.split(whereSeparator: \.isNewline) {
            let rule = line.lowercased()
            if rule.hasPrefix("!") {
                exceptions.insert(String(rule.dropFirst()))
            } else if rule.hasPrefix("*.") {
                wildcards.insert(String(rule.dropFirst(2)))
            } else {
                rules.insert(rule)
            }
        }
        self.rules = rules
        self.wildcards = wildcards
        self.exceptions = exceptions
    }

    /// "developer.apple.com" -> "apple.com"; "bbc.co.uk" -> "bbc.co.uk".
    /// IP addresses, single-label hosts and bare public suffixes come back unchanged.
    public func registrableDomain(of host: String) -> String {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if host.isEmpty || isIPAddress(host) { return host }
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 1 else { return host }

        // Longest matching rule wins; an exception rule beats a wildcard.
        var suffixCount = 1  // the implicit "*" rule
        for i in 0..<labels.count {
            let candidate = labels[i...].joined(separator: ".")
            if exceptions.contains(candidate) {
                suffixCount = labels.count - i - 1
                break
            }
            if rules.contains(candidate) {
                suffixCount = labels.count - i
                break
            }
            if i + 1 < labels.count, wildcards.contains(labels[(i + 1)...].joined(separator: ".")) {
                suffixCount = labels.count - i
                break
            }
        }
        guard suffixCount < labels.count else { return host }
        return labels.suffix(suffixCount + 1).joined(separator: ".")
    }

    private func isIPAddress(_ host: String) -> Bool {
        host.contains(":") || host.split(separator: ".").allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }
}

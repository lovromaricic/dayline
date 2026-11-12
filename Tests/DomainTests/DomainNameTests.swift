import Foundation
import Testing
@testable import Domain

@Suite struct PublicSuffixTests {
    let psl = PublicSuffix.shared

    @Test(arguments: [
        ("developer.apple.com", "apple.com"),
        ("apple.com", "apple.com"),
        ("bbc.co.uk", "bbc.co.uk"),
        ("news.bbc.co.uk", "bbc.co.uk"),
        ("lovro.github.io", "lovro.github.io"),           // private section
        ("a.b.someone.github.io", "someone.github.io"),
        ("authentic-today-714871.framer.app", "authentic-today-714871.framer.app"),
        ("toolkit.artlist.io", "artlist.io"),
        ("george-business.blue.fat2.sparkasse.at", "sparkasse.at"),
        ("www.ck", "www.ck"),                              // exception rule
        ("foo.bar.ck", "foo.bar.ck"),                      // wildcard *.ck
        ("co.uk", "co.uk"),                                // bare public suffix
        ("localhost", "localhost"),
        ("127.0.0.1", "127.0.0.1"),
        ("APP.Slack.COM", "slack.com"),
    ])
    func registrable(host: String, expected: String) {
        #expect(psl.registrableDomain(of: host) == expected)
    }
}

@Suite struct ActivityTests {
    @Test func browserKeepsHostAndDomainNotPath() {
        let a = Activity.browser(appBundleID: "com.google.Chrome", appName: "Google Chrome", title: "Docs",
                                 url: URL(string: "https://www.developer.apple.com/documentation/swift?x=1"))
        #expect(a.host == "developer.apple.com")
        #expect(a.domain == "apple.com")
    }

    @Test(arguments: ["chrome://newtab/", "file:///Users/x/a.pdf", "about:blank"])
    func nonWebURLsHaveNoSite(url: String) {
        let a = Activity.browser(appBundleID: "com.google.Chrome", appName: "Google Chrome", title: "t", url: URL(string: url))
        #expect(a.host == nil && a.domain == nil)
    }

    @Test func exclusionsMatchAppsAndSubdomains() {
        let ex = Exclusions(apps: ["com.apple.Passwords"], sites: ["bank.example"])
        #expect(ex.excludes(Activity(appBundleID: "com.apple.Passwords", appName: "Passwords")))
        #expect(ex.excludes(Activity.browser(appBundleID: "c", appName: "C", title: nil, url: URL(string: "https://online.bank.example/"))))
        #expect(!ex.excludes(Activity.browser(appBundleID: "c", appName: "C", title: nil, url: URL(string: "https://notbank.example/"))))
    }
}

@Suite struct TitlesTests {
    @Test(arguments: [
        ("(3) Inbox - Gmail", "Inbox - Gmail"),
        ("! Alex (DM) - Acme - 1 new item - Slack", "Alex (DM) - Acme - Slack"),
        ("Alex (DM) - Acme - 12 new items - Slack", "Alex (DM) - Acme - Slack"),
        ("Inbox (13,743) - me@example.com - Gmail", "Inbox - me@example.com - Gmail"),
        ("• Slack", "Slack"),
        ("Plain title", "Plain title"),
    ])
    func normalize(raw: String, expected: String) {
        #expect(Titles.normalize(raw) == expected)
    }
}

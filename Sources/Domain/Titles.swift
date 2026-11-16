import Foundation

public enum Titles {
    /// Strips unread badges that apps toggle on their own, so they do not
    /// split segments: "(3) Inbox - Gmail", "! Alex (DM) - 1 new item - Slack",
    /// "• Slack". Used only for comparison; the stored title stays as captured.
    public static func normalize(_ title: String) -> String {
        var t = title
        for pattern in [
            #"^\(\d+\+?\)\s*"#,             // (3) Inbox
            #"^[!*•●]\s*"#,                  // ! Alex (DM)
            #" - \d+ new items?(?= - )"#,    // ... - 1 new item - Slack
            #"\s*\(\d{1,3}(,\d{3})*\)"#,    // Inbox (13,743) - Gmail
        ] {
            t = t.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// The site behind a browser window that has no address: an installed web
    /// app ("Alex - Acme - Slack") or Chrome's screen-sharing
    /// prompts ("Choose what to share with teams.microsoft.com"). nil if unknown.
    public static func webAppHost(_ title: String) -> String? {
        let t = normalize(title)
        if let m = t.range(of: #"[a-z0-9-]+(\.[a-z0-9-]+)+(?= is sharing)|(?<=share with )[a-z0-9-]+(\.[a-z0-9-]+)+"#,
                           options: .regularExpression) {
            return String(t[m])
        }
        let last = t.components(separatedBy: " - ").last?.components(separatedBy: " | ").last?
            .trimmingCharacters(in: .whitespaces) ?? t
        return webApps[last]
    }

    static let webApps: [String: String] = [
        "Slack": "app.slack.com", "Microsoft Teams": "teams.microsoft.com", "Google Calendar": "calendar.google.com",
        "Gmail": "mail.google.com", "Google Meet": "meet.google.com", "WhatsApp": "web.whatsapp.com",
        "Discord": "discord.com", "Notion": "www.notion.so", "Figma": "www.figma.com", "Linear": "linear.app",
        "Outlook": "outlook.office.com",
    ]

    /// "Novi kreditni accounti – FigJam" -> "Novi kreditni accounti": the
    /// app's name after an en dash (Figma, Google Docs) says nothing new.
    public static func withoutAppSuffix(_ title: String) -> String {
        let t = normalize(title)
        guard let r = t.range(of: " – ", options: .backwards), t.distance(from: r.upperBound, to: t.endIndex) <= 20 else { return t }
        return String(t[..<r.lowerBound])
    }

    /// What to call a call, from the window it started in.
    public static func callName(appBundleID: String, appName: String, host: String?, title: String?) -> String {
        let site = host ?? title.flatMap(webAppHost)
        if appBundleID == "us.zoom.xos" || site == "zoom.us" || site?.hasSuffix(".zoom.us") == true { return "Zoom call" }
        if appBundleID == "com.apple.FaceTime" { return "FaceTime call" }
        if site == "meet.google.com" { return "Google Meet" }
        if appBundleID.hasPrefix("com.microsoft.teams") || site == "teams.microsoft.com" { return "Teams call" }
        if appBundleID == "com.tinyspeck.slackmacgap" || site == "app.slack.com" { return "Slack huddle" }
        if appBundleID == "com.hnc.Discord" || site == "discord.com" { return "Discord call" }
        return "Call in \(appName)"
    }

    /// Who is on a Slack huddle, from its window: "Alex, Sam - Acme - Slack"
    /// -> "Alex, Sam". nil for any other window.
    public static func callPeople(host: String?, title: String?) -> String? {
        guard host == nil, let t = title.map(normalize), t.hasSuffix(" - Slack") else { return nil }
        let parts = t.components(separatedBy: " - ")
        guard parts.count >= 3, let first = parts.first?.trimmingCharacters(in: .whitespaces), !first.isEmpty else { return nil }
        return first
    }

    /// Windows that are a call wherever the call started: a Slack huddle (its
    /// own browser window with no address, titled with the people in it,
    /// "Alex, Sam - Acme - Slack"), Google Meet, Zoom, FaceTime.
    public static func isCallWindow(appBundleID: String, host: String?, title: String?) -> Bool {
        if ["us.zoom.xos", "com.apple.FaceTime"].contains(appBundleID) { return true }
        if let host { return host == "meet.google.com" || host == "zoom.us" || host.hasSuffix(".zoom.us") }
        return title.map(normalize)?.hasSuffix(" - Slack") ?? false
    }
}

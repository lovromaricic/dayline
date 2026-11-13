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
}

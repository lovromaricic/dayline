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
}

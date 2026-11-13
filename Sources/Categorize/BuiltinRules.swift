import Domain

/// Built-in rules (spec section 4, step 2). They sit below your rules.
/// Kept in Swift rather than a bundled JSON file: the app is assembled by
/// scripts/build-app.sh, and SwiftPM resource bundles do not survive that.
public enum BuiltinRules {
    public struct Entry: Sendable {
        public var kind: Rule.Kind
        /// Bundle id for apps, host or registrable domain for sites.
        public var pattern: String
        /// Human name for the list in Settings.
        public var label: String
        public var category: ActivityCategory
    }

    public static func category(for s: Segment) -> ActivityCategory? {
        if let host = s.host {
            if let c = hosts[host] { return c }
            if let d = s.domain, let c = sites[d] { return c }
        }
        if let c = apps[s.appBundleID]?.1 { return c }
        // A web app window (no address bar): known by its title.
        if browsers.contains(s.appBundleID), s.host == nil, let host = s.title.flatMap(Titles.webAppHost) {
            if let c = hosts[host] { return c }
            if let c = sites[PublicSuffix.shared.registrableDomain(of: host)] { return c }
        }
        if browsers.contains(s.appBundleID) { return .browsing }
        return nil
    }

    /// Everything, for the read-only list in Settings.
    public static var all: [Entry] {
        apps.map { Entry(kind: .app, pattern: $0.key, label: $0.value.0, category: $0.value.1) }
            + hosts.map { Entry(kind: .site, pattern: $0.key, label: $0.key, category: $0.value) }
            + sites.map { Entry(kind: .site, pattern: $0.key, label: $0.key, category: $0.value) }
            + browsers.map { Entry(kind: .app, pattern: $0, label: browserNames[$0] ?? $0, category: .browsing) }
    }

    public static var count: Int { apps.count + hosts.count + sites.count + browsers.count }

    static let browsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "com.apple.Safari", "company.thebrowser.Browser", "org.mozilla.firefox", "com.microsoft.edgemac",
        "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    ]

    static let browserNames: [String: String] = [
        "com.google.Chrome": "Google Chrome", "com.google.Chrome.beta": "Chrome Beta", "com.google.Chrome.dev": "Chrome Dev",
        "com.google.Chrome.canary": "Chrome Canary", "com.apple.Safari": "Safari", "company.thebrowser.Browser": "Arc",
        "org.mozilla.firefox": "Firefox", "com.microsoft.edgemac": "Microsoft Edge", "com.brave.Browser": "Brave",
        "com.operasoftware.Opera": "Opera", "com.vivaldi.Vivaldi": "Vivaldi",
    ]

    /// Bundle id -> (name, category).
    static let apps: [String: (String, ActivityCategory)] = [
        // Entertainment
        "com.apple.Music": ("Music", .entertainment),
        "com.apple.TV": ("TV", .entertainment),
        "com.apple.podcasts": ("Podcasts", .entertainment),
        "com.spotify.client": ("Spotify", .entertainment),
        "com.tidal.desktop": ("TIDAL", .entertainment),
        "org.videolan.vlc": ("VLC", .entertainment),
        "com.colliderli.iina": ("IINA", .entertainment),
        "com.valvesoftware.steam": ("Steam", .entertainment),
        // Development
        "com.apple.dt.Xcode": ("Xcode", .development),
        "com.microsoft.VSCode": ("Visual Studio Code", .development),
        "com.microsoft.VSCodeInsiders": ("VS Code Insiders", .development),
        "com.todesktop.230313mzl4w4u92": ("Cursor", .development),
        "dev.zed.Zed": ("Zed", .development),
        "com.sublimetext.4": ("Sublime Text", .development),
        "com.jetbrains.intellij": ("IntelliJ IDEA", .development),
        "com.jetbrains.pycharm": ("PyCharm", .development),
        "com.jetbrains.WebStorm": ("WebStorm", .development),
        "com.google.android.studio": ("Android Studio", .development),
        "com.apple.Terminal": ("Terminal", .development),
        "com.googlecode.iterm2": ("iTerm", .development),
        "dev.warp.Warp-Stable": ("Warp", .development),
        "com.mitchellh.ghostty": ("Ghostty", .development),
        "com.github.GitHubClient": ("GitHub Desktop", .development),
        "com.fournova.Tower3": ("Tower", .development),
        "com.postmanlabs.mac": ("Postman", .development),
        "com.apple.Instruments": ("Instruments", .development),
        "com.apple.dt.Xcode.AccessibilityInspector": ("Accessibility Inspector", .development),
        "com.apple.Console": ("Console", .development),
        "com.docker.docker": ("Docker", .development),
        "com.tinyapp.TablePlus": ("TablePlus", .development),
        "cc.arduino.IDE2": ("Arduino IDE", .development),
        "com.anthropic.claudefordesktop": ("Claude", .development),
        "com.openai.codex": ("Codex", .development),
        "com.parallels.desktop.console": ("Parallels Desktop", .development),
        // Design
        "com.figma.Desktop": ("Figma", .design),
        "com.bohemiancoding.sketch3": ("Sketch", .design),
        "com.adobe.Photoshop": ("Photoshop", .design),
        "com.adobe.illustrator": ("Illustrator", .design),
        "com.adobe.InDesign": ("InDesign", .design),
        "com.adobe.xd": ("Adobe XD", .design),
        "com.adobe.AfterEffects": ("After Effects", .design),
        "com.adobe.PremierePro": ("Premiere Pro", .design),
        "com.seriflabs.affinitydesigner2": ("Affinity Designer 2", .design),
        "com.seriflabs.affinityphoto2": ("Affinity Photo 2", .design),
        "com.pixelmatorteam.pixelmator.x": ("Pixelmator Pro", .design),
        "com.blackmagic-design.DaVinciResolve": ("DaVinci Resolve", .design),
        "com.apple.FinalCut": ("Final Cut Pro", .design),
        "com.autodesk.fusion360": ("Autodesk Fusion", .design),
        "com.shapr3d.shapr": ("Shapr3D", .design),
        "org.blenderfoundation.blender": ("Blender", .design),
        "com.framer.electron": ("Framer", .design),
        "com.lukilabs.lukiapp": ("Craft", .writing),
        "com.apple.SFSymbols": ("SF Symbols", .design),
        "com.apple.IconComposer": ("Icon Composer", .design),
        "com.rotato.app": ("Rotato", .design),
        "com.screenstudio.app": ("Screen Studio", .design),
        "com.cavalry.app": ("Cavalry", .design),
        // Communication
        "com.tinyspeck.slackmacgap": ("Slack", .communication),
        "com.apple.mail": ("Mail", .communication),
        "com.apple.MobileSMS": ("Messages", .communication),
        "com.microsoft.Outlook": ("Microsoft Outlook", .communication),
        "ru.keepcoder.Telegram": ("Telegram", .communication),
        "net.whatsapp.WhatsApp": ("WhatsApp", .communication),
        "com.hnc.Discord": ("Discord", .communication),
        "org.whispersystems.signal-desktop": ("Signal", .communication),
        "com.readdle.smartemail-Mac": ("Spark", .communication),
        "com.superhuman.electron": ("Superhuman", .communication),
        "com.apple.Phone": ("Phone", .communication),
        // Meetings
        "us.zoom.xos": ("Zoom", .meetings),
        // Mostly chat; time in a Teams call counts as Meetings (Categorizer).
        "com.microsoft.teams2": ("Microsoft Teams", .communication),
        "com.apple.FaceTime": ("FaceTime", .meetings),
        // Calendars are planning, not meetings; a call while one is open still
        // counts as Meetings (Categorizer).
        "com.apple.iCal": ("Calendar", .communication),
        "com.flexibits.fantastical2.mac": ("Fantastical", .communication),
        "com.cisco.webexmeetingsapp": ("Webex", .meetings),
        "com.loom.desktop": ("Loom", .meetings),
        // Writing and Docs
        "notion.id": ("Notion", .writing),
        "com.apple.iWork.Pages": ("Pages", .writing),
        "com.apple.iWork.Keynote": ("Keynote", .writing),
        "com.apple.iWork.Numbers": ("Numbers", .writing),
        "com.microsoft.Word": ("Microsoft Word", .writing),
        "com.microsoft.Excel": ("Microsoft Excel", .writing),
        "com.microsoft.Powerpoint": ("Microsoft PowerPoint", .writing),
        "md.obsidian": ("Obsidian", .writing),
        "com.apple.Notes": ("Notes", .writing),
        "net.shinyfrog.bear": ("Bear", .writing),
        "com.ulyssesapp.mac": ("Ulysses", .writing),
        "com.apple.TextEdit": ("TextEdit", .writing),
        "com.apple.Preview": ("Preview", .writing),
        "com.apple.reminders": ("Reminders", .writing),
        "com.linear": ("Linear", .development),
        // Browsing and research
        "com.apple.iBooksX": ("Books", .browsing),
        "com.apple.news": ("News", .browsing),
        "com.apple.Dictionary": ("Dictionary", .browsing),
        "com.perplexity.mac": ("Perplexity", .browsing),
        "com.google.GeminiMacOS": ("Gemini", .browsing),
    ]

    /// Registrable domains.
    static let sites: [String: ActivityCategory] = [
        // Development
        "github.com": .development, "gitlab.com": .development, "bitbucket.org": .development,
        "stackoverflow.com": .development, "stackexchange.com": .development, "linear.app": .development,
        "atlassian.net": .development, "vercel.com": .development, "netlify.com": .development,
        "npmjs.com": .development, "swift.org": .development, "swiftpackageindex.com": .development,
        "developer.mozilla.org": .development, "mdn.dev": .development, "localhost": .development,
        "127.0.0.1": .development, "codepen.io": .development, "codesandbox.io": .development,
        "railway.app": .development, "supabase.com": .development, "sentry.io": .development,
        "claude.ai": .development, "chatgpt.com": .development,
        // Design
        "figma.com": .design, "dribbble.com": .design, "behance.net": .design, "mobbin.com": .design,
        "framer.com": .design, "canva.com": .design, "coolors.co": .design, "fonts.google.com": .design,
        "muz.li": .design, "awwwards.com": .design, "pangrampangram.com": .design, "unsplash.com": .design,
        // Communication
        "slack.com": .communication, "discord.com": .communication, "whatsapp.com": .communication,
        "telegram.org": .communication, "outlook.com": .communication, "linkedin.com": .communication,
        "superhuman.com": .communication, "cal.com": .communication, "calendly.com": .communication,
        // Meetings
        "zoom.us": .meetings, "whereby.com": .meetings, "webex.com": .meetings,
        // Writing and Docs
        "notion.so": .writing, "notion.site": .writing, "coda.io": .writing, "dropboxpaper.com": .writing,
        "medium.com": .writing, "substack.com": .writing, "quip.com": .writing, "craft.do": .writing,
        "confluence.com": .writing, "grammarly.com": .writing,
        // Browsing and research
        "wikipedia.org": .browsing, "news.ycombinator.com": .browsing, "reddit.com": .browsing,
        "perplexity.ai": .browsing, "gemini.google.com": .browsing,
        // Entertainment
        "youtube.com": .entertainment, "netflix.com": .entertainment, "twitch.tv": .entertainment,
        "spotify.com": .entertainment, "soundcloud.com": .entertainment, "disneyplus.com": .entertainment,
        "max.com": .entertainment, "hbomax.com": .entertainment, "primevideo.com": .entertainment,
        "hulu.com": .entertainment, "crunchyroll.com": .entertainment, "deezer.com": .entertainment,
        "tidal.com": .entertainment,
    ]

    /// Full hosts, for sites that share a registrable domain.
    static let hosts: [String: ActivityCategory] = [
        "meet.google.com": .meetings, "calendar.google.com": .communication, "teams.microsoft.com": .communication,
        "teams.live.com": .communication, "outlook.office.com": .communication,
        "mail.google.com": .communication, "chat.google.com": .communication,
        "docs.google.com": .writing, "drive.google.com": .writing, "sheets.google.com": .writing,
        "slides.google.com": .writing, "keep.google.com": .writing,
        "developer.apple.com": .development, "developer.android.com": .development,
        "cloud.google.com": .development, "console.aws.amazon.com": .development,
        "gemini.google.com": .browsing, "news.ycombinator.com": .browsing,
        "music.apple.com": .entertainment, "tv.apple.com": .entertainment,
    ]

    /// LSApplicationCategoryType -> category (spec section 4, step 3).
    public static let appStoreCategories: [String: ActivityCategory] = [
        "public.app-category.developer-tools": .development,
        "public.app-category.graphics-design": .design,
        "public.app-category.photography": .design,
        "public.app-category.video": .design,
        "public.app-category.social-networking": .communication,
        "public.app-category.reference": .browsing,
        "public.app-category.news": .browsing,
        "public.app-category.education": .browsing,
        "public.app-category.music": .entertainment,
        "public.app-category.entertainment": .entertainment,
        "public.app-category.games": .entertainment,
    ]

    /// Also covers the game subtypes (public.app-category.action-games and so on).
    public static func appStoreCategory(_ type: String) -> ActivityCategory? {
        appStoreCategories[type] ?? (type.hasSuffix("-games") ? .entertainment : nil)
    }
}

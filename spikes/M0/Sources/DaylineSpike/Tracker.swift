import AppKit
import ApplicationServices

/// Follows the frontmost app and its focused window title. Event-driven:
/// NSWorkspace activation + AXObserver; an optional safety poll reports any
/// change the events missed.
final class Tracker {
    struct Options {
        var dump = false
        var safetyPoll = true
        var manualAX = true
    }

    private let options: Options
    private var workspaceToken: NSObjectProtocol?
    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var observedWindow: AXUIElement?
    private var app: NSRunningApplication?
    private var pending: DispatchWorkItem?
    private var pollTimer: Timer?
    private var lastKey: String?
    private var lastDumpedWindow: AXUIElement?

    init(options: Options) { self.options = options }

    func start() {
        workspaceToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.attach(app)
        }
        attach(NSWorkspace.shared.frontmostApplication)
        if options.safetyPoll {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                guard let self, self.pending == nil else { return }
                self.report(reason: "poll")
            }
        }
    }

    func stop() {
        if let t = workspaceToken { NSWorkspace.shared.notificationCenter.removeObserver(t) }
        workspaceToken = nil
        pollTimer?.invalidate()
        pollTimer = nil
        detach()
        lastKey = nil
    }

    // MARK: - Observation

    private func attach(_ app: NSRunningApplication?) {
        detach()
        guard let app, app.processIdentifier != getpid() else { return }
        self.app = app
        let el = AXUIElementCreateApplication(app.processIdentifier)
        appElement = el

        if isChrome, options.manualAX {
            let err = ChromeReader.enableAccessibility(app: el)
            if err != .success { Log.line("  AXManualAccessibility -> \(err.rawValue)") }
        }

        var obs: AXObserver?
        let err = AXObserverCreate(app.processIdentifier, { _, _, notification, refcon in
            guard let refcon else { return }
            Unmanaged<Tracker>.fromOpaque(refcon).takeUnretainedValue().axEvent(notification as String)
        }, &obs)
        guard err == .success, let obs else {
            Log.line("  AXObserverCreate failed: \(err.rawValue)")
            scheduleReport(reason: "activate")
            return
        }
        observer = obs
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification, kAXTitleChangedNotification] {
            let r = AXObserverAddNotification(obs, el, n as CFString, refcon)
            if r != .success && r != .notificationAlreadyRegistered {
                Log.line("  observe \(n) on \(app.localizedName ?? "?") -> \(r.rawValue)")
            }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observeFocusedWindow()
        scheduleReport(reason: "activate")
    }

    private func detach() {
        pending?.cancel()
        pending = nil
        if let obs = observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        observer = nil
        appElement = nil
        observedWindow = nil
        app = nil
    }

    /// Title changes registered on the app element are not delivered by every
    /// app, so also register on the focused window itself.
    private func observeFocusedWindow() {
        guard let obs = observer, let appEl = appElement, let win = AX.focusedWindow(of: appEl) else { return }
        if let old = observedWindow, old == win { return }
        if let old = observedWindow {
            AXObserverRemoveNotification(obs, old, kAXTitleChangedNotification as CFString)
        }
        AXObserverAddNotification(obs, win, kAXTitleChangedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
        observedWindow = win
    }

    private func axEvent(_ name: String) {
        if name != kAXTitleChangedNotification { observeFocusedWindow() }
        scheduleReport(reason: name.replacingOccurrences(of: "AX", with: ""))
    }

    /// Chrome fires several title changes while a tab loads; settle first.
    private func scheduleReport(reason: String) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pending = nil
            self?.report(reason: reason)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    // MARK: - Reading

    private var isChrome: Bool { ChromeReader.bundleIDs.contains(app?.bundleIdentifier ?? "") }

    private func report(reason: String) {
        guard let app, let appEl = appElement else { return }
        let name = app.localizedName ?? app.bundleIdentifier ?? "?"
        let window = AX.focusedWindow(of: appEl)

        var line: String
        var key: String
        if isChrome, let window {
            if options.dump, lastDumpedWindow.map({ $0 != window }) ?? true {
                lastDumpedWindow = window
                Log.raw("---- AX dump of focused Chrome window ----")
                AX.dump(window)
                Log.raw("---- end dump ----")
            }
            let s = ChromeReader.read(window: window)
            let timing = String(format: "%.1fms/%d nodes", s.millis, s.nodesVisited)
            if s.isIncognito {
                key = "\(name)|incognito"
                line = "\(name)  |  [Incognito window, not recorded]  (\(s.incognitoEvidence!); \(timing))"
            } else {
                let title = s.title ?? "(no title)"
                var domain = "(no domain)"
                var src = "none"
                if let (url, from) = s.bestURL {
                    src = from
                    if let host = DomainName.host(of: url) {
                        domain = "\(DomainName.registrable(host))  host=\(host)"
                    } else {
                        domain = "(\(url.scheme ?? "?"):)"
                    }
                }
                key = "\(name)|\(title)|\(domain)"
                let omni = s.omniboxText.map { " omnibox=\"\($0.prefix(50))\"\(s.omniboxFocused ? "(editing)" : "")" } ?? " omnibox=none"
                line = "\(name)  |  \(title)  |  \(domain)  [url via \(src);\(omni); \(timing)]"
            }
        } else {
            let title = window.flatMap { AX.string($0, kAXTitleAttribute) } ?? "(no window title)"
            key = "\(name)|\(title)"
            line = "\(name)  |  \(title)"
        }

        guard key != lastKey else { return }
        lastKey = key
        Log.line("[\(reason)] \(line)\(reason == "poll" ? "   <-- MISSED BY EVENTS" : "")")
    }
}

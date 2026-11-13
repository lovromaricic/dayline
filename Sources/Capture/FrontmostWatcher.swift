import AppKit
import ApplicationServices
import Domain

/// Follows the frontmost app and its focused window title, event-driven:
/// NSWorkspace activation plus an AXObserver on the frontmost app.
/// Reports `nil` for Chrome Incognito windows and for Dayline's own windows.
///
/// AX calls are blocking IPC to the target app, so reads run on a background
/// queue with a 1 s timeout; a hung app cannot stall the main thread.
public final class FrontmostWatcher {
    public var onActivity: ((Activity?) -> Void)?
    /// Settings "Read Chrome tab titles": off keeps the site but drops the title.
    public var readChromeTitles = true
    /// Settings "Private browsing windows": off records Incognito like any window.
    public var skipPrivateWindows = true

    private let readQueue = DispatchQueue(label: "app.dayline.ax-read", qos: .utility)
    private var workspaceToken: NSObjectProtocol?
    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var observedWindow: AXUIElement?
    private var app: NSRunningApplication?
    private var pending: DispatchWorkItem?
    private var generation = 0

    public init() {}

    public func start() {
        guard workspaceToken == nil else { return }
        workspaceToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.attach(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
        attach(NSWorkspace.shared.frontmostApplication)
    }

    public func stop() {
        if let t = workspaceToken { NSWorkspace.shared.notificationCenter.removeObserver(t) }
        workspaceToken = nil
        detach()
    }

    /// Re-reads the frontmost app, e.g. after wake.
    public func refresh() { scheduleRead() }

    // MARK: - Observation

    /// System surfaces that come forward around lock and unlock; not activity.
    private static let ignoredApps: Set<String> = ["com.apple.loginwindow", "com.apple.ScreenSaver.Engine"]

    private func attach(_ app: NSRunningApplication?) {
        if let id = app?.bundleIdentifier, Self.ignoredApps.contains(id) { return }
        // Looking at Dayline itself is not an activity of its own: it counts
        // toward whatever was in front before, so checking your day leaves
        // no gap in it (and never shows Dayline as a block).
        if app?.processIdentifier == getpid() { return }
        detach()
        guard let app else { return }
        self.app = app
        let el = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(el, 1.0)
        appElement = el

        var obs: AXObserver?
        guard AXObserverCreate(app.processIdentifier, { _, _, notification, refcon in
            guard let refcon else { return }
            Unmanaged<FrontmostWatcher>.fromOpaque(refcon).takeUnretainedValue().axEvent(notification as String)
        }, &obs) == .success, let obs else {
            scheduleRead()
            return
        }
        observer = obs
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification, kAXTitleChangedNotification] {
            AXObserverAddNotification(obs, el, n as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observeFocusedWindow()
        scheduleRead()
    }

    private func detach() {
        pending?.cancel()
        pending = nil
        generation += 1
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
        if let old = observedWindow {
            if old == win { return }
            AXObserverRemoveNotification(obs, old, kAXTitleChangedNotification as CFString)
        }
        AXObserverAddNotification(obs, win, kAXTitleChangedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
        observedWindow = win
    }

    private func axEvent(_ name: String) {
        if name != kAXTitleChangedNotification { observeFocusedWindow() }
        scheduleRead()
    }

    /// Chrome fires several title changes while a tab loads; let them settle.
    private func scheduleRead() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pending = nil
            self?.read()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    // MARK: - Reading

    private func read() {
        guard let app, let appEl = appElement else { return }
        let gen = generation
        let bundleID = app.bundleIdentifier ?? "pid.\(app.processIdentifier)"
        let name = app.localizedName ?? bundleID
        let titles = readChromeTitles, skipPrivate = skipPrivateWindows
        readQueue.async { [weak self] in
            let activity = Self.readActivity(appEl, bundleID: bundleID, name: name, chromeTitles: titles, skipPrivate: skipPrivate)
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }  // app changed meanwhile
                self.onActivity?(activity)
            }
        }
    }

    private static func readActivity(_ appEl: AXUIElement, bundleID: String, name: String,
                                     chromeTitles: Bool, skipPrivate: Bool) -> Activity? {
        let window = AX.focusedWindow(of: appEl)
        guard ChromeReader.bundleIDs.contains(bundleID), let window else {
            return Activity(appBundleID: bundleID, appName: name, title: window.flatMap { AX.string($0, kAXTitleAttribute) })
        }
        let snap = ChromeReader.read(window: window)
        if snap.isIncognito && skipPrivate { return nil }
        return .browser(appBundleID: bundleID, appName: name, title: chromeTitles ? snap.title : nil, url: snap.bestURL?.0)
    }
}

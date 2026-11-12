import AppKit
import CoreGraphics
import Domain

/// Seconds since the last keyboard, mouse or trackpad input.
public enum IdleClock {
    public static func secondsSinceInput() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}

/// Sleep/wake, screen lock/unlock and fast user switching, as suspend/resume.
public final class PowerMonitor {
    public var onEvent: ((CaptureEvent) -> Void)?
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    public init() {}

    public func start() {
        let ws = NSWorkspace.shared.notificationCenter
        let dist = DistributedNotificationCenter.default()
        observe(ws, NSWorkspace.willSleepNotification, .suspend(.sleep))
        observe(ws, NSWorkspace.didWakeNotification, .resume(.sleep))
        observe(dist, Notification.Name("com.apple.screenIsLocked"), .suspend(.lock))
        observe(dist, Notification.Name("com.apple.screenIsUnlocked"), .resume(.lock))
        observe(ws, NSWorkspace.sessionDidResignActiveNotification, .suspend(.session))
        observe(ws, NSWorkspace.sessionDidBecomeActiveNotification, .resume(.session))
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ event: CaptureEvent) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.onEvent?(event) }
        tokens.append((center, token))
    }
}

import AppKit
import ApplicationServices

enum PermissionState: String {
    case needsPermission, waitingForPermission, tracking, permissionLost
}

/// Spec 2.2 state machine, minus `paused` (no UI in M0).
final class PermissionMonitor {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    private(set) var state: PermissionState
    var onChange: ((PermissionState, PermissionState) -> Void)?
    private var timer: Timer?

    init() {
        state = AXIsProcessTrusted() ? .tracking : .needsPermission
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.tick() }
    }

    /// Stands in for the "Open System Settings" button.
    func openSystemSettings(prompt: Bool) {
        if prompt {
            // Shows the system alert and also adds the app (switched off) to the list.
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        } else {
            NSWorkspace.shared.open(Self.settingsURL)
        }
        if state == .needsPermission { set(.waitingForPermission) }
    }

    private func tick() {
        let trusted = AXIsProcessTrusted()
        switch (state, trusted) {
        case (.needsPermission, true), (.waitingForPermission, true), (.permissionLost, true):
            set(.tracking)
        case (.tracking, false):
            set(.permissionLost)
        default:
            break
        }
    }

    private func set(_ new: PermissionState) {
        let old = state
        state = new
        onChange?(old, new)
    }
}

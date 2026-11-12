import ServiceManagement

/// Start at login (spec 5.4) via SMAppService. macOS may list the app under
/// System Settings > General > Login Items and notify the user once.
enum LoginItem {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns an error message to show, or nil.
    @discardableResult
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            Log.line("login item \(on ? "register" : "unregister") failed: \(error)")
            return error.localizedDescription
        }
    }
}

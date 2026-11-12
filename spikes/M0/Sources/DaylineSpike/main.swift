import AppKit

// Usage: DaylineSpike [--dump] [--no-poll] [--no-manual-ax] [--prompt]
//   --dump          print the native AX tree of each newly focused Chrome window
//   --no-poll       disable the 2 s safety poll that flags changes events missed
//   --no-manual-ax  do not set AXManualAccessibility on Chrome (omnibox only)
//   --prompt        use the system Accessibility alert instead of opening Settings

// `open --stdout` fails with -10810 here, so write next to the .app instead.
let logURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("spike.log")
freopen(logURL.path, "a", stdout)
setvbuf(stdout, nil, _IOLBF, 0)
let args = Set(CommandLine.arguments.dropFirst())

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let tracker = Tracker(options: .init(
    dump: args.contains("--dump"),
    safetyPoll: !args.contains("--no-poll"),
    manualAX: !args.contains("--no-manual-ax")
))
let permission = PermissionMonitor()
// Call detection needs no Accessibility, so it runs in every state.
let calls = CallDetector()

permission.onChange = { old, new in
    Log.line("STATE \(old.rawValue) -> \(new.rawValue)")
    switch new {
    case .tracking: tracker.start()
    case .permissionLost: tracker.stop()
    default: break
    }
}

Log.line("Dayline spike pid \(getpid()), bundle \(Bundle.main.bundleIdentifier ?? "none"), AXIsProcessTrusted=\(AXIsProcessTrusted())")
Log.line("STATE \(permission.state.rawValue)")
permission.start()
calls.start()
if permission.state == .tracking {
    tracker.start()
} else {
    permission.openSystemSettings(prompt: args.contains("--prompt"))
}

app.run()

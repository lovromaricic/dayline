import AppKit
import Domain
import SwiftUI
import UI

/// Menu bar item and its popover. AppKit rather than MenuBarExtra because the
/// item needs a custom-drawn ring, ⌥-click to toggle pause and a right-click menu.
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: PopoverPanel
    private let engine: TrackingEngine
    private var clickMonitor: Any?

    init(engine: TrackingEngine, popover: some View) {
        self.engine = engine
        panel = PopoverPanel(content: popover)
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
        panel.onClose = { [weak self] in self?.stopClickMonitor() }
    }

    func update(phase: TrackingPhase, tracked: Int64, length: DayLength, showTotal: Bool) {
        guard let button = statusItem.button else { return }
        button.image = MenuBarIcon.image(phase: phase, tracked: tracked, length: length)
        // Setting "Show today's total in the menu bar": off leaves the ring alone.
        button.attributedTitle = showTotal ? MenuBarIcon.title(phase: phase, tracked: tracked) : NSAttributedString()
        button.imagePosition = showTotal ? .imageLeading : .imageOnly
        button.setAccessibilityLabel(MenuBarIcon.accessibilityLabel(phase: phase, tracked: tracked, length: length))
    }

    var isPopoverShown: Bool { panel.isVisible }
    var onPopoverShow: (() -> Void)?
    /// The popover's primary button is Open System Settings while permission
    /// is missing, so the menu keeps a way to the timeline in every state.
    var onOpenTimeline: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    func closePopover() { panel.close() }

    func refitPopover() { panel.refit() }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else if event.modifierFlags.contains(.option) {
            engine.togglePause()
        } else if panel.isVisible {
            panel.close()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button, let window = button.window else { return }
        onPopoverShow?()
        let itemFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        panel.show(below: itemFrame)
        // Close on any click outside the panel, like a menu.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.panel.close()
        }
    }

    private func stopClickMonitor() {
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = nil
    }

    private func showMenu() {
        panel.close()
        let menu = NSMenu()
        menu.addItem(item("Open timeline") { [weak self] in self?.onOpenTimeline?() })
        let settings = item("Settings…") { [weak self] in self?.onOpenSettings?() }
        settings.keyEquivalent = ","  // shows ⌘, as in the app menu
        menu.addItem(settings)
        menu.addItem(.separator())
        if engine.phase.canPause {
            if case .paused = engine.phase {
                menu.addItem(item("Resume tracking") { [weak self] in self?.engine.resume() })
            }
            for length in PauseLength.allCases {
                menu.addItem(item("Pause \(length.title.prefix(1).lowercased())\(length.title.dropFirst())") { [weak self] in
                    self?.engine.pause(length)
                })
            }
            menu.addItem(.separator())
        }
        menu.addItem(item("Quit Dayline") { NSApp.terminate(nil) })
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, _ action: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(ClosureTarget.run), keyEquivalent: "")
        let target = ClosureTarget(action)
        item.target = target
        item.representedObject = target  // keep alive
        return item
    }
}

private final class ClosureTarget: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func run() { action() }
}

/// Borderless panel under the menu bar item. Non-activating, so the app you
/// were in stays frontmost (and keeps being tracked), but it can take key
/// focus for keyboard use; Esc closes it.
final class PopoverPanel: NSPanel {
    var onClose: (() -> Void)?
    /// Off-screen twin of the content, only for measuring its size.
    private let measure: NSView

    private var closing = false

    init(content: some View) {
        // Two hosts. `measure` reports the size; show/refit apply it with the
        // top edge kept under the menu bar. The visible host never sizes the
        // window, and its GeometryReader pins the content to the top-left:
        // while a change animates, the window already has its final size and
        // a plain host would centre the in-between content in it, so
        // everything would bob up and down.
        let measure = NSHostingView(rootView: content)
        measure.sizingOptions = [.intrinsicContentSize]
        self.measure = measure
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: GeometryReader { _ in content })
        host.sizingOptions = []
        contentView = host
        setContentSize(measure.fittingSize)
    }

    override var canBecomeKey: Bool { true }

    func show(below item: NSRect) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(item) }) ?? NSScreen.main else { return }
        setContentSize(measure.fittingSize)
        let size = frame.size
        var x = item.midX - size.width / 2
        x = min(max(x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        setFrameOrigin(NSPoint(x: x, y: item.minY - 6 - size.height))
        // Fades in with the content's grow (PopoverView), shadow included.
        closing = false
        alphaValue = Self.animates ? 0 : 1
        makeKeyAndOrderFront(nil)
        guard Self.animates else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    private static var animates: Bool { !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    override func cancelOperation(_ sender: Any?) { close() }

    /// A quick fade out, then the real close.
    override func close() {
        guard isVisible, Self.animates else { return finishClose() }
        guard !closing else { return }
        closing = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, closing else { return }
            finishClose()
        })
    }

    private func finishClose() {
        closing = false
        super.close()
        alphaValue = 1
        onClose?()
    }

    /// Keeps the top edge in place when the content changes height.
    func refit() {
        guard isVisible else { return }
        let size = measure.fittingSize
        guard size != frame.size else { return }
        setFrame(NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height), display: true)
    }
}

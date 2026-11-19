import AppKit
import SwiftUI

/// The legacy ("always show scroll bars") scroller in the window's own colour:
/// no visible track or divider, only the knob, instead of the system's grey strip.
/// Overlay scrollers (trackpad default) keep their usual look.
final class DarkScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        guard scrollerStyle == .legacy else { return super.drawKnobSlot(in: slotRect, highlight: flag) }
        NSColor(Theme.surfaceWindow).setFill()
        bounds.fill()
    }

    override func drawKnob() {
        guard scrollerStyle == .legacy else { return super.drawKnob() }
        let knob = rect(for: .knob).insetBy(dx: 4, dy: 4).offsetBy(dx: 0.5, dy: 0)
        guard knob.height > 0 else { return }
        NSColor(hex: 0x3A3D43).setFill()
        NSBezierPath(roundedRect: knob, xRadius: knob.width / 2, yRadius: knob.width / 2).fill()
    }
}

extension View {
    /// Gives the enclosing ScrollView a DarkScroller. Put it on the scroll content.
    func darkScroller() -> some View { background(ScrollerInstaller()) }
}

private struct ScrollerInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let scroll = enclosingScrollView, !(scroll.verticalScroller is DarkScroller) else { return }
            scroll.verticalScroller = DarkScroller()
            // Keep the scroller's width even when nothing scrolls, so the page
            // doesn't widen and re-lay out when content gets short (a search).
            scroll.autohidesScrollers = false
        }
    }
}

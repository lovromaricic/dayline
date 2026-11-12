import AppKit
import Domain

/// The menu bar ring + total (spec 5.1). Drawn with dynamic colors so the
/// track (white on a dark menu bar, black on a light one) and muted text
/// follow the menu bar.
public enum MenuBarIcon {
    /// Ring fill is today's tracked time against 8 h (not a goal).
    public static let target: Int64 = 8 * 3600

    public static func image(phase: TrackingPhase, tracked: Int64) -> NSImage {
        let fraction = min(1, Double(tracked) / Double(target))
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let center = NSPoint(x: 9, y: 9), r: CGFloat = 6.5
            let circle = NSBezierPath(ovalIn: NSRect(x: 9 - r, y: 9 - r, width: 2 * r, height: 2 * r))
            circle.lineWidth = 2.4
            switch phase {
            case .tracking:
                NSColor.labelColor.setStroke()
                circle.stroke()
                if fraction > 0 {
                    let arc = NSBezierPath()
                    arc.appendArc(withCenter: center, radius: r, startAngle: -90, endAngle: -90 + 360 * fraction, clockwise: false)
                    arc.lineWidth = 2.4
                    arc.lineCapStyle = .round
                    let shadow = NSShadow()
                    shadow.shadowColor = NSColor(hex: 0xD1FE17)
                    shadow.shadowBlurRadius = 3
                    shadow.set()
                    NSColor(hex: 0xD1FE17).setStroke()
                    arc.stroke()
                }
            case .paused:
                NSColor.labelColor.withAlphaComponent(0.22).setStroke()
                circle.stroke()
                NSColor.secondaryLabelColor.setFill()
                NSBezierPath(roundedRect: NSRect(x: 6.6, y: 6, width: 1.7, height: 6), xRadius: 0.8, yRadius: 0.8).fill()
                NSBezierPath(roundedRect: NSRect(x: 9.7, y: 6, width: 1.7, height: 6), xRadius: 0.8, yRadius: 0.8).fill()
            case .needsPermission, .waitingForPermission:
                circle.setLineDash([2, 4], count: 2, phase: 0)
                NSColor.labelColor.withAlphaComponent(0.25).setStroke()
                circle.stroke()
            case .permissionLost:
                circle.setLineDash([2, 4], count: 2, phase: 0)
                NSColor(hex: 0xEB5757).setStroke()
                circle.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    public static func title(phase: TrackingPhase, tracked: Int64) -> NSAttributedString {
        let muted = phase != .tracking
        return NSAttributedString(string: " " + Durations.format(tracked), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: muted ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ])
    }

    /// VoiceOver label for the status item.
    public static func accessibilityLabel(phase: TrackingPhase, tracked: Int64) -> String {
        let state = switch phase {
        case .tracking: "tracking"
        case .paused: "paused"
        case .needsPermission, .waitingForPermission: "needs Accessibility access"
        case .permissionLost: "tracking stopped, Accessibility access was turned off"
        }
        return "Dayline, \(Durations.format(tracked)) today, \(state)"
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

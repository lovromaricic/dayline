// Draws the Dayline app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift   (needs iconutil, part of macOS)
import AppKit

func draw(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    // macOS icon grid: 824 pt body centred on a 1024 canvas, ~185 pt corner radius.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: NSColor(srgbRed: 0.10, green: 0.105, blue: 0.115, alpha: 1),
               ending: NSColor(srgbRed: 0.035, green: 0.04, blue: 0.045, alpha: 1))!.draw(in: shape, angle: -90)
    NSColor.white.withAlphaComponent(0.08).setStroke()
    shape.lineWidth = 2 * s
    shape.stroke()

    let center = NSPoint(x: 512 * s, y: 512 * s), r = 250 * s, width = 74 * s
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: r, startAngle: 0, endAngle: 360)
    track.lineWidth = width
    NSColor.white.withAlphaComponent(0.10).setStroke()
    track.stroke()

    // About three quarters of a day: the arc from 12 o'clock, clockwise.
    let lime = NSColor(srgbRed: 0xD1 / 255, green: 0xFE / 255, blue: 0x17 / 255, alpha: 1)
    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: r, startAngle: 90, endAngle: 90 - 270, clockwise: true)
    arc.lineWidth = width
    arc.lineCapStyle = .round
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = lime.withAlphaComponent(0.55)
    glow.shadowBlurRadius = 40 * s
    glow.set()
    lime.setStroke()
    arc.stroke()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try draw(size * scale).representation(using: .png, properties: [:])!.write(to: iconset.appending(path: name))
    }
}
let out = root.appending(path: "Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try p.run()
p.waitUntilExit()
try draw(1024).representation(using: .png, properties: [:])!.write(to: root.appending(path: "Resources/AppIcon.png"))
print(p.terminationStatus == 0 ? "wrote \(out.path)" : "iconutil failed")

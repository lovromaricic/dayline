import SwiftUI

/// Glyphs from the design files, drawn as shapes so they match exactly.
struct PauseGlyph: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 18
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 4.5 * s, y: 3.5 * s, width: 3 * s, height: 11 * s), cornerSize: CGSize(width: s, height: s))
        p.addRoundedRect(in: CGRect(x: 10.5 * s, y: 3.5 * s, width: 3 * s, height: 11 * s), cornerSize: CGSize(width: s, height: s))
        return p
    }
}

struct PlayGlyph: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 14
        var p = Path()
        p.move(to: CGPoint(x: 3 * s, y: 1.8 * s))
        p.addLine(to: CGPoint(x: 3 * s, y: 12.2 * s))
        p.addLine(to: CGPoint(x: 12 * s, y: 7 * s))
        p.closeSubpath()
        return p
    }
}

/// Settings "sliders" icon, stroked at 1.5.
struct SlidersGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 20
            var lines = Path()
            for (a, b, y) in [(3.0, 10.0, 6.0), (14, 17, 6), (3, 6, 14), (10, 17, 14)] {
                lines.move(to: CGPoint(x: a * s, y: y * s))
                lines.addLine(to: CGPoint(x: b * s, y: y * s))
            }
            lines.addEllipse(in: CGRect(x: 10 * s, y: 4 * s, width: 4 * s, height: 4 * s))
            lines.addEllipse(in: CGRect(x: 6 * s, y: 12 * s, width: 4 * s, height: 4 * s))
            ctx.stroke(lines, with: .color(Theme.textMuted), style: StrokeStyle(lineWidth: 1.5 * s, lineCap: .round))
        }
        .frame(width: 20, height: 20)
    }
}

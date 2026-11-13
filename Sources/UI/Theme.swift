import SwiftUI

/// Spec section 8 tokens ("lime on Linear dark"). Type is SF Pro (system font).
public enum Theme {
    public static let bg = Color(hex: 0x08090A)
    public static let surfaceWindow = Color(hex: 0x101113)
    public static let surfacePopover = Color(hex: 0x141516)
    public static let surfaceControl = Color(hex: 0x1C1C1F)
    public static let border = Color(hex: 0x23252A)
    public static let text = Color(hex: 0xF7F8F8)
    public static let textSecondary = Color(hex: 0xD0D6E0)
    public static let textMuted = Color(hex: 0x8A8F98)
    public static let textFaint = Color(hex: 0x62666D)
    public static let accent = Color(hex: 0xD1FE17)
    public static let onAccent = Color(hex: 0x0B0D00)
    public static let danger = Color(hex: 0xEB5757)
    public static let ok = Color(hex: 0x00B8CC)
    /// The menu bar ring and popover note past 9 h, and past 10 h.
    public static let long = Color(hex: 0xFFB547)
    public static let veryLong = Color(hex: 0xFF5A4E)
    /// rgba(255,255,255,0.04): cards
    public static let cardFill = Color.white.opacity(0.04)
    /// rgba(255,255,255,0.05): empty rails
    public static let railFill = Color.white.opacity(0.05)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    /// "#RRGGBB" from the category table.
    init(hexString: String) {
        self.init(hex: UInt32(hexString.dropFirst(), radix: 16) ?? 0x62666D)
    }
}

extension Text {
    /// 12 pt, uppercase, medium, letter-spacing 0.08em.
    func eyebrow() -> some View {
        font(.system(size: 12, weight: .medium)).tracking(0.96).foregroundStyle(Theme.textMuted)
    }
}

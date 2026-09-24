import SwiftUI

/// Colour, radius, spacing and type tokens lifted verbatim from the repository root
/// `README.md` "Design tokens" section — the token authority is `10 UI Kit.dc.html`,
/// and no screen may introduce a colour, radius or spacing value absent from here.
///
/// This is the app-layer visual system only. It has no dependency on ClearskyCore and
/// makes no product decisions — it just names the values the design references use so
/// screens reference `ClearskyColor.inkNavy` etc. instead of hex literals scattered
/// through views.
enum ClearskyColor {
    // Ink / text
    static let inkNavy = Color(hex: "#1B2B4B")
    static let body = Color(hex: "#22314F")
    static let muted = Color(hex: "#5B6F8E")
    static let secondaryInk = Color(hex: "#4C5F7D")

    // Sky
    static let skyStart = Color(hex: "#7FA5CE")
    static let skyEnd = Color(hex: "#D5E8F9")

    // Surfaces
    static let surfacePrimary = Color(hex: "#FDFEFF")
    static let surfaceSecondary = Color(hex: "#F3F8FD")
    static let surfaceTertiary = Color(hex: "#F7FBFE")

    // Hairlines
    static let hairline = Color(hex: "#E9F1F9")
    static let hairlineStrong = Color(hex: "#E0EBF7")

    // Amber action
    static let amberGradientStart = Color(hex: "#FFDD9A")
    static let amberGradientEnd = Color(hex: "#F2B84B")
    static let amberInk = Color(hex: "#4A3410")
    static let amberLabelInk = Color(hex: "#8A6420")

    // Status
    static let keptGreen = Color(hex: "#3F6339")
    static let urgentTerracotta = Color(hex: "#C0492B")

    /// Retired per `10 UI Kit.dc.html`: fails AA under 18px on every surface in this
    /// system. Kept named here only so nobody reaches for the raw hex by accident —
    /// never assign this to text.
    static let retiredMutedDoNotUseForText = Color(hex: "#8FA2BD")
}

enum ClearskyRadius {
    static let xs: CGFloat = 11
    static let sm: CGFloat = 13
    static let s: CGFloat = 14
    static let md: CGFloat = 16
    static let ml: CGFloat = 18
    static let lg: CGFloat = 20
    static let xl: CGFloat = 22
    static let pill: CGFloat = 999
}

enum ClearskySpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 7
    static let s: CGFloat = 9
    static let sm: CGFloat = 11
    static let m: CGFloat = 14
    static let ml: CGFloat = 16
    static let l: CGFloat = 18
    static let xl: CGFloat = 22
}

enum ClearskyMetric {
    /// "44px minimum hit target, everywhere, no exceptions" — root README, Design
    /// tokens, Hard rules.
    static let minHitTarget: CGFloat = 44
}

/// Type tokens per the README: **Anton** for display headlines, uppercase, tracking
/// 0.015em · **Source Serif 4** (600) for editorial/emotional moments · **Instrument
/// Sans** for all UI and body.
///
/// None of the three are bundled in this task (the task note says a placeholder system
/// font is fine — "do not spend time hunting down and embedding font files this task").
/// These helpers stand in with the closest system `Font.Design` so the type *hierarchy*
/// (display vs editorial vs UI) is already correct and swapping in the real families
/// later is a one-line change per case, not a redesign:
/// - display -> `.rounded` system font, bold, uppercase + tracking (Anton is a tall
///   uppercase display face; rounded+bold+tracking approximates its weight and stance)
/// - editorial -> `.serif` system font (stands in for Source Serif 4)
/// - ui/body -> `.default` system font (stands in for Instrument Sans)
enum ClearskyFont {
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func editorial(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

/// Applies the display-headline treatment the README specifies for Anton: uppercase,
/// tracking 0.015em. Call as `.displayHeadlineStyle()` on any Text using
/// `ClearskyFont.display`.
struct DisplayHeadlineModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textCase(.uppercase)
            .tracking(0.015 * 17) // 0.015em at a 17pt reference size
    }
}

extension View {
    func displayHeadlineStyle() -> some View {
        modifier(DisplayHeadlineModifier())
    }
}

extension Color {
    init(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexString = hexString.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

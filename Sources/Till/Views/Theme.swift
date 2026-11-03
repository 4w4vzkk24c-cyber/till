import AppKit
import SwiftUI

/// Colour and spacing tokens for the popover (spec A2). Built from the environment's
/// colour scheme and contrast so every view reads one source. Amber and red mean state
/// only; a chip's accent is identity and is drawn on its icon.
struct Theme {
    let scheme: ColorScheme
    let contrast: ColorSchemeContrast

    init(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast) {
        self.scheme = scheme
        self.contrast = contrast
    }

    private var isDark: Bool { scheme == .dark }
    private var increased: Bool { contrast == .increased }

    var tile: Color {
        isDark ? Color.white.opacity(increased ? 0.18 : 0.10) : Color.black.opacity(increased ? 0.12 : 0.06)
    }
    var hairline: Color {
        isDark ? Color.white.opacity(increased ? 0.32 : 0.16) : Color.black.opacity(increased ? 0.24 : 0.12)
    }
    // Light appearance is derived from system label colours, not mocked (spec A2).
    var ink: Color { isDark ? .white : Color(nsColor: .labelColor) }
    var ink2: Color { isDark ? Color.white.opacity(0.82) : Color(nsColor: .secondaryLabelColor) }
    var ink3: Color { isDark ? Color.white.opacity(0.66) : Color(nsColor: .tertiaryLabelColor) }

    var amber: Color {
        Color(hex: isDark ? "#FFC15E" : HexColor.adjusted("#FFC15E", forLight: true, minContrast: 4.5))
    }

    /// A chip's stored accent, adjusted by lightness only so it stays legible on the tile.
    func accent(_ hex: String) -> Color {
        Color(hex: HexColor.adjusted(hex, forLight: !isDark, minContrast: 3.0))
    }

    /// Blue-ish tint laid over the system window material (spec A2). Strengths are first
    /// guesses to tune on the Mac. Reduce Transparency swaps it for an opaque colour.
    func trayTint(reduceTransparency: Bool) -> Color {
        if reduceTransparency { return Color(hex: isDark ? "#1E3260" : "#E6ECF7") }
        return isDark ? Color(hex: "#1E3260").opacity(0.45) : Color(hex: "#7FA6E8").opacity(0.10)
    }

    static let overdueFill = Color(hex: "#CF2F36")

    enum Radius {
        static let tile: CGFloat = 20       // concentric with the 10 pt padding; tune on the Mac
        static let control: CGFloat = 12
        static let pill: CGFloat = 20
    }

    enum Space {
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let pad: CGFloat = 10
    }
}

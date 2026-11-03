import Foundation

/// WCAG 2 contrast ratio between two `#RRGGBB` colours (1...21). An unparseable colour
/// reads as 1 (no contrast), which fails any threshold rather than passing silently.
enum Contrast {
    static func ratio(_ a: String, _ b: String) -> Double {
        guard let la = luminance(a), let lb = luminance(b) else { return 1 }
        let (hi, lo) = (max(la, lb), min(la, lb))
        return (hi + 0.05) / (lo + 0.05)
    }

    private static func luminance(_ hex: String) -> Double? {
        guard let c = HexColor.rgb(hex) else { return nil }
        func linear(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }
}

extension HexColor {
    /// Reference tile colours the accent adjustment is measured against: a representative
    /// neutral tile over the light and dark popover surfaces.
    static let lightTile = "#ECEFF6"
    static let darkTile = "#445D8E"

    /// Hue in degrees (0..<360), nil for an unparseable colour.
    static func hue(of hex: String) -> Double? {
        guard let c = rgb(hex) else { return nil }
        let (mx, mn) = (max(c.r, c.g, c.b), min(c.r, c.g, c.b))
        let d = mx - mn
        guard d > 0 else { return 0 }
        var h: Double
        if mx == c.r { h = ((c.g - c.b) / d).truncatingRemainder(dividingBy: 6) }
        else if mx == c.g { h = (c.b - c.r) / d + 2 }
        else { h = (c.r - c.g) / d + 4 }
        h *= 60
        if h < 0 { h += 360 }
        return h
    }

    /// Returns `hex` (uppercased) when it already meets `minContrast` against the
    /// reference tile for the appearance; otherwise changes HSL lightness only, in 0.01
    /// steps (darker for light, lighter for dark), so the hue is preserved.
    static func adjusted(_ hex: String, forLight: Bool, minContrast: Double) -> String {
        guard let c = rgb(hex) else { return hex }
        let reference = forLight ? lightTile : darkTile
        let original = format(c.r, c.g, c.b)
        if Contrast.ratio(original, reference) >= minContrast { return original }

        let (h, s, l0) = hsl(c.r, c.g, c.b)
        var l = l0
        let step = forLight ? -0.01 : 0.01
        while true {
            l = min(1, max(0, (l + step) * 100).rounded() / 100)
            let (r, g, b) = fromHSL(h, s, l)
            let candidate = format(r, g, b)
            if Contrast.ratio(candidate, reference) >= minContrast || l <= 0 || l >= 1 { return candidate }
        }
    }

    private static func format(_ r: Double, _ g: Double, _ b: Double) -> String {
        func byte(_ v: Double) -> String {
            let n = min(255, max(0, Int((v * 255).rounded())))
            let digits = String(n, radix: 16, uppercase: true)
            return digits.count == 1 ? "0" + digits : digits
        }
        return "#" + byte(r) + byte(g) + byte(b)
    }

    private static func hsl(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, l: Double) {
        let (mx, mn) = (max(r, g, b), min(r, g, b))
        let l = (mx + mn) / 2
        let d = mx - mn
        guard d > 0 else { return (0, 0, l) }
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
        else if mx == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        h /= 6
        if h < 0 { h += 1 }
        return (h, s, l)
    }

    private static func fromHSL(_ h: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
        guard s > 0 else { return (l, l, l) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func channel(_ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        return (channel(h + 1.0 / 3), channel(h), channel(h - 1.0 / 3))
    }
}

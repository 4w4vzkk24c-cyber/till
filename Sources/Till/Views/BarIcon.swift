import AppKit
import SwiftUI

/// Pure mapping from bar escalation to what the menu bar shows: one static glyph with
/// four tint variants and an overdue count (design §6, §7.5).
struct BarIconPresentation: Equatable {
    enum Tint: Equatable { case template, amber, red, dimmed }

    let glyphName: String
    let tint: Tint
    let countText: String?
    let accessibilityText: String

    init(_ state: BarIconState) {
        glyphName = BarGlyph.name
        switch state {
        case .normal:
            tint = .template; countText = nil; accessibilityText = "Till"
        case .amber:
            tint = .amber; countText = nil; accessibilityText = "Till, a timer is almost due"
        case .red(let count):
            tint = .red
            countText = "\(count)"
            accessibilityText = "Till, \(count) overdue"
        case .dimmed:
            tint = .dimmed; countText = nil; accessibilityText = "Till, no active timers"
        }
    }
}

@MainActor
enum BarIconImage {
    /// 18 pt square; rasterized at 4x so it stays sharp on retina menu bars.
    private static let pointSize = NSSize(width: 18, height: 18)
    private static var cachedBase: NSImage?

    /// Template for normal/dimmed (follows the menu bar's own appearance); a colored
    /// non-template image for amber/red, because the menu bar strips SwiftUI foreground
    /// color from template images (R3).
    static func make(_ presentation: BarIconPresentation) -> NSImage {
        let base = baseImage()
        let image: NSImage
        switch presentation.tint {
        case .template, .dimmed:
            image = (base.copy() as? NSImage) ?? base
            image.isTemplate = true
        case .amber, .red:
            let color: NSColor = presentation.tint == .amber ? .systemOrange : .systemRed
            image = tinted(base, color)
        }
        image.accessibilityDescription = presentation.accessibilityText
        return image
    }

    /// The seedling, rasterized once from the bundled SVG. If that ever fails the bar still
    /// shows something: the old SF Symbol.
    private static func baseImage() -> NSImage {
        if let cachedBase { return cachedBase }
        let image: NSImage
        if let png = try? SVGRasterizer.pngData(from: Data(BarGlyph.seedlingSVG.utf8), pixels: 72),
           let decoded = NSImage(data: png) {
            decoded.size = pointSize
            image = decoded
        } else {
            image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil) ?? NSImage()
        }
        cachedBase = image
        return image
    }

    /// A copy of `base` filled with `color`, keeping its alpha (blend mode source-in).
    private static func tinted(_ base: NSImage, _ color: NSColor) -> NSImage {
        guard let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return base }
        let rect = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        ctx.draw(cg, in: rect)
        ctx.setBlendMode(.sourceIn)
        ctx.setFillColor((color.usingColorSpace(.sRGB) ?? color).cgColor)
        ctx.fill(rect)
        guard let out = ctx.makeImage() else { return base }
        let image = NSImage(cgImage: out, size: pointSize)
        image.isTemplate = false
        return image
    }
}

struct BarIconLabel: View {
    let store: TimerStore

    var body: some View {
        let state = DeadlineState.barEscalation(of: store.chips.map(\.snapshot), at: store.now)
        let presentation = BarIconPresentation(state)
        HStack(spacing: 2) {
            Image(nsImage: BarIconImage.make(presentation))
                .opacity(presentation.tint == .dimmed ? 0.45 : 1)
            if let count = presentation.countText {
                Text(count)
            }
        }
        .accessibilityLabel(presentation.accessibilityText)
    }
}

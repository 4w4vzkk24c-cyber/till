import AppKit
import SwiftUI

/// Pure mapping from bar escalation to what the menu bar shows: one static glyph with
/// four tint variants and an overdue count (design §6, §7.5).
struct BarIconPresentation: Equatable {
    enum Tint: Equatable { case template, amber, red, dimmed }

    let symbolName: String
    let tint: Tint
    let countText: String?
    let accessibilityText: String

    init(_ state: BarIconState) {
        symbolName = "timer"
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

enum BarIconImage {
    /// Template for normal/dimmed (follows the menu bar's own appearance); a palette-colored
    /// non-template image for amber/red, because the menu bar strips SwiftUI foreground
    /// color from template images (R3).
    static func make(_ presentation: BarIconPresentation) -> NSImage {
        let base = NSImage(
            systemSymbolName: presentation.symbolName,
            accessibilityDescription: presentation.accessibilityText) ?? NSImage()
        switch presentation.tint {
        case .template, .dimmed:
            base.isTemplate = true
            return base
        case .amber, .red:
            let color: NSColor = presentation.tint == .amber ? .systemOrange : .systemRed
            let configured = base.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [color])) ?? base
            configured.isTemplate = false
            return configured
        }
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

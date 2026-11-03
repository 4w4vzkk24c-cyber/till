import AppKit
import Foundation
import SwiftUI

/// Immutable value copy of a chip for views, so a view never reads a `ChipEntity` that
/// has just been deleted (SwiftData invalidates deleted models).
struct ChipViewData: Identifiable, Equatable {
    let id: UUID
    let iconId: String
    let iconMonotone: Bool
    let label: String?
    let accentHex: String
    let snapshot: ChipSnapshot

    init(_ entity: ChipEntity) {
        id = entity.id
        iconId = entity.iconId
        iconMonotone = entity.iconMonotone
        label = entity.label
        accentHex = entity.accentHex
        snapshot = entity.snapshot
    }

    func state(at now: Date) -> ChipState { DeadlineState.state(of: snapshot, at: now) }
    func heroText(at now: Date) -> String { HeroTime.format(chip: snapshot, at: now) }
    func accessibilityLabel(at now: Date) -> String {
        Spoken.label(title: label, state: state(at: now), remaining: HeroTime.remaining(of: snapshot, at: now))
    }
}

enum HexColor {
    static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, text.allSatisfy(\.isHexDigit), let value = UInt32(text, radix: 16) else {
            return nil
        }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }
}

extension Color {
    init(hex: String) {
        if let c = HexColor.rgb(hex) {
            self.init(red: c.r, green: c.g, blue: c.b)
        } else {
            self.init(white: 0.7)
        }
    }
}

/// Bundled fallback glyphs (design §5 step 4): SF Symbols referenced as `sf:<name>`.
/// Until `IconProvider` exists every chip uses one of these.
enum FallbackIcons {
    static let defaultID = "sf:timer"
    static let all = [
        "sf:timer", "sf:bell", "sf:cup.and.saucer", "sf:fork.knife",
        "sf:pills", "sf:phone", "sf:car", "sf:flame",
    ]

    static func symbolName(for iconId: String) -> String? {
        iconId.hasPrefix("sf:") ? String(iconId.dropFirst(3)) : nil
    }
}

/// Read-only lookup of the raster cache `IconProvider` will write
/// (`~/Library/Application Support/Till/icons/{prefix}--{name}.png`). Memoized so the 1 s
/// display tick does no file I/O.
@MainActor
enum IconCache {
    private static var memo: [String: NSImage] = [:]

    static func image(for iconId: String) -> NSImage? {
        if let hit = memo[iconId] { return hit }
        let parts = iconId.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let base = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: false)
        else { return nil }
        let url = base.appendingPathComponent("Till/icons/\(parts[0])--\(parts[1]).png")
        guard let image = NSImage(contentsOf: url) else { return nil }
        memo[iconId] = image
        return image
    }
}

struct ChipIconView: View {
    let iconId: String
    let monotone: Bool
    let tint: Color

    var body: some View {
        if let symbol = FallbackIcons.symbolName(for: iconId) {
            Image(systemName: symbol).resizable().scaledToFit().foregroundStyle(tint)
        } else if let image = IconCache.image(for: iconId) {
            if monotone {
                Image(nsImage: image).renderingMode(.template).resizable().scaledToFit()
                    .foregroundStyle(tint)
            } else {
                // Palette icons render as-is, untinted (design §5 step 3).
                Image(nsImage: image).renderingMode(.original).resizable().scaledToFit()
            }
        } else {
            // Cache missing/corrupt: bundled fallback glyph (design §8).
            Image(systemName: FallbackIcons.symbolName(for: FallbackIcons.defaultID) ?? "timer")
                .resizable().scaledToFit().foregroundStyle(tint)
        }
    }
}

import CoreGraphics
import Foundation
import SwiftUI

/// What a chip tile shows for a state, as plain values (spec A2 chip table). The view
/// maps these to colours and glyphs; the decisions live here so they are unit-tested.
struct ChipPresentation: Equatable {
    enum Surface: Equatable { case neutral, dueSoon, overdue, paused }
    enum Control: Equatable { case pause, resume, done }
    /// A semantic colour, mapped to a real colour by `Theme.color(_:accentHex:)`: the colour
    /// decisions live here (unit-tested), the view only draws them.
    enum Tone: Equatable { case primary, secondary, amber, onRed, accent }

    let surface: Surface
    let hero: String
    let control: Control
    let heroTone: Tone
    let iconTone: Tone
    let iconOpacity: Double
    let controlTone: Tone
    let controlHasFill: Bool

    init(state: ChipState, heroText: String) {
        switch state {
        case .clean:
            surface = .neutral; control = .pause
            hero = heroText
            heroTone = .primary; iconTone = .accent; iconOpacity = 1
            controlTone = .primary; controlHasFill = false
        case .approaching:
            surface = .dueSoon; control = .pause
            hero = heroText
            heroTone = .amber; iconTone = .accent; iconOpacity = 1
            controlTone = .primary; controlHasFill = false
        case .overdue:
            // "+41m overdue" renders as hero "+41m": the red fill, the "+" and the Done
            // control say "overdue", so the word is dropped from the digits to fit the tile.
            surface = .overdue; control = .done
            let suffix = " overdue"
            hero = heroText.hasSuffix(suffix) ? String(heroText.dropLast(suffix.count)) : heroText
            heroTone = .onRed; iconTone = .onRed; iconOpacity = 1
            controlTone = .onRed; controlHasFill = true         // light "Done" on a darker strip
        case .paused:
            surface = .paused; control = .resume
            hero = heroText
            heroTone = .secondary; iconTone = .accent; iconOpacity = 0.5
            controlTone = .primary; controlHasFill = false
        }
    }
}

/// Explicit height for the chip grid. The menu-bar window sizes itself from its content's
/// natural height, and a `ScrollView` given only a maximum has almost none, so the window
/// opened too short and clipped the tiles. The height is computed from the chip count, and
/// capped so long lists scroll.
enum ChipGridLayout {
    static let tileHeight: CGFloat = 128      // 16 top + 40 icon + 2 + 28 hero + 2 + 26 control + 14 bottom
    static let gap: CGFloat = 8
    static let maxHeight: CGFloat = 408        // three full rows (400) with room to spare

    static func height(forChips count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let rows = (count + 1) / 2
        let natural = CGFloat(rows) * tileHeight + CGFloat(rows - 1) * gap
        return min(natural, maxHeight)
    }
}

/// Rendering of the hero time. The text is the normative `HeroTime` string; only the space
/// between units ("14h 32m") is drawn a little tighter, because a monospaced space is as
/// wide as a digit (about 16 pt at 26 pt) and read as a gap.
enum ChipHero {
    static let unitSpaceKern: CGFloat = -5

    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString()
        for (index, part) in text.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
            if index > 0 {
                var space = AttributedString(" ")
                space.kern = unitSpaceKern
                result += space
            }
            result += AttributedString(String(part))
        }
        return result
    }
}


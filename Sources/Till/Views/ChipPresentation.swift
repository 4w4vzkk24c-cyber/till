import CoreGraphics
import Foundation

/// What a chip tile shows for a state, as plain values (spec A2 chip table). The view
/// maps these to colours and glyphs; the decisions live here so they are unit-tested.
struct ChipPresentation: Equatable {
    enum Surface: Equatable { case neutral, dueSoon, overdue, paused }
    enum Control: Equatable { case pause, resume, done }

    let surface: Surface
    let hero: String
    let control: Control

    init(state: ChipState, heroText: String) {
        switch state {
        case .clean:
            surface = .neutral; control = .pause
            hero = heroText
        case .approaching:
            surface = .dueSoon; control = .pause
            hero = heroText
        case .overdue:
            // "+41m overdue" renders as hero "+41m": the red fill, the "+" and the Done
            // control say "overdue", so the word is dropped from the digits to fit the tile.
            surface = .overdue; control = .done
            let suffix = " overdue"
            hero = heroText.hasSuffix(suffix) ? String(heroText.dropLast(suffix.count)) : heroText
        case .paused:
            surface = .paused; control = .resume
            hero = heroText
        }
    }
}

/// Explicit height for the chip grid. The menu-bar window sizes itself from its content's
/// natural height, and a `ScrollView` given only a maximum has almost none, so the window
/// opened too short and clipped the tiles. The height is computed from the chip count, and
/// capped so long lists scroll.
enum ChipGridLayout {
    static let tileHeight: CGFloat = 112
    static let gap: CGFloat = 8
    static let maxHeight: CGFloat = 360        // three full rows (352) with room to spare

    static func height(forChips count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let rows = (count + 1) / 2
        let natural = CGFloat(rows) * tileHeight + CGFloat(rows - 1) * gap
        return min(natural, maxHeight)
    }
}

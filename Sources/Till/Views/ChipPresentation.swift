import Foundation

/// What a chip tile shows for a state, as plain values (spec A2 chip table). The view
/// maps these to colours and glyphs; the decisions live here so they are unit-tested.
struct ChipPresentation: Equatable {
    enum Surface: Equatable { case neutral, dueSoon, overdue, paused }
    enum Control: Equatable { case pause, resume, done }

    let surface: Surface
    let hero: String
    let caption: String?
    let control: Control

    init(state: ChipState, heroText: String) {
        switch state {
        case .clean:
            surface = .neutral; caption = nil; control = .pause
            hero = heroText
        case .approaching:
            surface = .dueSoon; caption = "due soon"; control = .pause
            hero = heroText
        case .overdue:
            // "+41m overdue" renders as hero "+41m" with the caption "overdue": a split of
            // the normative HeroTime string, not a format change.
            surface = .overdue; caption = "overdue"; control = .done
            let suffix = " overdue"
            hero = heroText.hasSuffix(suffix) ? String(heroText.dropLast(suffix.count)) : heroText
        case .paused:
            surface = .paused; caption = "paused"; control = .resume
            hero = heroText
        }
    }
}

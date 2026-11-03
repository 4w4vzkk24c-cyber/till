import Foundation

/// Display tick cadence, seed verbatim (design §7.4, TRC-01): "1s while a chip is visible
/// or within its final stretch, 30s otherwise." "Visible" = the popover is open; "final
/// stretch" = an active chip in the Approaching state (remaining <= its approachWindow).
enum TickCadence {
    static let active: TimeInterval = 1
    static let idle: TimeInterval = 30

    static func interval(popoverOpen: Bool, chips: [ChipSnapshot], now: Date) -> TimeInterval {
        if popoverOpen { return active }
        for chip in chips where DeadlineState.state(of: chip, at: now) == .approaching {
            return active
        }
        return idle
    }
}

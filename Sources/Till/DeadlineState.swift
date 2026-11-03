import Foundation

/// Value snapshot of a chip, as seen by the pure state machine (design §7.3).
public struct ChipSnapshot: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let deadline: Date
    public let pausedAt: Date?
    public let approachWindow: TimeInterval

    public init(id: UUID, deadline: Date, pausedAt: Date? = nil, approachWindow: TimeInterval) {
        self.id = id
        self.deadline = deadline
        self.pausedAt = pausedAt
        self.approachWindow = approachWindow
    }
}

public enum ChipState: Sendable, Equatable {
    case clean, approaching, overdue, paused
}

public enum BarIconState: Sendable, Equatable {
    case normal
    case amber
    case red(overdueCount: Int)
    case dimmed
}

/// Pure functions of (deadline, now, pausedAt, approachWindow). No clock inside:
/// `now` is always injected (design §7.3).
public enum DeadlineState {

    /// Precedence (design §6): Paused, else deadline <= now -> Overdue,
    /// else remaining <= approachWindow -> Approaching, else Clean.
    public static func state(of chip: ChipSnapshot, at now: Date) -> ChipState {
        if chip.pausedAt != nil { return .paused }
        if chip.deadline <= now { return .overdue }
        if chip.deadline.timeIntervalSince(now) <= chip.approachWindow { return .approaching }
        return .clean
    }

    /// Bar escalation over ALL chips; paused chips are excluded here.
    /// Overdue > Approaching > Clean. No active chips (none, or all paused) -> dimmed.
    public static func barEscalation(of chips: [ChipSnapshot], at now: Date) -> BarIconState {
        var overdue = 0
        var approaching = 0
        var clean = 0
        for chip in chips {
            switch state(of: chip, at: now) {
            case .overdue: overdue += 1
            case .approaching: approaching += 1
            case .clean: clean += 1
            case .paused: break
            }
        }
        if overdue > 0 { return .red(overdueCount: overdue) }
        if approaching > 0 { return .amber }
        if clean > 0 { return .normal }
        return .dimmed
    }

    /// The worst active chip: Overdue > Approaching > Clean, nearest deadline wins
    /// ties, then id (deterministic). Nil when nothing is active.
    public static func driver(of chips: [ChipSnapshot], at now: Date) -> ChipSnapshot? {
        func rank(_ s: ChipState) -> Int {
            switch s {
            case .overdue: return 3
            case .approaching: return 2
            case .clean: return 1
            case .paused: return 0
            }
        }
        var best: ChipSnapshot?
        var bestRank = 0
        for chip in chips {
            let r = rank(state(of: chip, at: now))
            if r == 0 { continue }
            if let current = best {
                if r > bestRank
                    || (r == bestRank && chip.deadline < current.deadline)
                    || (r == bestRank && chip.deadline == current.deadline
                        && chip.id.uuidString < current.id.uuidString) {
                    best = chip
                    bestRank = r
                }
            } else {
                best = chip
                bestRank = r
            }
        }
        return best
    }

    /// Display order for the grid (addendum A1.1 item 3): deadline ascending, id tie-break.
    public static func displayOrder(_ chips: [ChipSnapshot]) -> [ChipSnapshot] {
        chips.sorted {
            if $0.deadline != $1.deadline { return $0.deadline < $1.deadline }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

/// Hero time text (design §4, normative). Seconds/minutes floor.
public enum HeroTime {

    /// remaining > 0: `3d 14h` (>= 24h), `14h 32m` (>= 1h), `32:41` (< 1h).
    /// remaining <= 0: `+2h overdue` (>= 1h), `+41m overdue` (< 1h, floor at minutes).
    /// The spec is silent on overdue >= 24h; this renders hours (`+50h overdue`).
    public static func format(remaining: TimeInterval) -> String {
        if remaining > 0 {
            let total = Int(remaining.rounded(.down))
            if total >= 86_400 {
                return "\(total / 86_400)d \((total % 86_400) / 3_600)h"
            }
            if total >= 3_600 {
                return "\(total / 3_600)h \((total % 3_600) / 60)m"
            }
            let minutes = total / 60
            let seconds = total % 60
            return "\(minutes):" + (seconds < 10 ? "0" : "") + "\(seconds)"
        }
        let over = Int((-remaining).rounded(.down))
        if over >= 3_600 { return "+\(over / 3_600)h overdue" }
        return "+\(over / 60)m overdue"
    }

    /// Remaining seconds shown for a chip: live for active chips, frozen
    /// (`deadline - pausedAt`) for paused ones.
    public static func remaining(of chip: ChipSnapshot, at now: Date) -> TimeInterval {
        if let pausedAt = chip.pausedAt {
            return chip.deadline.timeIntervalSince(pausedAt)
        }
        return chip.deadline.timeIntervalSince(now)
    }

    public static func format(chip: ChipSnapshot, at now: Date) -> String {
        format(remaining: remaining(of: chip, at: now))
    }
}

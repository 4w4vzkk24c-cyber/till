import Foundation
import Observation

/// The add/edit field's state machine (design §5 creation sequence):
/// parse -> time prompt (date-only input) -> persist -> schedule.
/// Errors are inline hints, never dialogs. Icon fetch is not part of this pass: new chips
/// use the bundled fallback glyph (see addendum A1.8).
@MainActor
@Observable
final class CreationFlow {
    enum Phase: Equatable {
        case idle
        case awaitingTime(ParsedDeadline)
    }

    var input = ""
    var label = ""
    var promptHour = NaturalDeadline.suggestedHour
    var promptMinute = 0

    private(set) var phase: Phase = .idle
    private(set) var errorHint: String?
    private(set) var editingID: UUID?
    private(set) var isBusy = false

    @ObservationIgnored private let store: TimerStore
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let timeZone: TimeZone

    static let accents = ["#F5A623", "#4FC3F7", "#81C784", "#BA68C8", "#FF8A65", "#FFD54F"]
    static let genericHint = "Couldn’t save that. Try again."

    init(
        store: TimerStore,
        clock: @escaping @MainActor () -> Date = { Date() },
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) {
        self.store = store
        self.clock = clock
        self.calendar = calendar
        self.timeZone = timeZone
    }

    // MARK: - Entry points

    func submit() async {
        guard !isBusy, phase == .idle else { return }
        errorHint = nil
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Editing with a blank deadline field keeps the deadline (label-only edit).
        if let id = editingID, text.isEmpty {
            await run { try await self.store.edit(id: id, label: self.cleanLabel, deadline: nil) }
            return
        }
        do {
            let parsed = try NaturalDeadline.parse(
                text, now: clock(), calendar: calendar, timeZone: timeZone)
            if parsed.timePromptRequired {
                promptHour = NaturalDeadline.suggestedHour
                promptMinute = 0
                phase = .awaitingTime(parsed)
                return
            }
            await commit(parsed)
        } catch let error as NaturalDeadlineError {
            errorHint = error.hint
        } catch {
            errorHint = Self.genericHint
        }
    }

    /// Accepts the time chosen in the prompt (09:00 pre-filled; one tap to accept).
    func confirmTime() async {
        guard !isBusy, case .awaitingTime(let parsed) = phase else { return }
        errorHint = nil
        do {
            let final = try NaturalDeadline.applyingTime(
                hour: promptHour, minute: promptMinute, to: parsed,
                now: clock(), calendar: calendar, timeZone: timeZone)
            await commit(final)
        } catch let error as NaturalDeadlineError {
            errorHint = error.hint           // stays in the prompt so the user can pick again
        } catch {
            errorHint = Self.genericHint
        }
    }

    /// Cancels the time prompt or edit mode; nothing is persisted.
    func cancel() {
        reset()
    }

    func beginEdit(id: UUID, label: String?) {
        reset()
        editingID = id
        self.label = label ?? ""
    }

    /// Runs a chip action (pause, resume, done) and surfaces any failure inline.
    func perform(_ work: () async throws -> Void) async {
        errorHint = nil
        do {
            try await work()
        } catch {
            errorHint = Self.message(for: error)
        }
    }

    // MARK: - Internals

    private var cleanLabel: String? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func commit(_ parsed: ParsedDeadline) async {
        if let id = editingID {
            await run { try await self.store.edit(id: id, label: self.cleanLabel, deadline: parsed) }
        } else {
            let accent = Self.accents[store.chips.count % Self.accents.count]
            let new = NewChip(
                iconId: FallbackIcons.defaultID, iconMonotone: true, label: cleanLabel,
                accentHex: accent, parsed: parsed)
            await run { try await self.store.createChip(new) }
        }
    }

    private func run<T>(_ work: () async throws -> T) async {
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await work()
            reset()
        } catch {
            errorHint = Self.message(for: error)
            if let storeError = error as? TimerStoreError, storeError == .notFound {
                let hint = errorHint
                reset()
                errorHint = hint
            }
        }
    }

    private func reset() {
        input = ""
        label = ""
        phase = .idle
        editingID = nil
        errorHint = nil
        promptHour = NaturalDeadline.suggestedHour
        promptMinute = 0
    }

    static func message(for error: Error) -> String {
        if let e = error as? NaturalDeadlineError { return e.hint }
        if let e = error as? TimerStoreError {
            switch e {
            case .notFound: return "That timer no longer exists."
            case .deadlineInPast: return "That time has already passed."
            case .cannotPauseOverdue: return "An overdue timer can’t be paused. Mark it Done."
            case .alreadyPaused, .notPaused: return "That timer’s state changed. Try again."
            }
        }
        return genericHint
    }
}

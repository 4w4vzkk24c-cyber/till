import Foundation
import Observation

/// The add/edit field's state machine (design §5 creation sequence):
/// parse -> time prompt (date-only input) -> persist -> schedule.
/// Errors are inline hints, never dialogs. The icon fetch is the only network step: it
/// happens after the time prompt and before persist, Enter is inert while it runs, and
/// dismissing the popover cancels it (`cancelInFlight`). A built-in (`sf:`) icon never
/// touches the network.
@MainActor
@Observable
final class CreationFlow {
    enum Phase: Equatable {
        case idle
        case awaitingTime(ParsedDeadline)
    }

    var input = ""
    var promptHour = NaturalDeadline.suggestedHour
    var promptMinute = 0

    private(set) var phase: Phase = .idle
    private(set) var errorHint: String?
    private(set) var editingID: UUID?
    private(set) var isBusy = false
    /// True while the creation-time icon fetch is in flight (shown as a static caption).
    private(set) var isFetchingIcon = false
    private(set) var selectedIcon = IconChoice.fallbackDefault
    var pickerOpen = false

    @ObservationIgnored private let store: TimerStore
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private let iconProvider: (any IconFetching)?
    @ObservationIgnored private var creationTask: Task<Void, Never>?
    /// Bumped by every cancel/reset so a result from a superseded attempt is dropped
    /// (addendum A1.1 item 8; cancellation alone is cooperative).
    @ObservationIgnored private var generation = 0

    /// Identity colours for new chips, kept out of the state hues (amber and red mean state).
    nonisolated static let accents = ["#6FCFFF", "#8FE0A0", "#D2A4FF", "#FF93C9", "#5EE0CF", "#A8B1FF"]
    static let genericHint = "Couldn’t save that. Try again."

    init(
        store: TimerStore,
        clock: @escaping @MainActor () -> Date = { Date() },
        calendar: Calendar = .current,
        timeZone: TimeZone = .current,
        iconProvider: (any IconFetching)? = nil
    ) {
        self.iconProvider = iconProvider
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

    /// View entry point: runs `submit()` in a task the flow owns so it can be cancelled.
    func startSubmit() {
        creationTask = Task { await self.submit() }
    }

    /// Popover dismissed: abandon any in-flight creation. No chip exists yet at that
    /// stage, so there is nothing to roll back.
    func cancelInFlight() {
        generation += 1
        creationTask?.cancel()
        creationTask = nil
        isFetchingIcon = false
        isBusy = false
    }

    func selectIcon(_ choice: IconChoice) {
        selectedIcon = choice
        pickerOpen = false
    }

    func beginEdit(id: UUID) {
        reset()
        editingID = id
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

    private func commit(_ parsed: ParsedDeadline) async {
        if let id = editingID {
            await run { try await self.store.edit(id: id, deadline: parsed) }
        } else {
            let gen = generation
            let accent = Self.accents[store.chips.count % Self.accents.count]
            await run {
                var icon = self.selectedIcon
                if !icon.isBuiltIn {
                    icon = try await self.resolveIcon(icon, generation: gen)   // the only network step
                }
                guard gen == self.generation else { throw CancellationError() }
                return try await self.store.createChip(
                    NewChip(
                        iconId: icon.id, iconMonotone: icon.monotone,
                        accentHex: accent, parsed: parsed))
            }
        }
    }

    /// Fetches (or reads from cache) the chosen icon; its detected monotone flag replaces
    /// the picker's hint.
    private func resolveIcon(_ choice: IconChoice, generation gen: Int) async throws -> IconChoice {
        guard let provider = iconProvider else { throw IconError.invalidIconID }
        isFetchingIcon = true
        defer { if gen == generation { isFetchingIcon = false } }
        let asset = try await provider.fetch(id: choice.id)
        try Task.checkCancellation()
        guard gen == generation else { throw CancellationError() }
        return IconChoice(
            id: asset.id, monotone: asset.monotone,
            collectionName: choice.collectionName, licenseTitle: choice.licenseTitle)
    }

    private func run<T>(_ work: () async throws -> T) async {
        isBusy = true
        let gen = generation
        defer { if gen == generation { isBusy = false } }
        do {
            _ = try await work()
            if gen == generation { reset() }
        } catch is CancellationError {
            return                                   // superseded or dismissed: stay silent
        } catch {
            guard gen == generation else { return }
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
        phase = .idle
        editingID = nil
        errorHint = nil
        promptHour = NaturalDeadline.suggestedHour
        promptMinute = 0
        selectedIcon = IconChoice.fallbackDefault
        pickerOpen = false
        isFetchingIcon = false
    }

    static func message(for error: Error) -> String {
        if let e = error as? NaturalDeadlineError { return e.hint }
        if let e = error as? IconError { return e.hint }
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

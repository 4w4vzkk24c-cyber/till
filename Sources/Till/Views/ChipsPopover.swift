import AppKit
import SwiftUI

/// The MenuBarExtra window content (design §4, §7.5; spec A2): the composer on top, a
/// two-column grid of chips below, the gear menu beside the composer. No secondary
/// windows, no animation.
struct ChipsPopover: View {
    let store: TimerStore
    @Bindable var creation: CreationFlow
    let loginItems: LoginItemController
    let picker: IconPickerModel?
    let loadError: String?

    @FocusState private var addFieldFocused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let columns = [
        GridItem(.flexible(), spacing: Theme.Space.s),
        GridItem(.flexible(), spacing: Theme.Space.s),
    ]
    private static let examples = ["in 20 min", "Fri 5pm", "Nov 15"]

    var body: some View {
        let theme = Theme(scheme, contrast)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            ComposerView(
                store: store, creation: creation, loginItems: loginItems,
                picker: picker, focus: $addFieldFocused)
            chipsGrid(theme)
        }
        .padding(Theme.Space.pad)
        .frame(width: 340)
        .background { theme.trayTint(reduceTransparency: reduceTransparency) }
        .transaction { $0.animation = nil }          // static swaps only (settled)
        .onAppear {
            store.popoverOpen = true
            addFieldFocused = true                    // A1.5 default; operator may veto
            loginItems.refresh()
            Task { await store.refreshAuthorization() }
        }
        .onDisappear {
            store.popoverOpen = false
            creation.cancelInFlight()         // dismissing cancels an in-flight icon fetch
            picker?.cancel()
        }
    }

    // MARK: - Chips

    @ViewBuilder
    private func chipsGrid(_ theme: Theme) -> some View {
        let items = store.chips.map(ChipViewData.init)
        if items.isEmpty {
            emptyState(theme)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                    ForEach(items) { item in
                        ChipCardView(
                            data: item, now: store.now,
                            onPauseResume: { pauseOrResume(item) },
                            onDone: { done(item) },
                            onEdit: { creation.beginEdit(id: item.id, label: item.label) })
                    }
                }
            }
            .frame(maxHeight: 470)
        }
    }

    /// An invitation, not an apology: the examples are the parser's real inputs and fill
    /// the field when pressed.
    private func emptyState(_ theme: Theme) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.system(size: 40))
                .foregroundStyle(theme.ink3)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            Text("Nothing counting down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.ink)
            Text("Type when it’s due. Till tells you when time’s up.")
                .font(.system(size: 13))
                .foregroundStyle(theme.ink2)
                .multilineTextAlignment(.center)
            HStack(spacing: Theme.Space.s) {
                ForEach(Self.examples, id: \.self) { example in
                    Button {
                        creation.input = example
                        addFieldFocused = true
                    } label: {
                        Text(example)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.ink)
                            .padding(.horizontal, Theme.Space.m)
                            .padding(.vertical, Theme.Space.s)
                            .background(theme.tile, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, Theme.Space.m)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func pauseOrResume(_ item: ChipViewData) {
        Task {
            await creation.perform {
                if item.snapshot.pausedAt == nil {
                    try store.pause(id: item.id)
                } else {
                    try await store.resume(id: item.id)
                }
            }
        }
    }

    private func done(_ item: ChipViewData) {
        Task { await creation.perform { try store.markDone(id: item.id) } }
    }
}

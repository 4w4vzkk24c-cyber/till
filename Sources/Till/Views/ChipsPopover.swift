import AppKit
import SwiftUI

/// The MenuBarExtra window content (design §4, §7.5): header with the add field, a
/// two-column grid of chips, and a footer with settings and Quit. No secondary windows,
/// no animation.
struct ChipsPopover: View {
    let store: TimerStore
    @Bindable var creation: CreationFlow
    let loginItems: LoginItemController
    let loadError: String?

    @FocusState private var addFieldFocused: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            header
            chipsGrid
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
        .transaction { $0.animation = nil }          // static swaps only (settled)
        .onAppear {
            store.popoverOpen = true
            addFieldFocused = true                    // A1.5 default; operator may veto
            loginItems.refresh()
            Task { await store.refreshAuthorization() }
        }
        .onDisappear { store.popoverOpen = false }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if creation.editingID != nil {
                HStack {
                    Text("Editing — leave the deadline blank to keep it")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { creation.cancel() }
                        .buttonStyle(.plain)
                        .font(.caption)
                }
            }

            TextField(
                creation.editingID == nil ? "in 20 min · Fri 5pm · Nov 15" : "New deadline (optional)",
                text: $creation.input
            )
            .textFieldStyle(.roundedBorder)
            .focused($addFieldFocused)
            .disabled(creation.phase != .idle)
            .onSubmit { Task { await creation.submit() } }
            .accessibilityLabel("Deadline")

            TextField("Label (optional)", text: $creation.label)
                .textFieldStyle(.roundedBorder)
                .disabled(creation.phase != .idle)
                .onSubmit { Task { await creation.submit() } }
                .accessibilityLabel("Label")

            if case .awaitingTime = creation.phase {
                HStack {
                    Text("At what time?")
                        .font(.caption)
                    DatePicker("Time", selection: promptTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Button("Set") { Task { await creation.confirmTime() } }
                        .keyboardShortcut(.defaultAction)
                    Button("Cancel") { creation.cancel() }
                }
            }

            if let hint = creation.errorHint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Error: \(hint)")
            }
        }
    }

    private var promptTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: creation.promptHour, minute: creation.promptMinute,
                    second: 0, of: Date()) ?? Date()
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                creation.promptHour = parts.hour ?? NaturalDeadline.suggestedHour
                creation.promptMinute = parts.minute ?? 0
            })
    }

    // MARK: - Chips

    @ViewBuilder
    private var chipsGrid: some View {
        let items = store.chips.map(ChipViewData.init)
        if items.isEmpty {
            Text("No timers. Type a deadline above.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(items) { item in
                        ChipCardView(
                            data: item, now: store.now,
                            onPauseResume: { pauseOrResume(item) },
                            onDone: { done(item) },
                            onEdit: { creation.beginEdit(id: item.id, label: item.label) })
                    }
                }
            }
            .frame(maxHeight: 420)
        }
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

    // MARK: - Footer (settings row + Quit; no secondary windows)

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Notifications", isOn: notificationsBinding)
                .disabled(store.authorization == .denied)
            if store.authorization == .denied {
                HStack(spacing: 4) {
                    Text("Notifications are turned off for Till in System Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link(
                        "Open",
                        destination: URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        .font(.caption)
                }
            }

            Toggle("Open at login", isOn: loginBinding)
            if loginItems.needsApproval {
                HStack(spacing: 4) {
                    Text("Approve Till in Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open") { loginItems.openSystemSettings() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            if let error = loginItems.errorText {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Quit Till") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { store.notificationsEnabled },
            set: { value in Task { await store.setNotificationsEnabled(value) } })
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { loginItems.isOn },
            set: { loginItems.setEnabled($0) })
    }
}

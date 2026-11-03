import SwiftUI

/// The add/edit composer (spec A2): one pill holding the icon tile, the deadline field and
/// the optional label, the gear beside it, one status line, the time prompt, and the
/// inline icon picker. Behavior is `CreationFlow`'s; this view only lays it out.
struct ComposerView: View {
    let store: TimerStore
    @Bindable var creation: CreationFlow
    let loginItems: LoginItemController
    let picker: IconPickerModel?
    var focus: FocusState<Bool>.Binding

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let theme = Theme(scheme, contrast)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                pill(theme)
                SettingsMenu(store: store, loginItems: loginItems)
            }
            statusLine(theme)
            timePrompt(theme)
            if creation.editingID == nil, creation.pickerOpen, let picker {
                IconPickerView(model: picker, creation: creation)
            }
        }
    }

    // MARK: - Pill

    private func pill(_ theme: Theme) -> some View {
        let adding = creation.editingID == nil
        return HStack(spacing: Theme.Space.s) {
            if adding { iconTile(theme) }
            TextField(adding ? "in 20 min, Fri 5pm" : "New deadline (optional)", text: $creation.input)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused(focus)
                .disabled(creation.phase != .idle)
                .onSubmit { creation.startSubmit() }
                .accessibilityLabel("Deadline")
            TextField("Label", text: $creation.label)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
                .disabled(creation.phase != .idle)
                .onSubmit { creation.startSubmit() }
                .accessibilityLabel("Label")
        }
        .padding(.leading, adding ? 7 : 14)
        .padding(.trailing, 12)
        .frame(height: 40)
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
            shape.fill(theme.tile).overlay(shape.strokeBorder(theme.hairline, lineWidth: 0.5))
        }
    }

    private func iconTile(_ theme: Theme) -> some View {
        Button {
            if picker != nil { creation.pickerOpen.toggle() }
        } label: {
            ChipIconView(
                iconId: creation.selectedIcon.id, monotone: creation.selectedIcon.monotone,
                tint: theme.ink)
                .frame(width: 16, height: 16)
                .frame(width: 26, height: 26)
                .background(Circle().fill(theme.tile))
        }
        .buttonStyle(.plain)
        .disabled(picker == nil || creation.phase != .idle)
        .accessibilityLabel("Choose icon")
        .help("Choose icon")
    }

    // MARK: - Status line

    @ViewBuilder
    private func statusLine(_ theme: Theme) -> some View {
        let echo = (creation.editingID == nil && creation.phase == .idle)
            ? ParseEcho.text(
                for: creation.input, now: store.now, calendar: .current, timeZone: .current)
            : nil
        switch ComposerStatus.line(
            error: creation.errorHint, fetching: creation.isFetchingIcon,
            editing: creation.editingID != nil, echo: echo)
        {
        case .error(let message):
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Color.white)
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, Theme.Space.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Theme.overdueFill.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .accessibilityLabel("Error: \(message)")
        case .fetching:
            // Static caption, no spinner: no animation anywhere (design §4, §5).
            Text("Fetching icon…")
                .font(.system(size: 12))
                .foregroundStyle(theme.ink2)
                .padding(.horizontal, Theme.Space.m)
        case .editing:
            HStack {
                Text("Editing. Leave the deadline blank to keep it.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.ink2)
                Spacer()
                Button("Cancel") { creation.cancel() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.ink)
            }
            .padding(.horizontal, Theme.Space.m)
        case .echo(let text):
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(theme.ink2)
                .padding(.horizontal, Theme.Space.m)
        case nil:
            EmptyView()
        }
    }

    // MARK: - Time prompt

    @ViewBuilder
    private func timePrompt(_ theme: Theme) -> some View {
        if case .awaitingTime = creation.phase {
            HStack(spacing: Theme.Space.s) {
                Text("At what time?")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.ink2)
                DatePicker("Time", selection: promptTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Spacer()
                Button("Cancel") { creation.cancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Set") { Task { await creation.confirmTime() } }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Theme.Space.m)
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
}

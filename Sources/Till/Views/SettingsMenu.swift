import AppKit
import SwiftUI

/// The gear: Notifications, Open at login and Quit (replaces the footer, spec A2). Quit
/// stays discoverable because the app has no ordinary windows. An amber dot says a
/// setting needs attention.
struct SettingsMenu: View {
    let store: TimerStore
    let loginItems: LoginItemController

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    private static let notificationSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!

    var body: some View {
        let theme = Theme(scheme, contrast)
        let badge = SettingsAttention.needsBadge(
            authorization: store.authorization,
            notificationsEnabled: store.notificationsEnabled,
            loginNeedsApproval: loginItems.needsApproval,
            loginError: loginItems.errorText)

        Menu {
            Toggle("Notifications", isOn: notificationsBinding)
                .disabled(store.authorization == .denied)
            if store.authorization == .denied {
                Button("Notifications are off for Till. Open System Settings…") {
                    NSWorkspace.shared.open(Self.notificationSettingsURL)
                }
            }
            Toggle("Open at login", isOn: loginBinding)
            if loginItems.needsApproval {
                Button("Approve Till in Login Items…") { loginItems.openSystemSettings() }
            }
            if let error = loginItems.errorText {
                Text(error)
            }
            Divider()
            Button("Quit Till") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 16))
                .foregroundStyle(theme.ink3)
                .frame(width: 32, height: 32)
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle().fill(theme.amber).frame(width: 9, height: 9).padding(4)
                    }
                }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(badge ? "Settings, needs attention" : "Settings")
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

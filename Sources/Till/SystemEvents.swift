import AppKit
import Foundation
import UserNotifications

/// Wake / activation observers. AppKit data/event APIs only (design §1).
@MainActor
final class SystemEventObserver {
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    func start(store: TimerStore, loginItems: LoginItemController) {
        guard observers.isEmpty else { return }

        // Wake: the display clock catches up and reconciliation runs (design §7.4).
        add(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) {
            Task { @MainActor in
                store.tick()
                await store.reconcile()
            }
        }
        // App became active: authorization re-check (FR-01). Also the popover-open signal
        // for an agent app; the view's onAppear is the primary one (addendum A1.8).
        add(.default, NSApplication.didBecomeActiveNotification) {
            Task { @MainActor in
                store.popoverOpen = true
                loginItems.refresh()
                await store.refreshAuthorization()
            }
        }
        add(.default, NSApplication.didResignActiveNotification) {
            Task { @MainActor in store.popoverOpen = false }
        }
    }

    func stop() {
        for entry in observers { entry.center.removeObserver(entry.token) }
        observers.removeAll()
    }

    private func add(
        _ center: NotificationCenter, _ name: Notification.Name,
        handler: @escaping @Sendable () -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in handler() }
        observers.append((center, token))
    }
}

/// Marks a delivery as observed (sets `zeroCrossingHandled`, design §7.4) and lets
/// notifications show as banners while the app is active.
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let store: TimerStore

    init(store: TimerStore) {
        self.store = store
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let identifier = notification.request.identifier
        await MainActor.run { self.observed(identifier) }
        return [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        await MainActor.run { self.observed(identifier) }
    }

    private func observed(_ identifier: String) {
        guard let id = SystemNotificationScheduler.chipID(from: identifier) else { return }
        try? store.handleDeliveryObserved(chipID: id)
    }
}

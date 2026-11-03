import Foundation
import UserNotifications

enum NotificationAuthorization: Sendable, Equatable {
    case notDetermined, denied, authorized
}

struct NotificationContent: Sendable, Equatable {
    let title: String
    let body: String
}

/// Seam over UNUserNotificationCenter so the store's scheduling and reconciliation logic
/// is testable with a mock (design §11). All members run on the main actor.
@MainActor
protocol NotificationScheduling: AnyObject {
    func authorizationStatus() async -> NotificationAuthorization
    func requestAuthorization() async -> Bool
    /// Schedules (or replaces) the one calendar-trigger request for this chip.
    func schedule(id: UUID, content: NotificationContent, at date: Date) async throws
    /// Delivers immediately under the chip's identifier.
    func fireNow(id: UUID, content: NotificationContent) async throws
    func removePending(ids: [UUID])
    func pendingIDs() async -> Set<UUID>
    func deliveredIDs() async -> Set<UUID>
}

/// Real implementation. NOT covered by automated tests; compile-checked only until the
/// delegate wiring and a manual notification pass happen on a Mac.
@MainActor
final class SystemNotificationScheduler: NotificationScheduling {
    private let center: UNUserNotificationCenter
    private static let prefix = "till.chip."

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    static func identifier(for id: UUID) -> String { prefix + id.uuidString }

    static func chipID(from identifier: String) -> UUID? {
        guard identifier.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(prefix.count)))
    }

    func authorizationStatus() async -> NotificationAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorized, .provisional: return .authorized
        default: return .denied
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func schedule(id: UUID, content: NotificationContent, at date: Date) async throws {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.identifier(for: id), content: Self.make(content), trigger: trigger)
        try await center.add(request)
    }

    func fireNow(id: UUID, content: NotificationContent) async throws {
        let request = UNNotificationRequest(
            identifier: Self.identifier(for: id), content: Self.make(content), trigger: nil)
        try await center.add(request)
    }

    func removePending(ids: [UUID]) {
        center.removePendingNotificationRequests(withIdentifiers: ids.map(Self.identifier(for:)))
    }

    func pendingIDs() async -> Set<UUID> {
        let requests = await center.pendingNotificationRequests()
        return Set(requests.compactMap { Self.chipID(from: $0.identifier) })
    }

    func deliveredIDs() async -> Set<UUID> {
        let delivered = await center.deliveredNotifications()
        return Set(delivered.compactMap { Self.chipID(from: $0.request.identifier) })
    }

    private static func make(_ content: NotificationContent) -> UNMutableNotificationContent {
        let result = UNMutableNotificationContent()
        result.title = content.title
        result.body = content.body
        result.sound = .default
        return result
    }
}

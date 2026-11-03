import Foundation
@testable import Till

@MainActor
final class ClockBox {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@MainActor
final class FailureSwitch {
    var failSaves = false
}

@MainActor
final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

struct SaveFailure: Error {}
struct ScheduleFailure: Error {}

@MainActor
final class MockScheduler: NotificationScheduling {
    struct Scheduled: Equatable {
        let id: UUID
        let date: Date
        let title: String
    }

    var status: NotificationAuthorization = .authorized
    var requestResult = true
    var pending: Set<UUID> = []
    var delivered: Set<UUID> = []
    var scheduleError: Error?

    private(set) var scheduled: [Scheduled] = []
    private(set) var fired: [UUID] = []
    private(set) var removed: [UUID] = []
    private(set) var requestCount = 0
    private(set) var pendingReadCount = 0

    var onSchedule: (@MainActor () -> Void)?
    var onPendingRead: (@MainActor () async -> Void)?

    func authorizationStatus() async -> NotificationAuthorization { status }

    func requestAuthorization() async -> Bool {
        requestCount += 1
        status = requestResult ? .authorized : .denied
        return requestResult
    }

    func schedule(id: UUID, content: NotificationContent, at date: Date) async throws {
        onSchedule?()
        if let scheduleError { throw scheduleError }
        scheduled.append(Scheduled(id: id, date: date, title: content.title))
        pending.insert(id)
    }

    func fireNow(id: UUID, content: NotificationContent) async throws {
        fired.append(id)
        delivered.insert(id)
    }

    func removePending(ids: [UUID]) {
        removed.append(contentsOf: ids)
        pending.subtract(ids)
    }

    func pendingIDs() async -> Set<UUID> {
        pendingReadCount += 1
        await onPendingRead?()
        return pending
    }

    func deliveredIDs() async -> Set<UUID> { delivered }
}

import Foundation
import Observation
import SwiftData
import UserNotifications

/// Composition root (design §7.4 "Creation point: app start"). Owns the container, store,
/// flow, login item and system observers for the app's lifetime.
@MainActor
@Observable
final class AppModel {
    let store: TimerStore
    let creation: CreationFlow
    let loginItems: LoginItemController
    private(set) var loadError: String?

    @ObservationIgnored private let observer = SystemEventObserver()
    @ObservationIgnored private var notificationDelegate: NotificationDelegate?

    /// Under XCTest/swift-testing the app is only a host: do not touch the user's real
    /// store, observers, or notification center.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    init() {
        let testing = Self.isRunningTests
        var message: String?
        let container: ModelContainer
        if testing {
            container = Self.inMemoryContainer()
        } else {
            do {
                container = try TillPersistence.makeContainer(inMemory: false, storeURL: try Self.storeURL())
            } catch {
                // Never delete or overwrite the user's data automatically. Run from memory
                // and say so; the on-disk store is left untouched for recovery.
                message = "Couldn’t open your saved timers. Changes this session won’t be saved."
                container = Self.inMemoryContainer()
            }
        }
        loadError = message

        let scheduler = SystemNotificationScheduler()
        let defaults: UserDefaults = testing
            ? (UserDefaults(suiteName: "till.apphost.\(UUID().uuidString)") ?? .standard)
            : .standard
        let store = TimerStore(container: container, scheduler: scheduler, defaults: defaults)
        self.store = store
        self.creation = CreationFlow(store: store)
        self.loginItems = LoginItemController(service: SMAppServiceLoginItem())

        guard !testing else { return }
        let delegate = NotificationDelegate(store: store)
        notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
        observer.start(store: store, loginItems: loginItems)
        Task { [weak self] in
            do {
                try await store.start()
            } catch {
                self?.loadError = "Couldn’t load your saved timers."
            }
            store.startTicking()
        }
    }

    private static func inMemoryContainer() -> ModelContainer {
        do {
            return try TillPersistence.makeContainer(inMemory: true)
        } catch {
            fatalError("Till: in-memory SwiftData container failed: \(error)")
        }
    }

    private static func storeURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("Till", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("till.store")
    }
}

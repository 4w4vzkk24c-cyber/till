import Foundation
import Observation
import os
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
    let picker: IconPickerModel?
    private(set) var loadError: String?

    @ObservationIgnored private let observer = SystemEventObserver()
    @ObservationIgnored private var notificationDelegate: NotificationDelegate?

    /// Under XCTest/swift-testing the app is only a host: do not touch the user's real
    /// store, observers, or notification center.
    static var isRunningTests: Bool { TestHostSignals.current().isTesting }

    init() {
        let signals = TestHostSignals.current()
        let testing = signals.isTesting
        Logger(subsystem: "com.crossedkeys.till", category: "launch").notice(
            "testing=\(testing, privacy: .public) configurationFile=\(signals.configurationFile, privacy: .public) sessionIdentifier=\(signals.sessionIdentifier, privacy: .public) xctestClass=\(signals.xctestClassLoaded, privacy: .public)")
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
        self.loginItems = LoginItemController(service: SMAppServiceLoginItem())

        // The icon service is the only network use and is never created under test.
        var madeProvider: IconProvider?
        if !testing {
            let cache = (try? IconProvider.defaultCacheDirectory())
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("Till-icons", isDirectory: true)
            madeProvider = IconProvider(network: URLSessionIconNetworking(), cacheDirectory: cache)
        }
        self.creation = CreationFlow(store: store, iconProvider: madeProvider)
        self.picker = madeProvider.map { IconPickerModel(provider: $0) }

        guard !testing, let provider = madeProvider else { return }
        // Evict cached icons no chip references (unreferenced files get a grace period).
        store.onChipsReloaded = { ids in
            Task { await provider.evictUnreferenced(Set(ids)) }
        }
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

/// Which "this process is a test host" signals fired. Kept separate so a launch log can
/// show which one tripped (handoff H1: the XCTestCase class check may misfire).
struct TestHostSignals: Equatable {
    let configurationFile: Bool
    let sessionIdentifier: Bool
    let xctestClassLoaded: Bool

    var isTesting: Bool { configurationFile || sessionIdentifier || xctestClassLoaded }

    static func current() -> TestHostSignals {
        let env = ProcessInfo.processInfo.environment
        return TestHostSignals(
            configurationFile: env["XCTestConfigurationFilePath"] != nil,
            sessionIdentifier: env["XCTestSessionIdentifier"] != nil,
            xctestClassLoaded: NSClassFromString("XCTestCase") != nil)
    }
}

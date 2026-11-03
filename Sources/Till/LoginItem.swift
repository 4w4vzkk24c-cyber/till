import Foundation
import Observation
import ServiceManagement

enum LoginItemStatus: Equatable {
    case notRegistered, enabled, requiresApproval, notFound
}

@MainActor
protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

/// `SMAppService.mainApp` (macOS 13+). Registration is attempted only when the user turns
/// the toggle on; status is re-read afterwards (capabilities reference).
@MainActor
final class SMAppServiceLoginItem: LoginItemService {
    private let service = SMAppService.mainApp

    var status: LoginItemStatus {
        switch service.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .notRegistered
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }

    func register() throws { try service.register() }
    func unregister() throws { try service.unregister() }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

@MainActor
@Observable
final class LoginItemController {
    private(set) var status: LoginItemStatus
    private(set) var errorText: String?
    @ObservationIgnored private let service: any LoginItemService

    init(service: any LoginItemService) {
        self.service = service
        self.status = service.status
    }

    /// The toggle reads "on" when enabled or waiting for the user's approval.
    var isOn: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = service.status
    }

    func setEnabled(_ enabled: Bool) {
        errorText = nil
        do {
            if enabled { try service.register() } else { try service.unregister() }
        } catch {
            errorText = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}

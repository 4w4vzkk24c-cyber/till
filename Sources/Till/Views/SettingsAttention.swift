import Foundation

/// Whether the gear should carry an attention dot. A denied notification permission only
/// counts while the user has Notifications switched on; turning it off is a choice, not
/// a problem to nag about.
enum SettingsAttention {
    static func needsBadge(
        authorization: NotificationAuthorization?,
        notificationsEnabled: Bool,
        loginNeedsApproval: Bool,
        loginError: String?
    ) -> Bool {
        (authorization == .denied && notificationsEnabled) || loginNeedsApproval || loginError != nil
    }
}

import Foundation
import Testing
@testable import Till

@Suite struct SettingsAttentionTests {
    private func badge(
        _ auth: NotificationAuthorization?, enabled: Bool = true, approval: Bool = false, error: String? = nil
    ) -> Bool {
        SettingsAttention.needsBadge(
            authorization: auth, notificationsEnabled: enabled,
            loginNeedsApproval: approval, loginError: error)
    }

    @Test func deniedWhileOnBadges() { #expect(badge(.denied)) }

    @Test func deniedWhileTheUserTurnedItOffDoesNotBadge() {   // Review Focus 4
        #expect(!badge(.denied, enabled: false))
    }

    @Test func authorizedOrUnknownDoesNotBadge() {
        #expect(!badge(.authorized))
        #expect(!badge(nil))
        #expect(!badge(.notDetermined))
    }

    @Test func loginApprovalBadges() { #expect(badge(.authorized, approval: true)) }

    @Test func loginErrorBadges() { #expect(badge(.authorized, error: "boom")) }
}

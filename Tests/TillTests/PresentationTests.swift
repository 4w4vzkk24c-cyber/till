import Foundation
import Testing
@testable import Till

@Suite struct BarIconPresentationTests {
    @Test func normalIsTemplateWithoutCount() {
        let p = BarIconPresentation(.normal)
        #expect(p.tint == .template && p.countText == nil && p.symbolName == "timer")
    }

    @Test func amberHasNoCount() {
        let p = BarIconPresentation(.amber)
        #expect(p.tint == .amber && p.countText == nil)
    }

    @Test func redShowsOverdueCount() {
        let p = BarIconPresentation(.red(overdueCount: 3))
        #expect(p.tint == .red && p.countText == "3")
        #expect(p.accessibilityText == "Till, 3 overdue")
    }

    @Test func dimmedWhenNothingActive() {
        let p = BarIconPresentation(.dimmed)
        #expect(p.tint == .dimmed && p.countText == nil)
    }

    @Test func oneGlyphForEveryState() {
        let states: [BarIconState] = [.normal, .amber, .red(overdueCount: 1), .dimmed]
        #expect(Set(states.map { BarIconPresentation($0).symbolName }).count == 1)
    }
}

@Suite struct SpokenTests {
    @Test func durations() {
        #expect(Spoken.duration(seconds: 0) == "0 seconds")
        #expect(Spoken.duration(seconds: 1) == "1 second")
        #expect(Spoken.duration(seconds: 61) == "1 minute 1 second")
        #expect(Spoken.duration(seconds: 120) == "2 minutes")
        #expect(Spoken.duration(seconds: 3_600) == "1 hour")
        #expect(Spoken.duration(seconds: 3 * 3_600 + 12 * 60) == "3 hours 12 minutes")
        #expect(Spoken.duration(seconds: 86_400) == "1 day")
        #expect(Spoken.duration(seconds: 90_000) == "1 day 1 hour")
    }

    @Test func labelsCarryState() {
        #expect(Spoken.label(title: "Dentist", state: .approaching, remaining: 3 * 3_600 + 12 * 60)
                == "Dentist, 3 hours 12 minutes remaining, approaching")
        #expect(Spoken.label(title: nil, state: .clean, remaining: 7_200) == "Timer, 2 hours remaining")
        #expect(Spoken.label(title: "  ", state: .paused, remaining: 600)
                == "Timer, paused, 10 minutes remaining")
        #expect(Spoken.label(title: "Tea", state: .overdue, remaining: -(2 * 3_600 + 5))
                == "Tea, 2 hours overdue")
        #expect(Spoken.label(title: "Tea", state: .overdue, remaining: -10)
                == "Tea, less than a minute overdue")
    }
}

@Suite struct IconAndColorTests {
    @Test func hexParsing() throws {
        let c = try #require(HexColor.rgb("#F5A623"))
        #expect(abs(c.r - 245.0 / 255) < 0.0001)
        #expect(abs(c.g - 166.0 / 255) < 0.0001)
        #expect(abs(c.b - 35.0 / 255) < 0.0001)
        #expect(HexColor.rgb("F5A623") != nil)
        #expect(HexColor.rgb("#FFF") == nil)
        #expect(HexColor.rgb("#GGGGGG") == nil)
        #expect(HexColor.rgb("") == nil)
    }

    @Test func fallbackSymbolNames() {
        #expect(FallbackIcons.symbolName(for: "sf:timer") == "timer")
        #expect(FallbackIcons.symbolName(for: "mdi:timer") == nil)
        #expect(FallbackIcons.all.contains(FallbackIcons.defaultID))
    }
}

@MainActor
@Suite struct LoginItemControllerTests {
    final class MockLoginItem: LoginItemService {
        var status: LoginItemStatus = .notRegistered
        var registerError: Error?
        var registerResult: LoginItemStatus = .enabled
        private(set) var openedSettings = 0

        func register() throws {
            if let registerError { throw registerError }
            status = registerResult
        }
        func unregister() throws { status = .notRegistered }
        func openSystemSettings() { openedSettings += 1 }
    }

    struct Boom: Error, LocalizedError { var errorDescription: String? { "boom" } }

    @Test func enableAndDisable() {
        let mock = MockLoginItem()
        let c = LoginItemController(service: mock)
        #expect(!c.isOn)
        c.setEnabled(true)
        #expect(c.isOn && c.status == .enabled && c.errorText == nil)
        c.setEnabled(false)
        #expect(!c.isOn && c.status == .notRegistered)
    }

    @Test func requiresApprovalReadsAsOnAndNeedsApproval() {
        let mock = MockLoginItem()
        mock.registerResult = .requiresApproval
        let c = LoginItemController(service: mock)
        c.setEnabled(true)
        #expect(c.isOn && c.needsApproval)
        c.openSystemSettings()
        #expect(mock.openedSettings == 1)
    }

    @Test func registrationFailureIsSurfacedAndStatusReread() {
        let mock = MockLoginItem()
        mock.registerError = Boom()
        let c = LoginItemController(service: mock)
        c.setEnabled(true)
        #expect(c.errorText == "boom")
        #expect(!c.isOn)
    }

    @Test func refreshPicksUpExternalChanges() {
        let mock = MockLoginItem()
        let c = LoginItemController(service: mock)
        mock.status = .enabled                       // user flipped it in System Settings
        c.refresh()
        #expect(c.isOn)
    }
}

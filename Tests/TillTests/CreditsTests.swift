import AppKit
import Foundation
import Testing
@testable import Till

@Suite struct CreditsTests {
    @Test func everyBundledIconCollectionHasACredit() {
        // A new bundled icon cannot ship without its author and license in the About panel.
        let credited = Set(Credits.entries.map(\.collection))
        for icon in BundledIconCatalog.icons {
            #expect(credited.contains(icon.collection), "\(icon.id) has no credit for \(icon.collection)")
        }
    }

    @Test func creditedLicensesMatchTheCatalog() {
        for icon in BundledIconCatalog.icons {
            let entry = Credits.entries.first { $0.collection == icon.collection }
            #expect(entry?.license == icon.license, "\(icon.id)")
        }
    }

    @Test func theAppIconIsCreditedToItsAuthor() {
        let text = Credits.text()
        #expect(text.contains("Seedling icons created by Umeicon - Flaticon"))
        #expect(text.contains("https://www.flaticon.com/free-icons/seedling"))
    }

    @Test func theTextNamesEveryAuthorAndLicense() {
        let text = Credits.text()
        for author in ["Hugeicons", "Evergrow", "Valentin Fossati", "Emoji One", "Dave Gandy", "Gil Barbara"] {
            #expect(text.contains(author), "\(author)")
        }
        for license in ["MIT", "CC BY 4.0", "CC0"] { #expect(text.contains(license), "\(license)") }
    }

    @Test func attributionLicensesLinkToTheirTerms() {
        #expect(Credits.text().contains("https://creativecommons.org/licenses/by/4.0/"))
    }

    @Test func eachCreditListsItsIconNames() {
        let text = Credits.text()
        for id in ["hugeicons:bio-energy", "emojione-monotone:tomato", "builtin:seedling", "logos:ollama"] {
            #expect(text.contains(FallbackIcons.displayName(for: id)), "\(id)")
        }
    }

    @Test func theCompanyMarksCarryATrademarkDisclaimer() {
        let text = Credits.text()
        #expect(text.contains("trademarks of their owners"))
        #expect(text.contains("not affiliated with or endorsed by"))
        for name in ["Claude", "OpenAI", "Z.ai", "opencode", "Ollama"] { #expect(text.contains(name), "\(name)") }
    }

    @Test func iconsPickedFromIconifyKeepTheirOwnLicenses() {
        #expect(Credits.text().contains("Icons you pick from Iconify keep their own licenses"))
    }
}

@Suite struct AboutPanelTests {
    @Test func onlyVisibleTitledWindowsAreRaised() {
        #expect(AboutPanel.shouldRaise(styleMask: [.titled, .closable], isVisible: true))
        #expect(!AboutPanel.shouldRaise(styleMask: [.titled, .closable], isVisible: false))
    }

    @Test func thePopoverWindowIsLeftAlone() {
        // The MenuBarExtra window is not a titled window.
        #expect(!AboutPanel.shouldRaise(styleMask: [.borderless], isVisible: true))
        #expect(!AboutPanel.shouldRaise(styleMask: [.nonactivatingPanel], isVisible: true))
    }

    @Test func thePanelSitsOneLayerAboveTheWindowItWasOpenedFrom() {
        #expect(AboutPanel.raisedLevel(above: .statusBar).rawValue == NSWindow.Level.statusBar.rawValue + 1)
        #expect(AboutPanel.raisedLevel(above: .normal).rawValue == NSWindow.Level.normal.rawValue + 1)
    }
}


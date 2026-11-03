import Foundation
import Testing
@testable import Till

@Suite struct BundledIconCatalogTests {
    private var nonSF: [String] { FallbackIcons.all.filter { !$0.hasPrefix("sf:") } }

    @Test func everyDefaultIsInTheCatalogWithAValidIconifyID() {
        for id in nonSF {
            #expect(BundledIconCatalog.icon(for: id) != nil, "\(id) missing from the catalog")
            #expect(IconID.parse(id) != nil, "\(id) is not a valid Iconify id")
        }
    }

    @Test func everySVGIsSelfContainedAndSmall() {
        for icon in BundledIconCatalog.icons {
            #expect(icon.svg.contains("<svg"), "\(icon.id)")
            #expect(!icon.svg.contains("currentColor"), "\(icon.id) still uses currentColor")
            #expect(icon.svg.utf8.count < 20_000, "\(icon.id) is unexpectedly large")
        }
    }

    @Test func tintableIconsAreWhiteAndColouredOnesKeepTheirColours() {
        for icon in BundledIconCatalog.icons where icon.monotone {
            #expect(icon.svg.contains("#ffffff"), "\(icon.id) is flagged monotone but is not white-filled")
        }
        #expect(BundledIconCatalog.icon(for: "logos:claude-icon")?.monotone == false)
        #expect(BundledIconCatalog.icon(for: "logos:z-ai")?.monotone == false)
        #expect(BundledIconCatalog.icon(for: "logos:opencode-icon")?.monotone == false)
        #expect(BundledIconCatalog.icon(for: "hugeicons:bio-energy")?.monotone == true)
        #expect(BundledIconCatalog.icon(for: "logos:openai-icon")?.monotone == true)
        #expect(BundledIconCatalog.icon(for: "logos:ollama")?.monotone == true)
    }

    @Test func everyEntryNamesItsCollectionAndLicense() {
        for icon in BundledIconCatalog.icons {
            #expect(!icon.collection.isEmpty && !icon.license.isEmpty, "\(icon.id)")
        }
    }

    @Test func idsAreUnique() {
        let ids = BundledIconCatalog.icons.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}

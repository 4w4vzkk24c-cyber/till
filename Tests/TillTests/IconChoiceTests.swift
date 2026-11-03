import Foundation
import Testing
@testable import Till

/// The monotone flag has two sources: the picker's guess from the collection's palette hint,
/// and the fetched asset's detected truth. These tests pin which one wins, in one place.
@Suite struct IconChoiceTests {
    private func result(palette: Bool?) -> IconSearchResult {
        IconSearchResult(
            id: "mdi:coffee", collectionName: "Material Design Icons", licenseTitle: "Apache 2.0",
            paletteHint: palette)
    }

    private func asset(monotone: Bool) -> IconAsset {
        IconAsset(id: "mdi:coffee", monotone: monotone, fileURL: URL(fileURLWithPath: "/tmp/coffee.png"))
    }

    // MARK: the hint

    @Test func aPaletteCollectionIsHintedMulticolor() {
        #expect(IconChoice.hinted(by: result(palette: true)).monotone == false)
    }

    @Test func aNonPaletteOrUnknownCollectionIsHintedMonotone() {
        #expect(IconChoice.hinted(by: result(palette: false)).monotone == true)
        #expect(IconChoice.hinted(by: result(palette: nil)).monotone == true)
    }

    @Test func theHintKeepsTheIdAndTheSetsNameAndLicense() {
        let choice = IconChoice.hinted(by: result(palette: false))
        #expect(choice.id == "mdi:coffee")
        #expect(choice.collectionName == "Material Design Icons")
        #expect(choice.licenseTitle == "Apache 2.0")
    }

    // MARK: the truth

    @Test func theFetchedAssetOverridesAMonotoneHint() {
        let hinted = IconChoice.hinted(by: result(palette: false))          // hint: monotone
        #expect(hinted.resolved(with: asset(monotone: false)).monotone == false)
    }

    @Test func theFetchedAssetOverridesAMulticolorHint() {
        let hinted = IconChoice.hinted(by: result(palette: true))           // hint: multicolor
        #expect(hinted.resolved(with: asset(monotone: true)).monotone == true)
    }

    @Test func resolvingKeepsTheCollectionAndLicenseAndTakesTheAssetsId() {
        let resolved = IconChoice.hinted(by: result(palette: false)).resolved(with: asset(monotone: true))
        #expect(resolved.id == "mdi:coffee")
        #expect(resolved.collectionName == "Material Design Icons")
        #expect(resolved.licenseTitle == "Apache 2.0")
    }
}

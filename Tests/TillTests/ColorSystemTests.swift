import Foundation
import Testing
@testable import Till

@Suite struct ColorSystemTests {
    static let legacy = ["#F5A623", "#4FC3F7", "#81C784", "#BA68C8", "#FF8A65", "#FFD54F"]

    @Test func contrastMatchesWCAGReferences() {
        #expect(abs(Contrast.ratio("#FFFFFF", "#000000") - 21) < 0.01)
        #expect(abs(Contrast.ratio("#FFFFFF", "#FFFFFF") - 1) < 0.0001)
    }

    @Test func overdueFillCarriesWhiteText() {
        #expect(Contrast.ratio("#FFFFFF", "#CF2F36") >= 4.5)
    }

    @Test func newAccentsAvoidTheStateHues() throws {
        for hex in CreationFlow.accents {
            let hue = try #require(HexColor.hue(of: hex))
            #expect(hue > 60 && hue < 340)
        }
    }

    @Test func newAccentsReadOnTheDarkTile() {
        for hex in CreationFlow.accents { #expect(Contrast.ratio(hex, "#445D8E") >= 3.0) }
    }

    @Test func legacyAccentsStayLegibleInBothAppearances() {       // Review Focus 1
        for hex in Self.legacy + CreationFlow.accents {
            #expect(Contrast.ratio(HexColor.adjusted(hex, forLight: true, minContrast: 3.0), "#ECEFF6") >= 3.0)
            #expect(Contrast.ratio(HexColor.adjusted(hex, forLight: false, minContrast: 3.0), "#445D8E") >= 3.0)
        }
    }

    @Test func adjustmentKeepsHue() throws {
        for hex in Self.legacy {
            let adjusted = HexColor.adjusted(hex, forLight: true, minContrast: 3.0)
            let before = try #require(HexColor.hue(of: hex))
            let after = try #require(HexColor.hue(of: adjusted))
            #expect(abs(after - before) < 2)
        }
    }

    @Test func adjustmentLeavesLegibleColoursAlone() {
        #expect(HexColor.adjusted("#1C9383", forLight: true, minContrast: 3.0) == "#1C9383")
    }

    @Test func amberCaptionIsLegibleOnTheLightTile() {
        #expect(Contrast.ratio(HexColor.adjusted("#FFC15E", forLight: true, minContrast: 4.5), "#ECEFF6") >= 4.5)
    }
}

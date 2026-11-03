import Foundation

/// The menu-bar glyph (operator decision, 2026-11-03): Font Awesome 5 Solid "seedling",
/// Iconify id `fa-solid:seedling`, CC BY 4.0, by Dave Gandy (see THIRD_PARTY_NOTICES.md).
/// Bundled as source, not fetched, so the app still makes no network call after chip
/// creation. White fill: the menu bar draws it as a template image or tints it.
enum BarGlyph {
    static let name = "seedling"

    static let seedlingSVG = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="256" height="256"><path fill="#ffffff" d="M64 96H0c0 123.7 100.3 224 224 224v144c0 8.8 7.2 16 16 16h32c8.8 0 16-7.2 16-16V320C288 196.3 187.7 96 64 96m384-64c-84.2 0-157.4 46.5-195.7 115.2c27.7 30.2 48.2 66.9 59 107.6C424 243.1 512 147.9 512 32z"/></svg>"##
}

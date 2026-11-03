import Foundation

/// Author and license credits for the artwork bundled in the app (shown in the About
/// panel). CC BY 4.0 requires credit to the author; MIT requires the copyright and
/// permission notice to accompany copies. The exact upstream MIT wording is still to be
/// added (see THIRD_PARTY_NOTICES.md): until then each MIT set is credited by author with
/// a link where the upstream project gives one.
struct CreditEntry: Equatable {
    let collection: String       // matches `BundledIcon.collection`
    let author: String
    let license: String          // matches `BundledIcon.license`
    let url: String
}

enum Credits {
    /// The app icon's artwork (the seedling), credited as its source asks.
    static let appIconCredit = "Seedling icons created by Umeicon - Flaticon"
    static let appIconURL = "https://www.flaticon.com/free-icons/seedling"

    static let entries: [CreditEntry] = [
        CreditEntry(
            collection: "Huge Icons", author: "Hugeicons", license: "MIT",
            url: "https://icon-sets.iconify.design/icon-sets/hugeicons/"),
        CreditEntry(
            collection: "with icons", author: "Evergrow", license: "MIT",
            url: "https://github.com/withevergrow/withicons/blob/main/LICENSE"),
        CreditEntry(
            collection: "@icons", author: "Valentin Fossati", license: "MIT",
            url: "https://github.com/Voxybuns/at-icons/blob/main/LICENSE"),
        CreditEntry(
            collection: "Emoji One (Monotone)", author: "Emoji One", license: "CC BY 4.0",
            url: "https://creativecommons.org/licenses/by/4.0/"),
        CreditEntry(
            collection: "Font Awesome 5 Solid", author: "Dave Gandy, Font Awesome", license: "CC BY 4.0",
            url: "https://creativecommons.org/licenses/by/4.0/"),
        CreditEntry(
            collection: "SVG Logos", author: "Gil Barbara", license: "CC0",
            url: "https://github.com/gilbarbara/logos"),
    ]

    /// Plain text for the About panel.
    static func text() -> String {
        var lines = ["App icon", appIconCredit, appIconURL, "", "Icons bundled with Till", ""]
        for entry in entries {
            let names = BundledIconCatalog.icons
                .filter { $0.collection == entry.collection }
                .map { FallbackIcons.displayName(for: $0.id) }
                .joined(separator: ", ")
            lines.append("\(entry.collection) by \(entry.author), \(entry.license): \(names)")
            lines.append(entry.url)
            lines.append("")
        }
        lines.append(
            "Claude, OpenAI, Z.ai, opencode and Ollama are trademarks of their owners. Till is "
            + "not affiliated with or endorsed by them. The artwork is from SVG Logos (CC0), which "
            + "does not grant any trademark rights.")
        lines.append("")
        lines.append("Icons you pick from Iconify keep their own licenses, shown when you pick them.")
        return lines.joined(separator: "\n")
    }
}

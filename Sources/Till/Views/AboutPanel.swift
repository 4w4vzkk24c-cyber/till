import AppKit

/// The standard About panel with the icon credits (spec A2). Opened only from the gear
/// menu. The app has no ordinary windows, so it is brought to the front once, on the
/// user's action.
@MainActor
enum AboutPanel {
    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: Credits.text(),
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.labelColor,
            ])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}

import AppKit

/// The standard About panel with the icon credits (spec A2). Opened only from the gear
/// menu. Till is an agent-style app with no ordinary windows, so a plain activation can
/// lose to the app the user was in and the panel opened behind it (operator report,
/// 2026-11-03). The panel is therefore raised explicitly, which works even when Till is
/// not the active app.
@MainActor
enum AboutPanel {
    static func show() {
        NSApp.activate()
        let credits = NSAttributedString(
            string: Credits.text(),
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.labelColor,
            ])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        for window in NSApp.windows where shouldRaise(styleMask: window.styleMask, isVisible: window.isVisible) {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    /// The About panel is a visible, titled window; the MenuBarExtra popover is not titled.
    nonisolated static func shouldRaise(styleMask: NSWindow.StyleMask, isVisible: Bool) -> Bool {
        isVisible && styleMask.contains(.titled)
    }
}

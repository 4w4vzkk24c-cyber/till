import AppKit

/// The standard About panel with the icon credits (spec A2). Opened only from the gear
/// menu. Till is an agent-style app with no ordinary windows, so:
/// - a plain activation can lose to the app the user was in and the panel opened behind
///   it, so the panel is raised explicitly, even when Till is not the active app;
/// - the open popover sits on a higher layer than an ordinary window and covered the
///   panel, so the panel is placed one layer above the window it was opened from.
/// (Both are operator reports, 2026-11-03.) The popover is not closed from code: dismissing
/// a MenuBarExtra window that way can leave its menu-bar item out of step.
@MainActor
enum AboutPanel {
    static func show() {
        let openedFrom = NSApp.keyWindow?.level ?? .normal     // the popover is the key window
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: options())
        for window in NSApp.windows where shouldRaise(styleMask: window.styleMask, isVisible: window.isVisible) {
            window.level = raisedLevel(above: openedFrom)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    /// The credits text, and the app icon passed explicitly: the panel otherwise asks the
    /// system for the running app's icon, which for a debug build can still be the generic
    /// placeholder although Finder shows the real one (operator report, 2026-11-03).
    static func options() -> [NSApplication.AboutPanelOptionKey: Any] {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .credits: NSAttributedString(
                string: Credits.text(),
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.labelColor,
                ]),
        ]
        if let icon = NSImage(named: "AppIcon") {
            options[.applicationIcon] = icon
        }
        return options
    }

    /// The About panel is a visible, titled window; the MenuBarExtra popover is not titled.
    nonisolated static func shouldRaise(styleMask: NSWindow.StyleMask, isVisible: Bool) -> Bool {
        isVisible && styleMask.contains(.titled)
    }

    nonisolated static func raisedLevel(above level: NSWindow.Level) -> NSWindow.Level {
        NSWindow.Level(rawValue: level.rawValue + 1)
    }
}

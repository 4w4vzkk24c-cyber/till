import SwiftUI

// PLACEHOLDER scene so the target has an entry point. Real UI (chips grid, add
// field, footer with settings + Quit) comes with TimerStore/views; see design §7.5
// and addendum A1.1.
@main
struct TillApp: App {
    var body: some Scene {
        MenuBarExtra("Till", systemImage: "timer") {
            Text("Till")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}

import SwiftUI

@main
struct TillApp: App {
    @State private var model: AppModel

    init() {
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        MenuBarExtra {
            ChipsPopover(
                store: model.store, creation: model.creation,
                loginItems: model.loginItems, loadError: model.loadError)
        } label: {
            BarIconLabel(store: model.store)
        }
        .menuBarExtraStyle(.window)
    }
}

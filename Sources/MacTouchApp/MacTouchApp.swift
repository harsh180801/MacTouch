import AppKit
import SwiftUI

@main
struct MacTouchApp: App {
    @State private var model = AppViewModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("MacTouch", systemImage: "hand.tap.fill") {
            ContentView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

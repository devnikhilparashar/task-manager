import SwiftUI

@main
struct AmbiantMemoryApp: App {
    @StateObject private var model = AppModel.make()

    var body: some Scene {
        MenuBarExtra("AmbiantMemory", systemImage: "clock.badge.checkmark") {
            MenuContentView(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Today", id: "timeline") {
            TimelineView(model: model)
        }
        .defaultSize(width: 820, height: 600)

        Settings {
            JournalSettingsView(model: model)
        }
    }
}

import SwiftUI
import WL5024ControlFeature

@main
struct WL5024ControlApp: App {
    @State private var model = HeadsetModel(
        demoMode: ProcessInfo.processInfo.arguments.contains("--demo")
    )

    var body: some Scene {
        Window("WL5024 Control", id: "settings") {
            HeadsetSettingsView(model: model)
                .task {
                    await model.start()
                }
        }
        .defaultSize(width: 880, height: 620)

        MenuBarExtra {
            HeadsetMenuBarView(model: model)
                .task {
                    await model.start()
                }
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)
    }
}

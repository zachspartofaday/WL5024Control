import SwiftUI

public struct HeadsetMenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable private var model: HeadsetModel

    public init(model: HeadsetModel) {
        self.model = model
    }

    public var body: some View {
        Text(model.snapshot.device.model)
        if let battery = model.snapshot.device.batteryPercent {
            Text("Battery: \(battery)%")
        }
        Divider()
        if case .boolean(let enabled) = model.value(for: .automaticMedia) {
            Toggle("Automatic media control", isOn: Binding(
                get: { enabled },
                set: { model.set(.automaticMedia, to: .boolean($0)) }
            ))
            .disabled(!model.readiness(for: .automaticMedia).allowsWrite)
        } else {
            Text("Automatic media control: not read")
        }
        Divider()
        Button("Open Settings…") {
            openWindow(id: "settings")
            NSApp.activate()
        }
        Button("Refresh") { model.refresh() }
            .disabled(!isConnected || model.isCommandInFlight)
        Divider()
        Button("Quit WL5024 Control") { NSApp.terminate(nil) }
    }

    private var isConnected: Bool {
        if case .connected = model.snapshot.connection { true } else { false }
    }
}

public struct MenuBarLabel: View {
    private let model: HeadsetModel

    public init(model: HeadsetModel) {
        self.model = model
    }

    public var body: some View {
        Image(systemName: isConnected ? "headphones" : "headphones.circle")
            .accessibilityLabel(isConnected ? "WL5024 connected" : "WL5024 disconnected")
    }

    private var isConnected: Bool {
        if case .connected = model.snapshot.connection { true } else { false }
    }
}

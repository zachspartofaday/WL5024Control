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
            if model.readiness(for: .automaticMedia).allowsWrite {
                Toggle("Automatic media control", isOn: Binding(
                    get: { enabled },
                    set: { model.set(.automaticMedia, to: .boolean($0)) }
                ))
            } else {
                Text("Automatic media control: \(enabled ? "On" : "Off")")
                Text(readOnlyExplanation)
            }
        } else {
            Text("Automatic media control: not read")
            if model.readiness(for: .automaticMedia) == .experimental {
                Menu("Set Automatic Media…") {
                    Button("Turn On") { model.set(.automaticMedia, to: .boolean(true)) }
                    Button("Turn Off") { model.set(.automaticMedia, to: .boolean(false)) }
                }
                Text("Experimental — response verification required")
            }
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

    private var readOnlyExplanation: String {
        switch model.readiness(for: .automaticMedia) {
        case .readOnly, .validationPending:
            "Read-only — validation pending"
        case .experimental:
            "Experimental — response verification required"
        case .unavailable:
            switch model.snapshot.connection {
            case .idle: "Read-only — headset not connected"
            case .searching: "Read-only — looking for headset"
            case .bluetoothPermissionDenied: "Read-only — Bluetooth access is off"
            case .unavailable: "Read-only — Bluetooth unavailable"
            case .failed: "Read-only — connection failed"
            case .qualificationRequired: "Read-only — receiver validation pending"
            case .connected: "Read-only — validation pending"
            }
        case .ready:
            "Ready"
        }
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

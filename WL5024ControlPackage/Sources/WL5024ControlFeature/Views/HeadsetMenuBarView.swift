import SwiftUI

public struct HeadsetMenuBarView: View {
    @Bindable private var model: HeadsetModel
    private let openSettings: () -> Void
    private let openDiagnostics: () -> Void

    public init(
        model: HeadsetModel,
        openSettings: @escaping () -> Void,
        openDiagnostics: @escaping () -> Void
    ) {
        self.model = model
        self.openSettings = openSettings
        self.openDiagnostics = openDiagnostics
    }

    public var body: some View {
        Text(model.snapshot.device.model)
        if let battery = model.snapshot.device.batteryPercent {
            Text("Battery: \(battery)%")
        }
        Text(connectionText)
        Divider()
        Button("Open Settings…", action: openSettings)
        Button("Diagnostics…", action: openDiagnostics)
        Button("Refresh") { model.refresh() }
            .disabled(!isConnected || model.isCommandInFlight || model.discoveryState == .running)
        Divider()
        Button("Quit WL5024 Control") { NSApp.terminate(nil) }
    }

    private var isConnected: Bool {
        if case .connected = model.snapshot.connection { true } else { false }
    }

    private var connectionText: String {
        switch model.snapshot.connection {
        case .connected(.bluetooth): "Connected over Bluetooth"
        case .connected(.receiver): "Connected through USB receiver"
        case .searching: "Looking for headset…"
        case .qualificationRequired: "Receiver validation pending"
        case .bluetoothPermissionDenied: "Bluetooth access is off"
        case .unavailable: "Bluetooth unavailable"
        case .failed: "Connection failed"
        case .idle: "Not connected"
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

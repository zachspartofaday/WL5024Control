import AppKit
import SwiftUI

public struct HeadsetSettingsView: View {
    @Bindable private var model: HeadsetModel

    public init(model: HeadsetModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $model.selectedPage) { page in
                Label {
                    Text(page.title)
                } icon: {
                    Image(systemName: page.symbolName)
                }
                .tag(page)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            Group {
                switch model.selectedPage ?? .overview {
                case .overview:
                    OverviewView(model: model)
                case .diagnostics:
                    DiagnosticsView(model: model)
                case let page:
                    SettingsPageView(page: page, model: model)
                }
            }
            .navigationTitle(Text((model.selectedPage ?? .overview).title))
        }
        .frame(minWidth: 720, minHeight: 500)
        .alert(
            model.failure?.title ?? LocalizedStringResource("Unable to update the headset", bundle: #bundle),
            isPresented: Binding(
                get: { model.failure != nil },
                set: { if !$0 { model.dismissFailure() } }
            )
        ) {
            recoveryButtons
        } message: {
            Text(model.failure?.message ?? "Reconnect the headset and try again.")
        }
    }

    @ViewBuilder
    private var recoveryButtons: some View {
        if let failure = model.failure {
            switch failure.primaryAction {
            case .retry:
                Button("Try Again", action: model.retryLastAction)
                Button("Cancel", role: .cancel, action: model.dismissFailure)
            case .reconnect:
                Button("Reconnect", action: model.reconnect)
                Button("Cancel", role: .cancel, action: model.dismissFailure)
            case .openBluetoothSettings:
                Button("Open Bluetooth Settings", action: openBluetoothSettings)
                Button("Cancel", role: .cancel, action: model.dismissFailure)
            case .chooseAnotherLocation, .dismiss:
                Button("Dismiss", role: .cancel, action: model.dismissFailure)
            }
        }
    }

    private func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Bluetooth-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
        model.dismissFailure()
    }
}

private struct OverviewView: View {
    @Bindable var model: HeadsetModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                connectionCard

                GroupBox {
                    SettingRow(key: .automaticMedia, model: model)
                } label: {
                    Label("Wear-sensor media control", systemImage: "playpause")
                }

                if case .qualificationRequired = model.snapshot.connection {
                    ContentUnavailableView {
                        Label("Receiver detected", systemImage: "cable.connector")
                    } description: {
                        Text("The app found the USB receiver. Its HID report identifiers will be captured and validated when the headset is available.")
                    }
                }

                if model.snapshot.connection == .bluetoothPermissionDenied {
                    ContentUnavailableView {
                        Label("Bluetooth access is off", systemImage: "bluetooth.slash")
                    } description: {
                        Text("Allow WL5024 Control to use Bluetooth, then return here and reconnect.")
                    } actions: {
                        Button("Open Bluetooth Settings", action: openBluetoothSettings)
                    }
                }

                if model.snapshot.connection == .failed {
                    ContentUnavailableView {
                        Label("Unable to connect", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("Turn on the headset, then reconnect. Technical details are available in Diagnostics.")
                    } actions: {
                        Button("Reconnect", action: model.reconnect)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private var connectionCard: some View {
        GroupBox {
            HStack(spacing: 16) {
                Image(systemName: "headphones")
                    .font(.system(size: 34))
                    .foregroundStyle(connectionColor)
                    .frame(width: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.snapshot.device.model)
                        .font(.title2.weight(.semibold))
                    Text(connectionText)
                        .foregroundStyle(.secondary)
                    if let firmware = model.snapshot.device.headsetFirmware {
                        Text("Firmware \(firmware)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let battery = model.snapshot.device.batteryPercent {
                    Label("\(battery)%", systemImage: batterySymbol(battery))
                        .font(.headline)
                }

                Button("Refresh", systemImage: "arrow.clockwise") { model.refresh() }
                    .labelStyle(.iconOnly)
                .help("Refresh headset settings")
                .disabled(!isConnected)
            }
            .padding(8)
        }
    }

    private var isConnected: Bool {
        if case .connected = model.snapshot.connection { true } else { false }
    }

    private var connectionText: String {
        switch model.snapshot.connection {
        case .idle: "Not connected"
        case .searching: "Looking for the headset and receiver…"
        case .connected(.bluetooth): "Connected over Bluetooth"
        case .connected(.receiver): "Connected through the USB receiver"
        case .qualificationRequired: "Receiver found — report validation pending"
        case .bluetoothPermissionDenied: "Bluetooth access is disabled"
        case .unavailable: "Bluetooth is unavailable"
        case .failed: "Connection failed"
        }
    }

    private var connectionColor: Color {
        isConnected ? .green : .secondary
    }

    private func batterySymbol(_ percentage: Int) -> String {
        switch percentage {
        case 76...: "battery.100percent"
        case 51...: "battery.75percent"
        case 26...: "battery.50percent"
        default: "battery.25percent"
        }
    }

    private func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Bluetooth-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private struct SettingsPageView: View {
    let page: SettingsPage
    @Bindable var model: HeadsetModel

    private var settings: [HeadsetSettingKey] {
        HeadsetSettingKey.allCases.filter { $0.page == page }
    }

    var body: some View {
        Form {
            Section {
                ForEach(settings) { key in
                    SettingRow(key: key, model: model)
                }
            } footer: {
                Text("Only settings marked Ready can be changed. Settings awaiting hardware validation remain safely disabled.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct SettingRow: View {
    let key: HeadsetSettingKey
    @Bindable var model: HeadsetModel

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 4) {
                if let value = model.value(for: key) {
                    control(value: value)
                        .frame(maxWidth: 280)
                        .disabled(!model.readiness(for: key).allowsWrite || model.pendingSettings.contains(key))
                } else {
                    Text("Not read from headset")
                        .foregroundStyle(.secondary)
                }
                if model.readiness(for: key) != .ready {
                    Text(model.readiness(for: key).status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(key.title)
                Text(key.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func control(value: SettingValue) -> some View {
        switch key.controlKind {
        case .toggle:
            Toggle(key.title, isOn: Binding(
                get: {
                    if case .boolean(let enabled) = value { enabled } else { false }
                },
                set: { model.set(key, to: .boolean($0)) }
            ))
            .labelsHidden()
        case .choices:
            Picker(key.title, selection: Binding(
                get: {
                    if case .choice(let selection) = value { selection } else { "" }
                },
                set: { model.set(key, to: .choice($0)) }
            )) {
                ForEach(key.choices) { choice in
                    Text(choice.title).tag(choice.id)
                }
            }
            .labelsHidden()
        case .level(let range, let step):
            LevelSettingControl(
                key: key,
                currentValue: integer(from: value),
                range: range,
                step: step,
                apply: { model.set(key, to: .integer($0)) }
            )
        case .text:
            TextSettingControl(
                label: key.title,
                value: text(from: value),
                apply: { model.set(key, to: .text($0)) }
            )
            .id(text(from: value))
        case .action:
            Button("Play Headset Sound") { model.perform(key) }
        }
    }

    private func integer(from value: SettingValue) -> Int {
        if case .integer(let number) = value { number } else { 0 }
    }

    private func text(from value: SettingValue) -> String {
        if case .text(let text) = value { text } else { "" }
    }
}

private struct TextSettingControl: View {
    @State private var value: String
    let label: LocalizedStringResource
    let apply: (String) -> Void

    init(label: LocalizedStringResource, value: String, apply: @escaping (String) -> Void) {
        _value = State(initialValue: value)
        self.label = label
        self.apply = apply
    }

    var body: some View {
        HStack {
            TextField(label, text: $value)
                .onSubmit { apply(value) }
            Button("Apply Name") { apply(value) }
        }
    }
}

private struct LevelSettingControl: View {
    let key: HeadsetSettingKey
    let currentValue: Int
    let range: ClosedRange<Int>
    let step: Int
    let apply: (Int) -> Void
    @State private var draftValue: Double

    init(
        key: HeadsetSettingKey,
        currentValue: Int,
        range: ClosedRange<Int>,
        step: Int,
        apply: @escaping (Int) -> Void
    ) {
        self.key = key
        self.currentValue = currentValue
        self.range = range
        self.step = step
        self.apply = apply
        _draftValue = State(initialValue: Double(currentValue))
    }

    var body: some View {
        HStack {
            Slider(
                value: $draftValue,
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            ) { editing in
                if !editing {
                    apply(Int(draftValue.rounded()))
                }
            } label: {
                Text(key.title)
            }
            Text(Int(draftValue.rounded()).formatted())
                .monospacedDigit()
                .frame(minWidth: 28, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .onChange(of: currentValue) {
            draftValue = Double(currentValue)
        }
    }
}

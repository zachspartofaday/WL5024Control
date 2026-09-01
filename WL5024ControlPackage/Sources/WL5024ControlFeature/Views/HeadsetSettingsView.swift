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
            "Headset command failed",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.dismissError() } }
            )
        ) {
            Button("OK") { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
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

                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
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
                Text("Changes are written to the headset and remain in effect when this app is closed.")
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
            control
                .frame(maxWidth: 280)
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
        .disabled(model.pendingSettings.contains(key))
    }

    @ViewBuilder
    private var control: some View {
        switch key.controlKind {
        case .toggle:
            Toggle("", isOn: Binding(
                get: {
                    if case .boolean(let value) = model.value(for: key) { value } else { false }
                },
                set: { model.set(key, to: .boolean($0)) }
            ))
            .labelsHidden()
        case .choices:
            Picker("", selection: Binding(
                get: {
                    if case .choice(let value) = model.value(for: key) { value } else { "" }
                },
                set: { model.set(key, to: .choice($0)) }
            )) {
                ForEach(key.choices) { choice in
                    Text(choice.title).tag(choice.id)
                }
            }
            .labelsHidden()
        case .level(let range, let step):
            HStack {
                Slider(
                    value: Binding(
                        get: {
                            if case .integer(let value) = model.value(for: key) { Double(value) } else { 0 }
                        },
                        set: { model.set(key, to: .integer(Int($0.rounded()))) }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: Double(step)
                )
                Text(integerValue.formatted())
                    .monospacedDigit()
                    .frame(minWidth: 28, alignment: .trailing)
            }
        case .text:
            TextSettingControl(
                value: textValue,
                apply: { model.set(key, to: .text($0)) }
            )
            .id(textValue)
        case .action:
            Button("Play sound") { model.perform(key) }
        }
    }

    private var integerValue: Int {
        if case .integer(let value) = model.value(for: key) { value } else { 0 }
    }

    private var textValue: String {
        if case .text(let value) = model.value(for: key) { value } else { "" }
    }
}

private struct TextSettingControl: View {
    @State private var value: String
    let apply: (String) -> Void

    init(value: String, apply: @escaping (String) -> Void) {
        _value = State(initialValue: value)
        self.apply = apply
    }

    var body: some View {
        HStack {
            TextField("Device name", text: $value)
                .onSubmit { apply(value) }
            Button("Apply") { apply(value) }
        }
    }
}

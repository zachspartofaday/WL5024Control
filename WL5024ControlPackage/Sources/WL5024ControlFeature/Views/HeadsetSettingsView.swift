import AppKit
import SwiftUI

public struct HeadsetSettingsView: View {
    @Bindable private var model: HeadsetModel

    public init(model: HeadsetModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            List(CapabilityCatalog.visiblePages, selection: $model.selectedPage) { page in
                Label(page.title, systemImage: page.symbolName)
                    .tag(page)
            }
            .accessibilityLabel("Settings destinations")
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
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
                Button("Reconnect") { model.reconnect() }
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
        DetailPageContainer {
            ConnectionSummary(model: model)

            GroupBox {
                SettingRow(key: .automaticMedia, model: model)
                    .padding(DetailLayoutMetrics.cardInset)
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
                    Button("Reconnect") { model.reconnect() }
                }
            }
        }
    }

    private func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Bluetooth-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private struct ConnectionSummary: View {
    @Bindable var model: HeadsetModel

    var body: some View {
        GroupBox {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    identity
                    Spacer(minLength: 16)
                    statusControls
                }
                VStack(alignment: .leading, spacing: 12) {
                    identity
                    HStack {
                        Spacer()
                        statusControls
                    }
                }
            }
            .padding(DetailLayoutMetrics.cardInset)
        }
    }

    private var identity: some View {
        HStack(spacing: 16) {
            Image(systemName: "headphones")
                .font(.system(size: 34))
                .foregroundStyle(isConnected ? .green : .secondary)
                .frame(width: 48)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.snapshot.device.model)
                    .font(.title2.weight(.semibold))
                Text(connectionText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let firmware = model.snapshot.device.headsetFirmware {
                    Text("Firmware \(firmware)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusControls: some View {
        HStack(spacing: 12) {
            if let battery = model.snapshot.device.batteryPercent {
                Label("\(battery)%", systemImage: batterySymbol(battery))
                    .font(.headline)
            }
            Button("Refresh", systemImage: "arrow.clockwise") { model.refresh() }
                .labelStyle(.iconOnly)
                .help("Refresh headset settings")
                .disabled(!isConnected || model.discoveryState == .running || model.isCommandInFlight)
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
        CapabilityCatalog.interactiveSettings.filter { $0.page == page }
    }

    var body: some View {
        DetailPageContainer {
            SettingsCard {
                VStack(spacing: 0) {
                    ForEach(Array(settings.enumerated()), id: \.element.id) { index, key in
                        SettingRow(key: key, model: model)
                        if index < settings.count - 1 {
                            Divider()
                        }
                    }
                }
            }

            Text("Ready settings are verified. Experimental settings can be changed, but require a response and matching read-back before the app reports success.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, DetailLayoutMetrics.cardInset)
        }
    }
}

private struct SettingRow: View {
    let key: HeadsetSettingKey
    @Bindable var model: HeadsetModel

    private var readiness: CapabilityReadiness { model.readiness(for: key) }
    private var isSensitivityGated: Bool {
        guard key == .quickPauseSensitivity else { return false }
        if case .boolean(let enabled) = model.value(for: .quickPause) {
            return !enabled
        }
        return false
    }
    private var controlWidth: CGFloat {
        key == .deviceName ? DetailLayoutMetrics.wideControlWidth : DetailLayoutMetrics.controlWidth
    }

    var body: some View {
        SettingsRowLayout(controlWidth: controlWidth) {
            VStack(alignment: .leading, spacing: 4) {
                // The native Toggle/Picker carries the semantic name; hide the
                // visual title from AX to leave one control identity (AUD-010).
                Text(key.title)
                    .accessibilityIdentifier("setting.label.\(key.rawValue)")
                    .accessibilityHidden(true)
                Text(key.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                if readiness != .ready {
                    Text(readiness.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                }
                if isSensitivityGated {
                    Text("Turn on Quick Pause to change sensitivity.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityHidden(true)

            Group {
                if let value = model.value(for: key) {
                    if key.controlKind == .readOnlyValue {
                        readOnlyValue(value)
                    } else {
                        control(value: value)
                            .disabled(!readiness.allowsWrite || model.pendingSettings.contains(key) || isSensitivityGated || model.discoveryState == .running)
                    }
                } else if readiness == .experimental {
                    ExperimentalSettingMenu(key: key) { value in
                        model.set(key, to: value)
                    }
                    .disabled(model.pendingSettings.contains(key) || isSensitivityGated || model.discoveryState == .running)
                } else {
                    Text("Not read from headset")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityHint(readiness == .ready ? Text("") : Text(readiness.status))
        }
        .padding(.vertical, DetailLayoutMetrics.rowVerticalInset)
    }

    @ViewBuilder
    private func control(value: SettingValue) -> some View {
        switch key.controlKind {
        case .toggle:
            Toggle(key.title, isOn: Binding(
                get: { if case .boolean(let enabled) = value { enabled } else { false } },
                set: { model.set(key, to: .boolean($0)) }
            ))
            .labelsHidden()
            .frame(width: DetailLayoutMetrics.pickerWidth, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)

        case .choices:
            Picker(key.title, selection: Binding(
                get: { if case .choice(let selection) = value { selection } else { "" } },
                set: { model.set(key, to: .choice($0)) }
            )) {
                ForEach(key.choices) { choice in
                    Text(choice.title).tag(choice.id)
                }
            }
            .labelsHidden()
            .frame(width: DetailLayoutMetrics.pickerWidth, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)

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
                .frame(maxWidth: .infinity, alignment: .trailing)

        case .readOnlyValue:
            readOnlyValue(value)
        }
    }

    @ViewBuilder
    private func readOnlyValue(_ value: SettingValue) -> some View {
        let prefix = switch key {
        case .micFlipAction: "Action"
        case .ucProfile: "Profile"
        case .ucAppStatus: "Status"
        case .leAudioFeatureMode: "Mode"
        default: "Value"
        }
        Group {
            switch value {
            case .integer(let number): Text("\(prefix) \(number)")
            case .boolean(let enabled): Text(enabled ? "On" : "Off")
            case .choice(let choice), .text(let choice): Text(choice)
            }
        }
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .trailing)
        // One semantic identity for read-only rows: title + value combined.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(key.title))
        .accessibilityValue(valueAccessibilityText(value, prefix: prefix))
    }

    private func valueAccessibilityText(_ value: SettingValue, prefix: String) -> Text {
        switch value {
        case .integer(let number): Text("\(prefix) \(number)")
        case .boolean(let enabled): Text(enabled ? "On" : "Off")
        case .choice(let choice), .text(let choice): Text(choice)
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
        HStack(spacing: 12) {
            TextField(label, text: $value)
                .onSubmit { apply(value) }
            Button("Apply Name") { apply(value) }
        }
        .frame(width: DetailLayoutMetrics.wideControlWidth)
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
        HStack(spacing: 12) {
            Slider(
                value: $draftValue,
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            ) { editing in
                if !editing { apply(Int(draftValue.rounded())) }
            } label: {
                Text(key.title)
            }
            .labelsHidden()
            .accessibilityValue(Int(draftValue.rounded()).formatted())

            Text(Int(draftValue.rounded()).formatted())
                .monospacedDigit()
                .frame(width: DetailLayoutMetrics.sliderValueWidth, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .frame(width: DetailLayoutMetrics.controlWidth)
        .onChange(of: currentValue) {
            draftValue = Double(currentValue)
        }
    }
}

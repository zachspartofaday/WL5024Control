import AppKit
import SwiftUI

private enum SettingsVisualMetrics {
    static let pageInset: CGFloat = 12
    static let blockSpacing: CGFloat = 10
    static let columnSpacing: CGFloat = 12
    static let containerInset: CGFloat = 8
    static let settingsHorizontalInset: CGFloat = 16
    static let rowHeight: CGFloat = 36
    static let sectionHeaderHeight: CGFloat = 28
    static let topPanelHeight: CGFloat = 48
}

public struct HeadsetSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsHeadsetInformation = false
    @State private var showsWritableInfo = false
    @Bindable private var model: HeadsetModel
    @Bindable private var launchAtLogin: LaunchAtLoginModel
    private let openDiagnostics: () -> Void
    private let writableInfo = "Changes are saved on the headset. They persist without the app and are intended to follow the headset to another device. Writes are experimental."

    public init(
        model: HeadsetModel,
        launchAtLogin: LaunchAtLoginModel,
        openDiagnostics: @escaping () -> Void
    ) {
        self.model = model
        self.launchAtLogin = launchAtLogin
        self.openDiagnostics = openDiagnostics
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsVisualMetrics.blockSpacing) {
                GroupBox {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Headset")
                                .font(.headline.weight(.semibold))
                            ConnectionSummary(model: model)
                            connectionRecovery
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .frame(minHeight: SettingsVisualMetrics.topPanelHeight, alignment: .top)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("This Mac")
                                .font(.headline.weight(.semibold))
                        LaunchAtLoginRow(model: launchAtLogin)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .frame(minHeight: SettingsVisualMetrics.topPanelHeight, alignment: .top)
                    }
                    .padding(SettingsVisualMetrics.containerInset)
                }

                ConfigurationSections(model: model)

                GroupBox {
                    DisclosureGroup(isExpanded: $showsHeadsetInformation) {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 0) {
                            GridRow {
                                ReadOnlySettingRow(key: .autoPowerOff, model: model)
                                ReadOnlySettingRow(key: .environmentDetection, model: model)
                            }
                            GridRow {
                                ReadOnlySettingRow(key: .smartSwitch, model: model)
                                ReadOnlySettingRow(key: .micFlipAction, model: model)
                            }
                            GridRow {
                                ReadOnlySettingRow(key: .ucProfile, model: model)
                                ReadOnlySettingRow(key: .ucAppStatus, model: model)
                            }
                            GridRow {
                                ReadOnlySettingRow(key: .leAudioFeatureMode, model: model)
                                Color.clear.frame(minHeight: SettingsVisualMetrics.rowHeight)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        HStack {
                            Label {
                                Text("Headset Information")
                                    .font(.title2.weight(.semibold))
                            } icon: {
                                Image(systemName: "lock")
                            }
                            Spacer()
                            Text("7 read-only values")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("headsetInformation")
                    .padding(.vertical, SettingsVisualMetrics.containerInset)
                    .padding(.horizontal, SettingsVisualMetrics.settingsHorizontalInset)
                }
            }
            .padding(SettingsVisualMetrics.pageInset)
        }
        .frame(minWidth: 640, minHeight: 520)
        .navigationTitle("WL5024 Control")
        .navigationSubtitle(toolbarSubtitle)
        .toolbar {
            if let battery = model.snapshot.device.batteryPercent {
                ToolbarItem(placement: .automatic) {
                    Label("\(battery)%", systemImage: batterySymbol(battery))
                        .monospacedDigit()
                        .padding(.leading, 10)
                        .accessibilityLabel("Battery \(battery) percent")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("About writable controls", systemImage: "info.circle") {
                    showsWritableInfo.toggle()
                }
                .labelStyle(.iconOnly)
                .help("About writable controls")
                .popover(isPresented: $showsWritableInfo, arrowEdge: .top) {
                    Text(writableInfo)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 280, alignment: .leading)
                        .padding(12)
                }
                Button("Refresh", systemImage: "arrow.clockwise") { model.refresh() }
                    .disabled(!isConnected || model.discoveryState == .running || model.isCommandInFlight)
                Button("Diagnostics", systemImage: "stethoscope", action: openDiagnostics)
            }
        }
        .onAppear(perform: launchAtLogin.refresh)
        .onChange(of: scenePhase) {
            if scenePhase == .active { launchAtLogin.refresh() }
        }
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
    private var connectionRecovery: some View {
        switch model.snapshot.connection {
        case .qualificationRequired:
            RecoveryMessage(
                title: "Receiver detected",
                message: "The USB receiver was found, but its reports still require validation.",
                symbol: "cable.connector"
            )
        case .bluetoothPermissionDenied:
            RecoveryMessage(
                title: "Bluetooth access is off",
                message: "In System Settings → Privacy & Security → Bluetooth, allow WL5024 Control to use Bluetooth. Then return here and reconnect.",
                symbol: "bluetooth.slash",
                actionTitle: "Open Bluetooth Privacy Settings",
                action: BluetoothPrivacySettings.open
            )
        case .failed:
            RecoveryMessage(
                title: "Unable to connect",
                message: "Turn on the headset, then reconnect. Technical details are available in Diagnostics.",
                symbol: "exclamationmark.triangle",
                actionTitle: "Reconnect",
                action: { model.reconnect() }
            )
        default:
            EmptyView()
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
                Button("Open Bluetooth Privacy Settings") {
                    BluetoothPrivacySettings.open()
                    model.dismissFailure()
                }
                Button("Cancel", role: .cancel, action: model.dismissFailure)
            case .chooseAnotherLocation, .dismiss:
                Button("Dismiss", role: .cancel, action: model.dismissFailure)
            }
        }
    }

    private var toolbarSubtitle: String {
        "\(model.snapshot.device.model) — \(connectionText)"
    }

    private var connectionText: String {
        switch model.snapshot.connection {
        case .idle: "Not connected"
        case .searching: "Looking for headset…"
        case .connected(.bluetooth): "Connected over Bluetooth"
        case .connected(.receiver): "Connected through USB receiver"
        case .qualificationRequired: "Receiver validation pending"
        case .bluetoothPermissionDenied: "Bluetooth access is off"
        case .unavailable: "Bluetooth unavailable"
        case .failed: "Connection failed"
        }
    }

    private var isConnected: Bool {
        if case .connected = model.snapshot.connection { true } else { false }
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

private struct ConfigurationSections: View {
    @Bindable var model: HeadsetModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: SettingsVisualMetrics.blockSpacing) {
                ViewThatFits(in: .horizontal) {
                    alignedConfigurationGrid
                        .frame(minWidth: 540)

                    VStack(spacing: SettingsVisualMetrics.blockSpacing) {
                        ForEach(SettingsSection.allCases.filter { $0 != .sound }) { section in
                            ConfigurationGroup(section: section, model: model)
                        }
                    }
                }
            }
            .padding(.vertical, SettingsVisualMetrics.containerInset)
            .padding(.horizontal, SettingsVisualMetrics.settingsHorizontalInset)
        }
        .accessibilityIdentifier("headsetSettings")
    }

    private var alignedConfigurationGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 0) {
            GridRow {
                configurationHeader(.noiseControl)
                configurationHeader(.device)
            }
            GridRow {
                ConfigurableSettingRow(key: .microphoneNoiseCancellation, model: model)
                ConfigurableSettingRow(key: .voiceGuidance, model: model)
            }

            sectionGap

            configurationHeader(.callsAndMicrophone)
                .gridCellColumns(2)
            GridRow {
                ConfigurableSettingRow(key: .sidetone, model: model)
                ConfigurableSettingRow(key: .busyLight, model: model)
            }

            sectionGap

            configurationHeader(.wearAndAutomation)
                .gridCellColumns(2)
            GridRow {
                ConfigurableSettingRow(key: .wearDetection, model: model)
                ConfigurableSettingRow(key: .automaticMedia, model: model)
            }
            GridRow {
                ConfigurableSettingRow(key: .muteMicrophoneOnRemoval, model: model)
                ConfigurableSettingRow(key: .answerCallsOnWear, model: model)
            }
            GridRow {
                ConfigurableSettingRow(key: .quickPause, model: model)
                ConfigurableSettingRow(key: .quickPauseSensitivity, model: model)
            }

        }
    }

    private func configurationHeader(_ section: SettingsSection) -> some View {
        Text(section.title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: SettingsVisualMetrics.sectionHeaderHeight, alignment: .leading)
    }

    private var sectionGap: some View {
        Color.clear
            .frame(height: SettingsVisualMetrics.blockSpacing)
            .gridCellColumns(2)
    }
}

private struct ConfigurationGroup: View {
    let section: SettingsSection
    @Bindable var model: HeadsetModel

    private func settings(in section: SettingsSection) -> [HeadsetSettingKey] {
        CapabilityCatalog.configurableSettings.filter { $0.section == section }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(minHeight: SettingsVisualMetrics.sectionHeaderHeight, alignment: .leading)

            let sectionSettings = settings(in: section)
            ForEach(sectionSettings) { key in
                ConfigurableSettingRow(key: key, model: model)
            }
        }
    }
}

private struct ConnectionSummary: View {
    @Bindable var model: HeadsetModel

    var body: some View {
        HStack(spacing: 12) {
            Label {
                Text(model.snapshot.device.model)
                    .font(.headline)
            } icon: {
                Image(systemName: "headphones")
                    .foregroundStyle(isConnected ? .green : .secondary)
            }

            Spacer(minLength: 8)

            if let firmware = model.snapshot.device.headsetFirmware {
                Text("Firmware \(firmware)")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var isConnected: Bool {
        if case .connected = model.snapshot.connection { true } else { false }
    }

}

private struct RecoveryMessage: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let symbol: String
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(message).foregroundStyle(.secondary)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                }
            }
        } icon: {
            Image(systemName: symbol)
        }
    }
}

private struct ConfigurableSettingRow: View {
    let key: HeadsetSettingKey
    @Bindable var model: HeadsetModel

    private var readiness: CapabilityReadiness { model.readiness(for: key) }
    private var isPending: Bool { model.pendingSettings.contains(key) }
    private var isSensitivityGated: Bool {
        guard key == .quickPauseSensitivity else { return false }
        if case .boolean(let enabled) = model.value(for: .quickPause) { return !enabled }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(key.title)
                    .font(.body)
                    .help(String(localized: key.explanation))
                    .accessibilityHint(Text(key.explanation))
                Spacer(minLength: 6)
                valueOrControl
            }
            .frame(minHeight: SettingsVisualMetrics.rowHeight)
            if let exceptionText {
                AccessStatus(text: exceptionText, symbol: accessSymbol)
                    .accessibilityIdentifier("setting.status.\(key.rawValue)")
                    .padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var valueOrControl: some View {
        if isPending {
            ProgressView().controlSize(.small).accessibilityLabel("Saving…")
        } else if isSensitivityGated {
            StaticSettingValue(key: key, value: model.value(for: key), fallback: "Requires Quick Pause")
        } else if readiness.allowsWrite {
            if let value = model.value(for: key) {
                writableControl(value)
                    .disabled(model.discoveryState == .running)
            } else if readiness == .experimental {
                ExperimentalSettingMenu(key: key) { model.set(key, to: $0) }
                    .disabled(model.discoveryState == .running)
            } else {
                StaticSettingValue(key: key, value: nil)
            }
        } else {
            StaticSettingValue(key: key, value: model.value(for: key))
        }
    }

    @ViewBuilder
    private func writableControl(_ value: SettingValue) -> some View {
        switch key.controlKind {
        case .toggle:
            Toggle(
                isOn: Binding(
                    get: { if case .boolean(let enabled) = value { enabled } else { false } },
                    set: { model.set(key, to: .boolean($0)) }
                )
            ) {
                Text(key.title)
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel(Text(key.title))
            .accessibilityIdentifier("setting.toggle.\(key.rawValue)")
            .fixedSize()
        case .choices:
            NativeAccessiblePicker(
                label: String(localized: key.title),
                choices: key.choices,
                selection: Binding(
                    get: { if case .choice(let choice) = value { choice } else { "" } },
                    set: { model.set(key, to: .choice($0)) }
                )
            )
            .frame(width: 140)
        case .level, .text, .action, .readOnlyValue:
            StaticSettingValue(key: key, value: value)
        }
    }

    private var exceptionText: String? {
        if isPending { return "Saving…" }
        if isSensitivityGated { return "Requires Quick Pause" }
        return switch readiness {
        case .ready, .experimental: nil
        case .readOnly, .validationPending: "Read Only"
        case .unavailable: "Unavailable"
        }
    }

    private var accessSymbol: String {
        if isPending { return "arrow.triangle.2.circlepath" }
        if isSensitivityGated { return "link.badge.plus" }
        return readiness.allowsWrite ? "pencil" : "lock.fill"
    }
}

private struct ReadOnlySettingRow: View {
    let key: HeadsetSettingKey
    @Bindable var model: HeadsetModel

    var body: some View {
        HStack(spacing: 8) {
            Text(key.title)
                .font(.body)
                .lineLimit(2)
                .help(String(localized: key.explanation))
            Spacer(minLength: 6)
            StaticSettingValue(key: key, value: model.value(for: key))
        }
        .frame(minHeight: SettingsVisualMetrics.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AccessStatus: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
    }
}

private struct StaticSettingValue: View {
    let key: HeadsetSettingKey
    let value: SettingValue?
    var fallback = "Not reported"

    var body: some View {
        Text(formattedValue)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .accessibilityLabel(Text(key.title))
            .accessibilityValue(formattedValue)
            .accessibilityIdentifier("setting.value.\(key.rawValue)")
    }

    private var formattedValue: String {
        guard let value else { return fallback }
        switch value {
        case .boolean(let enabled): return enabled ? "On" : "Off"
        case .integer(let number): return number.formatted()
        case .text(let text): return text
        case .choice(let choice):
            return key.choices.first(where: { $0.id == choice }).map { String(localized: $0.title) } ?? choice
        }
    }
}

private struct LaunchAtLoginRow: View {
    @Bindable var model: LaunchAtLoginModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Launch at Login")
                Spacer(minLength: 6)
                Toggle("Launch at Login", isOn: Binding(
                    get: { model.isEnabled },
                    set: model.setEnabled
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel("Launch at Login")
                .accessibilityIdentifier("launchAtLogin.toggle")
                .disabled(model.state == .updating)
                stateLabel
            }
            .frame(height: 24)

            if model.state == .requiresApproval {
                Button("Open Login Items…", action: model.openSystemSettings)
                    .controlSize(.small)
            }
            if case .failed(let message) = model.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var stateLabel: some View {
        switch model.state {
        case .enabled:
            AccessStatus(text: "Enabled", symbol: "checkmark.circle.fill")
        case .disabled:
            AccessStatus(text: "Off", symbol: "minus.circle")
        case .requiresApproval:
            AccessStatus(text: "Approval Required", symbol: "exclamationmark.circle")
        case .updating:
            ProgressView().controlSize(.small).accessibilityLabel("Updating…")
        case .failed:
            AccessStatus(text: "Unavailable", symbol: "exclamationmark.triangle")
        }
    }
}

private enum BluetoothPrivacySettings {
    static func open() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct NativeAccessiblePicker: NSViewRepresentable {
    let label: String
    let choices: [SettingChoice]
    @Binding var selection: String
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        button.setAccessibilityElement(true)
        button.setAccessibilityRole(.popUpButton)
        button.setAccessibilityLabel(label)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let options = choices.map { ($0.id, String(localized: $0.title)) }
        context.coordinator.selection = $selection
        context.coordinator.optionIDs = options.map(\.0)
        if button.itemTitles != options.map(\.1) {
            button.removeAllItems()
            button.addItems(withTitles: options.map(\.1))
        }
        if let index = options.firstIndex(where: { $0.0 == selection }) { button.selectItem(at: index) }
        button.isEnabled = isEnabled
        button.setAccessibilityLabel(label)
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<String>
        var optionIDs: [String] = []
        init(selection: Binding<String>) { self.selection = selection }
        @objc func changed(_ sender: NSPopUpButton) {
            guard optionIDs.indices.contains(sender.indexOfSelectedItem) else { return }
            selection.wrappedValue = optionIDs[sender.indexOfSelectedItem]
        }
    }
}

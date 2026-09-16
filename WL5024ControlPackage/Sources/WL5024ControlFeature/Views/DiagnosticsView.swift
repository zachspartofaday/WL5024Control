import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct HeadsetDiagnosticsView: View {
    @Bindable var model: HeadsetModel
    @State private var exportPhase: DiagnosticExportPhase = .idle
    @State private var exportAlert: DiagnosticExportAlert?
    @State private var exportFocusRequest = 0
    @State private var exportButtonFocused = false

    public init(model: HeadsetModel) {
        self.model = model
    }

    public var body: some View {
        DetailPageContainer {
            diagnosticSection("Connection") {
                VStack(spacing: 8) {
                    selectableValue("Demo mode", model.demoMode ? "On" : "Off")
                    selectableValue("Transport", model.snapshot.device.transport?.rawValue.capitalized ?? "None")
                    if let updated = model.snapshot.lastUpdated {
                        selectableValue("Last update", updated.formatted(date: .abbreviated, time: .standard))
                    }
                    if let attempted = model.snapshot.lastAttemptedAt {
                        selectableValue("Last attempted", attempted.formatted(date: .abbreviated, time: .standard))
                    }

                    HStack(spacing: 12) {
                        DiagnosticExportButton(
                            isEnabled: exportPhase == .idle && model.discoveryState != .running,
                            focusRequest: exportFocusRequest,
                            isFocused: $exportButtonFocused,
                            action: exportLog
                        )

                        if exportPhase != .idle {
                            ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(exportPhase.label)
                            .accessibilityIdentifier("diagnostics.export.progress")
                            Text(exportPhase.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("diagnostics.export.phase")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if ProcessInfo.processInfo.arguments.contains("--ui-focus-probe") {
                        Text(exportButtonFocused ? "Export button focused" : "Export button not focused")
                            .font(.caption2)
                            .accessibilityIdentifier("diagnostics.export.focus")
                    }

                    Text("For the best capture, connect both Bluetooth and the USB receiver, operate the headset controls for a minute, then export the log.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            diagnosticSection("Read-only discovery") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Queries the recovered composite wear-detection getter, every byte-sized module of the preference getter, the Android Bluetooth SDK's typed status getters, the firmware-v4 UC getters, and the environment-detection and Smart Switch getters. It never generates setters, maintenance, reset, pairing, or firmware commands.")
                        .fixedSize(horizontal: false, vertical: true)

                    Text("A complete run sends 266 queries and can take about four minutes when most modules are silent. Keep the headset nearby, then export the log when it finishes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if model.discoveryState == .running {
                        Button("Cancel Discovery", role: .cancel) {
                            model.cancelReadOnlyDiscovery()
                        }
                        .accessibilityIdentifier("diagnostics.discovery.cancel")
                    } else {
                        Button("Run Read-only Discovery", systemImage: "magnifyingglass") {
                            model.runReadOnlyDiscovery()
                        }
                        .disabled(!canRunDiscovery || model.isCommandInFlight)
                        .accessibilityIdentifier("diagnostics.discovery.run")
                    }

                    discoveryStatus
                }
            }

            diagnosticSection("Recovered protocol") {
                VStack(spacing: 8) {
                    selectableBytes("Frame header", "05 5A")
                    selectableBytes("Read wear and automation flags", hex(WL5024Command.getWearDetection.frame.encoded))
                    selectableBytes("Read-only qualification probe", hex(WL5024Command.getPreference(module: 1).frame.encoded))
                    selectableBytes("Example composite write", hex(WL5024Command.setWearDetection(0).frame.encoded))
                    selectableBytes("Read advanced transparency", hex(WL5024Command.getPreference(module: 8).frame.encoded))
                    selectableBytes("Read sidetone", hex(WL5024Command.getPreference(module: 6).frame.encoded))
                    selectableBytes("Read busy light", hex(WL5024Command.getBusyLight.frame.encoded))
                    selectableBytes("Read voice guidance", hex(WL5024Command.getVoiceGuidance.frame.encoded))
                    selectableBytes("Read voice prompts (Windows-only evidence)", hex(WL5024Command.getPreference(module: 9).frame.encoded))
                    selectableBytes("Read LE Audio feature mode", hex(WL5024Command.getLEAudioFeatureMode.frame.encoded))
                }
            }

            diagnosticSection("Capability map") {
                VStack(spacing: 0) {
                    ForEach(Array(CapabilityCatalog.all.enumerated()), id: \.element.id) { index, definition in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(definition.key.title)
                                Spacer()
                                Text(definition.qualification.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(definition.recipe.summary)
                                .font(.caption.monospaced())
                            Text(definition.evidence)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .textSelection(.enabled)
                        .padding(.vertical, DetailLayoutMetrics.rowVerticalInset)
                        if index < CapabilityCatalog.all.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
        .alert("Diagnostic Export", isPresented: Binding(
            get: { exportAlert != nil },
            set: { presented in
                if !presented {
                    exportAlert = nil
                    restoreExportFocus()
                }
            }
        )) {
            if case .failed = exportAlert {
                Button("Choose Another Location", action: exportLog)
                Button("Cancel", role: .cancel, action: dismissExportAlert)
            } else {
                Button("Done", role: .cancel, action: dismissExportAlert)
            }
        } message: {
            switch exportAlert {
            case .saved(let filename, let byteCount):
                Text("Saved \(byteCount.formatted(.byteCount(style: .file))) to \(filename).")
            case .failed:
                Text("Unable to save the log. Choose another location and try again.")
            case nil:
                EmptyView()
            }
        }
    }

    private func diagnosticSection<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            SettingsCard(content: content)
        }
    }

    private func selectableValue(_ label: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .monospacedDigit()
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var discoveryStatus: some View {
        switch model.discoveryState {
        case .idle:
            if !canRunDiscovery {
                Text("Connect the headset over Bluetooth to run discovery.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .running:
            if let progress = model.discoveryProgress {
                ProgressView(
                    value: Double(progress.completed),
                    total: Double(progress.total)
                ) {
                    Text("Discovering headset settings")
                } currentValueLabel: {
                    Text("\(progress.completed) of \(progress.total)")
                        .monospacedDigit()
                }
                .accessibilityIdentifier("diagnostics.discovery.progress")
                Text(progress.currentProbe)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                ProgressView("Preparing read-only discovery…")
                    .accessibilityIdentifier("diagnostics.discovery.progress")
            }
        case .completed:
            if let summary = model.lastDiscoverySummary {
                Text("Completed \(summary.queryCount) queries: \(summary.responseCount) responses, \(summary.timeoutCount) timeouts, and \(summary.failureCount) errors. Decoded \(summary.decodedSettingCount) settings in \(summary.elapsedSeconds.formatted(.number.precision(.fractionLength(1)))) seconds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("diagnostics.discovery.summary")
            }
        case .cancelled:
            Text("Discovery cancelled. Partial results remain in the diagnostic log.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text("Discovery stopped: \(message)")
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private var canRunDiscovery: Bool {
        if model.demoMode { return true }
        if case .connected(.bluetooth) = model.snapshot.connection { return true }
        return false
    }

    private func selectableBytes(_ label: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .accessibilityIdentifier("diagnostics.protocol.value")
        }
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func exportLog() {
        guard exportPhase == .idle else { return }
        Task { @MainActor in
            do {
                exportPhase = .collecting
                if ProcessInfo.processInfo.arguments.contains("--ui-observe-export-progress") {
                    try await Task.sleep(for: .seconds(2))
                }
                let report = try await model.collectDiagnosticReport()
                exportPhase = .choosingLocation
                guard let url = await chooseExportURL() else {
                    exportPhase = .idle
                    restoreExportFocus()
                    return
                }
                exportPhase = .encoding
                let data = try await DiagnosticExporter.encode(report)
                exportPhase = .writing
                try await DiagnosticExporter.write(data, to: url)
                exportPhase = .idle
                exportAlert = .saved(filename: url.lastPathComponent, byteCount: data.count)
            } catch is CancellationError {
                exportPhase = .idle
                restoreExportFocus()
            } catch {
                DiagnosticRecorder.shared.record(
                    "export",
                    "Diagnostic export failed",
                    details: ["error": error.localizedDescription]
                )
                exportPhase = .idle
                exportAlert = .failed
            }
        }
    }

    private func chooseExportURL() async -> URL? {
        if ProcessInfo.processInfo.arguments.contains("--ui-export-direct") {
            return URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "WL5024ControlUITest.wl5024log.json")
        }
        let panel = NSSavePanel()
        panel.title = "Export WL5024 Diagnostic Log"
        panel.nameFieldStringValue = "WL5024-diagnostics-\(Self.filenameTimestamp).wl5024log.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow {
            response = await withCheckedContinuation { continuation in
                panel.beginSheetModal(for: window) { result in
                    continuation.resume(returning: result)
                }
            }
        } else {
            response = panel.runModal()
        }
        return response == .OK ? panel.url : nil
    }

    private func dismissExportAlert() {
        exportAlert = nil
        restoreExportFocus()
    }

    private func restoreExportFocus() {
        Task { @MainActor in
            NSApp.activate()
            let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" })
            window?.makeKeyAndOrderFront(nil)
            await Task.yield()
            exportFocusRequest &+= 1
        }
    }

    private static var filenameTimestamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }
}

private struct DiagnosticExportButton: NSViewRepresentable {
    let isEnabled: Bool
    let focusRequest: Int
    @Binding var isFocused: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action, isFocused: $isFocused)
    }

    func makeNSView(context: Context) -> FocusReportingButton {
        let button = FocusReportingButton(
            title: String(localized: "Collect & Export Log…", bundle: #bundle),
            target: context.coordinator,
            action: #selector(Coordinator.performAction)
        )
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.setAccessibilityIdentifier("diagnostics.export.button")
        button.onFocusChange = context.coordinator.reportFocus
        return button
    }

    func updateNSView(_ button: FocusReportingButton, context: Context) {
        context.coordinator.action = action
        context.coordinator.isFocused = $isFocused
        button.isEnabled = isEnabled
        guard focusRequest != context.coordinator.lastFocusRequest else { return }
        context.coordinator.lastFocusRequest = focusRequest
        DispatchQueue.main.async { [weak button] in
            guard let button, let window = button.window else { return }
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(button)
        }
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        var isFocused: Binding<Bool>
        var lastFocusRequest = 0

        init(action: @escaping () -> Void, isFocused: Binding<Bool>) {
            self.action = action
            self.isFocused = isFocused
        }

        @objc func performAction() {
            action()
        }

        func reportFocus(_ focused: Bool) {
            if isFocused.wrappedValue != focused {
                isFocused.wrappedValue = focused
            }
        }
    }
}

private final class FocusReportingButton: NSButton {
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder { onFocusChange?(true) }
        return becameFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let resignedFirstResponder = super.resignFirstResponder()
        if resignedFirstResponder { onFocusChange?(false) }
        return resignedFirstResponder
    }
}

private enum DiagnosticExportPhase: Equatable {
    case idle
    case collecting
    case choosingLocation
    case encoding
    case writing

    var label: LocalizedStringResource {
        switch self {
        case .idle: LocalizedStringResource("Ready", bundle: #bundle)
        case .collecting: LocalizedStringResource("Collecting diagnostic data…", bundle: #bundle)
        case .choosingLocation: LocalizedStringResource("Choosing a save location…", bundle: #bundle)
        case .encoding: LocalizedStringResource("Encoding diagnostic log…", bundle: #bundle)
        case .writing: LocalizedStringResource("Writing diagnostic log…", bundle: #bundle)
        }
    }
}

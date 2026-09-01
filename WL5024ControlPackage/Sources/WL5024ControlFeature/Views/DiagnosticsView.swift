import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DiagnosticsView: View {
    @Bindable var model: HeadsetModel
    @State private var isExporting = false
    @State private var exportAlert: DiagnosticExportAlert?

    var body: some View {
        List {
            Section("Connection") {
                LabeledContent("Demo mode", value: model.demoMode ? "On" : "Off")
                LabeledContent("Transport", value: model.snapshot.device.transport?.rawValue.capitalized ?? "None")
                if let updated = model.snapshot.lastUpdated {
                    LabeledContent("Last update", value: updated.formatted(date: .abbreviated, time: .standard))
                }
                if let attempted = model.snapshot.lastAttemptedAt {
                    LabeledContent("Last attempted", value: attempted.formatted(date: .abbreviated, time: .standard))
                }
                Button {
                    exportLog()
                } label: {
                    Label("Collect & Export Log…", systemImage: "square.and.arrow.up")
                }
                .disabled(isExporting)

                Text("For the best capture, connect both Bluetooth and the USB receiver, operate the headset controls for a minute, then export the log.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Recovered protocol") {
                LabeledContent("Frame header", value: "00 05 5A")
                LabeledContent("Read automatic media", value: hex(WL5024Command.getAutomaticMedia.frame.encoded))
                LabeledContent("Disable automatic media", value: hex(WL5024Command.setAutomaticMedia(false).frame.encoded))
            }

            Section("Capability map") {
                ForEach(CapabilityCatalog.all) { definition in
                    VStack(alignment: .leading, spacing: 3) {
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
                    .padding(.vertical, 3)
                }
            }
        }
        .alert("Diagnostic Export", isPresented: Binding(
            get: { exportAlert != nil },
            set: { if !$0 { exportAlert = nil } }
        )) {
            if case .failed = exportAlert {
                Button("Choose Another Location", action: exportLog)
                Button("Cancel", role: .cancel) { exportAlert = nil }
            } else {
                Button("Done", role: .cancel) { exportAlert = nil }
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

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func exportLog() {
        isExporting = true
        Task { @MainActor in
            defer { isExporting = false }
            do {
                let report = try await model.collectDiagnosticReport()
                let panel = NSSavePanel()
                panel.title = "Export WL5024 Diagnostic Log"
                panel.nameFieldStringValue = "WL5024-diagnostics-\(Self.filenameTimestamp).wl5024log.json"
                panel.allowedContentTypes = [.json]
                panel.canCreateDirectories = true

                guard panel.runModal() == .OK, let url = panel.url else { return }
                let data = try await DiagnosticExporter.encode(report)
                try await DiagnosticExporter.write(data, to: url)
                exportAlert = .saved(filename: url.lastPathComponent, byteCount: data.count)
            } catch is CancellationError {
                return
            } catch {
                DiagnosticRecorder.shared.record(
                    "export",
                    "Diagnostic export failed",
                    details: ["error": error.localizedDescription]
                )
                exportAlert = .failed
            }
        }
    }

    private static var filenameTimestamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }
}

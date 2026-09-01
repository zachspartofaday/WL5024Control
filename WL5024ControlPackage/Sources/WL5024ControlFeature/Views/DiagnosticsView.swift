import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DiagnosticsView: View {
    @Bindable var model: HeadsetModel
    @State private var isExporting = false
    @State private var exportMessage: String?

    var body: some View {
        List {
            Section("Connection") {
                LabeledContent("Demo mode", value: model.demoMode ? "On" : "Off")
                LabeledContent("Transport", value: model.snapshot.device.transport?.rawValue.capitalized ?? "None")
                if let updated = model.snapshot.lastUpdated {
                    LabeledContent("Last update", value: updated.formatted(date: .abbreviated, time: .standard))
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
        .alert(
            "Diagnostic export",
            isPresented: Binding(
                get: { exportMessage != nil },
                set: { if !$0 { exportMessage = nil } }
            )
        ) {
            Button("OK") { exportMessage = nil }
        } message: {
            Text(exportMessage ?? "")
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
                let data = try await model.collectDiagnosticReport()
                let panel = NSSavePanel()
                panel.title = "Export WL5024 Diagnostic Log"
                panel.nameFieldStringValue = "WL5024-diagnostics-\(Self.filenameTimestamp).wl5024log.json"
                panel.allowedContentTypes = [.json]
                panel.canCreateDirectories = true

                guard panel.runModal() == .OK, let url = panel.url else { return }
                try data.write(to: url, options: .atomic)
                exportMessage = "Saved \(data.count.formatted(.byteCount(style: .file))) to \(url.lastPathComponent)."
            } catch {
                exportMessage = error.localizedDescription
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

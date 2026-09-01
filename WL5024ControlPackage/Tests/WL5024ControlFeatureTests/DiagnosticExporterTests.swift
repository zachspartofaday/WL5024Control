import Foundation
import Testing
@testable import WL5024ControlFeature

struct DiagnosticExporterTests {
    @Test @MainActor func encodesMaximumSizedCaptureOffTheRecorderSnapshot() async throws {
        let base = DiagnosticRecorder.shared.report(snapshot: .demo())
        let entries = (0..<5_000).map { index in
            DiagnosticEntry(
                category: "fixture",
                message: "HID report \(index)",
                details: ["bytes": String(repeating: "A5 ", count: 128)]
            )
        }
        let report = DiagnosticReport(
            formatVersion: base.formatVersion,
            generatedAt: base.generatedAt,
            appVersion: base.appVersion,
            operatingSystem: base.operatingSystem,
            privacy: base.privacy,
            device: base.device,
            capabilities: base.capabilities,
            entries: entries
        )

        let data = try await DiagnosticExporter.encode(report)
        #expect(data.count > 1_000_000)
    }

    @Test @MainActor func honorsCancellationBeforeEncoding() async {
        let report = DiagnosticRecorder.shared.report(snapshot: .demo())
        let task = Task {
            try Task.checkCancellation()
            return try await DiagnosticExporter.encode(report)
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}

import Foundation
import Testing
@testable import WL5024ControlFeature

struct CapabilityCatalogTests {
    @Test func coversEveryExposedSettingExactlyOnce() {
        #expect(CapabilityCatalog.all.count == HeadsetSettingKey.allCases.count)
        #expect(Set(CapabilityCatalog.all.map(\.key)) == Set(HeadsetSettingKey.allCases))
    }

    @Test func allSettingsHaveControlsAndEvidence() {
        for definition in CapabilityCatalog.all {
            #expect(!definition.evidence.isEmpty)
            if case .choices = definition.key.controlKind {
                #expect(!definition.key.choices.isEmpty)
            }
        }
    }

    @Test @MainActor func mockControllerCanSetEveryNonActionCapability() async throws {
        let controller = MockHeadsetController()
        await controller.start()
        for key in HeadsetSettingKey.allCases where key.controlKind != .action {
            let snapshot = try await controller.set(key, value: key.defaultValue)
            #expect(snapshot.values[key] == key.defaultValue)
        }
        _ = try await controller.perform(.findMyHeadset)
    }

    @Test @MainActor func diagnosticReportIncludesCaptureAndCapabilityMap() throws {
        DiagnosticRecorder.shared.record(
            "test",
            "receiver captured",
            details: ["serialNumber": "PERSONAL-DEVICE"]
        )
        let data = try DiagnosticRecorder.shared.encodedReport(snapshot: .demo())
        let report = try JSONDecoder.iso8601.decode(DiagnosticReport.self, from: data)

        #expect(report.formatVersion == 1)
        #expect(report.capabilities.count == HeadsetSettingKey.allCases.count)
        #expect(report.entries.contains { $0.details["serialNumber"] == "PERSONAL-DEVICE" })
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

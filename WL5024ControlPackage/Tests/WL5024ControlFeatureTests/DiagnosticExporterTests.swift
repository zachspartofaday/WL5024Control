import Foundation
import Testing
@testable import WL5024ControlFeature

struct DiagnosticExporterTests {
    @Test @MainActor func versionTwoExportPreservesInventoryAndRetentionAfterRollover() async throws {
        let recorder = DiagnosticRecorder(maximumEntries: 2)
        let identifier = UUID()
        recorder.setBluetoothConnection(.init(
            name: "Fixture", identifier: identifier,
            diagnosticDetails: ["notifyCharacteristic": "fixture-characteristic"]
        ))
        for index in 0..<5 { recorder.record("fixture", "event \(index)") }
        let report = recorder.report(snapshot: .demo())
        let data = try await DiagnosticExporter.encode(report)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DiagnosticReport.self, from: data)
        #expect(decoded.formatVersion == 2)
        #expect(decoded.retention.droppedCount == 3)
        #expect(decoded.retention.totalRecordedCount == 5)
        #expect(decoded.retention.retainedCount == 2)
        #expect(decoded.retention.oldestEntryAt == decoded.entries.first?.timestamp)
        #expect(decoded.retention.newestEntryAt == decoded.entries.last?.timestamp)
        #expect(decoded.inventory.bluetooth?.identifier == identifier.uuidString)
        #expect(decoded.inventory.bluetooth?.details["notifyCharacteristic"] == "fixture-characteristic")
        #expect(decoded.entries.map(\.message) == ["event 3", "event 4"])
    }

    @Test @MainActor func emptyCaptureReportsNoRetainedTimeRange() {
        let report = DiagnosticRecorder(maximumEntries: 2).report(snapshot: .demo())
        #expect(report.retention.retainedCount == 0)
        #expect(report.retention.totalRecordedCount == 0)
        #expect(report.retention.droppedCount == 0)
        #expect(report.retention.oldestEntryAt == nil)
        #expect(report.retention.newestEntryAt == nil)
        #expect(report.inventory.bluetooth == nil)
        #expect(report.inventory.receiverInterfaces.isEmpty)
    }

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
            retention: .init(capacity: 5_000, retainedCount: 5_000, totalRecordedCount: 5_000,
                             droppedCount: 0, oldestEntryAt: entries.first?.timestamp,
                             newestEntryAt: entries.last?.timestamp),
            inventory: base.inventory,
            entries: entries
        )

        let data = try await DiagnosticExporter.encode(report)
        #expect(data.count > 1_000_000)
    }

    @Test @MainActor func honorsCancellationBeforeEncoding() async {
        let report = DiagnosticRecorder.shared.report(snapshot: .demo())
        let barrier = CancellationBarrier()
        let task = Task {
            await barrier.wait()
            return try await DiagnosticExporter.encode(report)
        }
        await barrier.waitUntilEntered()
        task.cancel()
        barrier.release()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test func ringBufferWrapsAndPreservesChronologicalOrder() {
        var buffer = FixedCapacityRingBuffer<Int>(capacity: 5)
        for value in 0..<8 {
            buffer.append(value)
        }

        #expect(buffer.count == 5)
        #expect(buffer.droppedCount == 3)
        #expect(buffer.elements == [3, 4, 5, 6, 7])
    }

    @Test @MainActor func recorderRetainsLast5000Of50000EntriesInOrder() {
        let recorder = DiagnosticRecorder(maximumEntries: 5_000)
        for index in 0..<50_000 {
            recorder.record("volume", "entry", details: ["index": String(index)])
        }

        #expect(recorder.entries.count == 5_000)
        #expect(recorder.entries.first?.details["index"] == "45000")
        #expect(recorder.entries.last?.details["index"] == "49999")
        let retention = recorder.report(snapshot: .demo()).retention
        #expect(retention.capacity == 5_000)
        #expect(retention.retainedCount == 5_000)
        #expect(retention.totalRecordedCount == 50_000)
        #expect(retention.droppedCount == 45_000)
        #expect(retention.oldestEntryAt == recorder.entries.first?.timestamp)
        #expect(retention.newestEntryAt == recorder.entries.last?.timestamp)
    }
}

@MainActor
private final class CancellationBarrier {
    private let enteredStream: AsyncStream<Void>
    private let enteredContinuation: AsyncStream<Void>.Continuation
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init() {
        let pair = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        enteredStream = pair.stream
        enteredContinuation = pair.continuation
    }

    func wait() async {
        enteredContinuation.yield()
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        for await _ in enteredStream { break }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

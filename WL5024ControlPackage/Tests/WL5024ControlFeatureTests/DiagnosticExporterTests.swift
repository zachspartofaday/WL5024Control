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

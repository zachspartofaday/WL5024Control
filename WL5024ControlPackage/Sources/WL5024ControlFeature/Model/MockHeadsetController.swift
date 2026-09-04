import Foundation

@MainActor
public final class MockHeadsetController: HeadsetController {
    private var snapshot: HeadsetSnapshot
    private let stream: AsyncStream<HeadsetEvent>
    private let continuation: AsyncStream<HeadsetEvent>.Continuation
    private var revision: UInt64 = 0
    private let connectedState: ConnectionState
    private let discoveryStepDelay: Duration

    public init(
        snapshot: HeadsetSnapshot = .demo(),
        discoveryStepDelay: Duration = .milliseconds(100)
    ) {
        self.snapshot = snapshot
        connectedState = snapshot.connection
        self.discoveryStepDelay = discoveryStepDelay
        let pair = AsyncStream.makeStream(
            of: HeadsetEvent.self,
            bufferingPolicy: .bufferingNewest(20)
        )
        stream = pair.stream
        continuation = pair.continuation
    }

    public func events() async -> AsyncStream<HeadsetEvent> { stream }

    public func start() async -> HeadsetStateUpdate {
        snapshot.connection = connectedState
        return publish()
    }

    public func stop() async -> HeadsetStateUpdate {
        snapshot.connection = .idle
        return publish()
    }

    public func refresh() async throws -> HeadsetStateUpdate {
        snapshot.lastUpdated = .now
        return publish()
    }

    public func set(
        _ key: HeadsetSettingKey,
        value: SettingValue
    ) async throws -> HeadsetStateUpdate {
        guard snapshot.capabilities.contains(key) else {
            throw HeadsetError.unsupported(key)
        }
        guard Self.value(value, isValidFor: key) else {
            throw HeadsetError.invalidValue(key)
        }
        snapshot.values[key] = value
        snapshot.lastUpdated = .now
        return publish()
    }

    public func perform(_ key: HeadsetSettingKey) async throws -> HeadsetStateUpdate {
        guard CapabilityCatalog.definition(for: key).access == .action else {
            throw HeadsetError.unsupported(key)
        }
        snapshot.lastUpdated = .now
        return publish()
    }

    public func discoverReadOnly(
        progress: @escaping @MainActor @Sendable (ReadOnlyDiscoveryProgress) -> Void
    ) async throws -> ReadOnlyDiscoveryResult {
        let probes = ReadOnlyDiscoveryPlan.probes
        let startedAt = Date.now
        for (index, probe) in probes.enumerated() {
            try Task.checkCancellation()
            // Yield so demo-mode UI can render numeric progress and deliver
            // the Cancel action before the loop completes.
            try await Task.sleep(for: discoveryStepDelay)
            try Task.checkCancellation()
            progress(.init(
                completed: index + 1,
                total: probes.count,
                currentProbe: probe.identifier
            ))
        }
        snapshot.lastAttemptedAt = .now
        snapshot.lastUpdated = .now
        return ReadOnlyDiscoveryResult(
            update: publish(),
            summary: ReadOnlyDiscoverySummary(
                queryCount: probes.count,
                responseCount: 11,
                timeoutCount: probes.count - 11,
                failureCount: 0,
                decodedSettingCount: 11,
                elapsedSeconds: Date.now.timeIntervalSince(startedAt)
            )
        )
    }

    private func publish() -> HeadsetStateUpdate {
        revision &+= 1
        let update = HeadsetStateUpdate(revision: revision, snapshot: snapshot)
        continuation.yield(.snapshot(update))
        return update
    }

    private static func value(_ value: SettingValue, isValidFor key: HeadsetSettingKey) -> Bool {
        switch (key.controlKind, value) {
        case (.toggle, .boolean), (.text, .text), (.action, .boolean):
            true
        case (.choices, .choice(let choice)):
            key.choices.contains { $0.id == choice }
        case (.level(let range, _), .integer(let number)):
            range.contains(number)
        default:
            false
        }
    }
}

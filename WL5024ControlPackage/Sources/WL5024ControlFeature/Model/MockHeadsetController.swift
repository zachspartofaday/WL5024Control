import Foundation

@MainActor
public final class MockHeadsetController: HeadsetController {
    private var snapshot: HeadsetSnapshot
    private let stream: AsyncStream<HeadsetEvent>
    private let continuation: AsyncStream<HeadsetEvent>.Continuation

    public init(snapshot: HeadsetSnapshot = .demo()) {
        self.snapshot = snapshot
        let pair = AsyncStream.makeStream(
            of: HeadsetEvent.self,
            bufferingPolicy: .bufferingNewest(20)
        )
        stream = pair.stream
        continuation = pair.continuation
    }

    public func events() async -> AsyncStream<HeadsetEvent> { stream }

    public func start() async {
        continuation.yield(.snapshot(snapshot))
    }

    public func stop() async {}

    public func refresh() async throws -> HeadsetSnapshot {
        snapshot.lastUpdated = .now
        continuation.yield(.snapshot(snapshot))
        return snapshot
    }

    public func set(
        _ key: HeadsetSettingKey,
        value: SettingValue
    ) async throws -> HeadsetSnapshot {
        guard snapshot.capabilities.contains(key) else {
            throw HeadsetError.unsupported(key)
        }
        guard Self.value(value, isValidFor: key) else {
            throw HeadsetError.invalidValue(key)
        }
        snapshot.values[key] = value
        snapshot.lastUpdated = .now
        continuation.yield(.snapshot(snapshot))
        return snapshot
    }

    public func perform(_ key: HeadsetSettingKey) async throws -> HeadsetSnapshot {
        guard CapabilityCatalog.definition(for: key).access == .action else {
            throw HeadsetError.unsupported(key)
        }
        snapshot.lastUpdated = .now
        continuation.yield(.snapshot(snapshot))
        return snapshot
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

import Foundation

@MainActor
public final class LiveHeadsetController: HeadsetController {
    private let transport = TransportCoordinator()
    private var snapshot = HeadsetSnapshot(
        connection: .idle,
        capabilities: Set(HeadsetSettingKey.allCases),
        values: Dictionary(uniqueKeysWithValues: HeadsetSettingKey.allCases.map { ($0, $0.defaultValue) })
    )
    private let stream: AsyncStream<HeadsetEvent>
    private let continuation: AsyncStream<HeadsetEvent>.Continuation

    public init() {
        let pair = AsyncStream.makeStream(
            of: HeadsetEvent.self,
            bufferingPolicy: .bufferingNewest(20)
        )
        stream = pair.stream
        continuation = pair.continuation
    }

    public func events() async -> AsyncStream<HeadsetEvent> { stream }

    public func start() async {
        guard snapshot.connection == .idle else { return }
        snapshot.connection = .searching
        continuation.yield(.snapshot(snapshot))
        transport.start { [weak self] update in
            Task { @MainActor in
                self?.handle(update)
            }
        }
    }

    public func stop() async {
        transport.stop()
        snapshot.connection = .idle
        continuation.yield(.snapshot(snapshot))
    }

    public func refresh() async throws -> HeadsetSnapshot {
        guard case .connected = snapshot.connection else {
            throw HeadsetError.disconnected
        }

        do {
            let response = try await transport.transact(WL5024Command.getAutomaticMedia.frame.encoded)
            snapshot.values[.automaticMedia] = .boolean(
                try WL5024Command.getAutomaticMedia.decodeAutomaticMedia(from: response)
            )
        } catch {
            continuation.yield(.error(Self.headsetError(error)))
        }
        snapshot.lastUpdated = .now
        continuation.yield(.snapshot(snapshot))
        return snapshot
    }

    public func set(
        _ key: HeadsetSettingKey,
        value: SettingValue
    ) async throws -> HeadsetSnapshot {
        guard case .connected = snapshot.connection else {
            throw HeadsetError.disconnected
        }
        guard let command = Self.command(for: key, value: value) else {
            let definition = CapabilityCatalog.definition(for: key)
            throw HeadsetError.transport(
                "\(definition.evidence) is implemented in the settings model and awaits a physical trace to validate its \(definition.recipe.summary) packet."
            )
        }

        _ = try await transport.transact(command.frame.encoded)
        snapshot.values[key] = value
        snapshot.lastUpdated = .now
        continuation.yield(.snapshot(snapshot))
        return snapshot
    }

    public func perform(_ key: HeadsetSettingKey) async throws -> HeadsetSnapshot {
        guard case .connected = snapshot.connection else {
            throw HeadsetError.disconnected
        }
        throw HeadsetError.unsupported(key)
    }

    private func handle(_ update: TransportUpdate) {
        switch update {
        case .searching:
            snapshot.connection = .searching
        case .connectedBluetooth:
            snapshot.connection = .connected(.bluetooth)
            snapshot.device.transport = .bluetooth
        case .receiverFound:
            if case .connected = snapshot.connection { break }
            snapshot.connection = .qualificationRequired(.receiver)
            snapshot.device.transport = .receiver
        case .disconnected:
            snapshot.connection = .searching
            snapshot.device.transport = nil
        case .bluetoothPermissionDenied:
            snapshot.connection = .bluetoothPermissionDenied
        case .unavailable:
            snapshot.connection = .unavailable
        case .failed(let message):
            snapshot.connection = .failed
            continuation.yield(.error(.transport(message)))
        }
        snapshot.lastUpdated = .now
        continuation.yield(.snapshot(snapshot))
    }

    private static func command(
        for key: HeadsetSettingKey,
        value: SettingValue
    ) -> WL5024Command? {
        switch (key, value) {
        case (.automaticMedia, .boolean(let enabled)):
            .setAutomaticMedia(enabled)
        case (.advancedPassthrough, .boolean(let enabled)):
            .setPreferenceByte(module: 8, value: enabled ? 1 : 0)
        case (.voicePrompts, .boolean(let enabled)):
            .setPreferenceByte(module: 9, value: enabled ? 1 : 0)
        case (.touchControls, .boolean(let enabled)):
            .setPreferenceUInt16(module: 0, value: enabled ? 1 : 0)
        case (.environmentDetection, .boolean(let enabled)):
            .setEnvironmentDetection(enabled)
        case (.smartSwitch, .boolean(let enabled)):
            .setSmartSwitch(enabled)
        case (.sidetone, .choice(let level)):
            .setPreferenceUInt16(module: 6, value: UInt16(level) ?? 0)
        default:
            nil
        }
    }

    private static func headsetError(_ error: any Error) -> HeadsetError {
        error as? HeadsetError ?? .transport(error.localizedDescription)
    }
}

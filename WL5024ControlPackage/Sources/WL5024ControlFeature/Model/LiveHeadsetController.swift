import Foundation

@MainActor
public final class LiveHeadsetController: HeadsetController {
    private let transport: any HeadsetTransporting
    private let qualifiedWrites: Set<HeadsetSettingKey>
    private var snapshot = HeadsetSnapshot(
        connection: .idle,
        capabilities: Set(HeadsetSettingKey.allCases),
        readiness: Dictionary(uniqueKeysWithValues: HeadsetSettingKey.allCases.map { ($0, .unavailable) })
    )
    private let stream: AsyncStream<HeadsetEvent>
    private let continuation: AsyncStream<HeadsetEvent>.Continuation

    var currentSnapshot: HeadsetSnapshot { snapshot }

    public init() {
        transport = TransportCoordinator()
        qualifiedWrites = []
        let pair = AsyncStream.makeStream(
            of: HeadsetEvent.self,
            bufferingPolicy: .bufferingNewest(20)
        )
        stream = pair.stream
        continuation = pair.continuation
    }

    init(
        transport: any HeadsetTransporting,
        qualifiedWrites: Set<HeadsetSettingKey> = []
    ) {
        self.transport = transport
        self.qualifiedWrites = qualifiedWrites
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
            MainActor.assumeIsolated {
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

        snapshot.lastAttemptedAt = .now
        continuation.yield(.snapshot(snapshot))
        let response = try await transport.transact(
            WL5024Command.getAutomaticMedia.transaction,
            timeout: .seconds(3)
        )
        snapshot.values[.automaticMedia] = .boolean(
            try WL5024Command.getAutomaticMedia.decodeAutomaticMedia(from: response)
        )
        snapshot.valueConfidence[.automaticMedia] = .deviceConfirmed
        snapshot.readiness[.automaticMedia] = qualifiedWrites.contains(.automaticMedia) ? .ready : .readOnly
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
        guard snapshot.readiness(for: key).allowsWrite else {
            throw HeadsetError.unsupported(key)
        }
        guard let command = Self.command(for: key, value: value) else {
            let definition = CapabilityCatalog.definition(for: key)
            throw HeadsetError.transport(
                "\(definition.evidence) is implemented in the settings model and awaits a physical trace to validate its \(definition.recipe.summary) packet."
            )
        }

        snapshot.lastAttemptedAt = .now
        continuation.yield(.snapshot(snapshot))
        _ = try await transport.transact(command.transaction, timeout: .seconds(3))

        if key == .automaticMedia, case .boolean(let requestedValue) = value {
            let readback = try await transport.transact(
                WL5024Command.getAutomaticMedia.transaction,
                timeout: .seconds(3)
            )
            let storedValue = try WL5024Command.getAutomaticMedia.decodeAutomaticMedia(from: readback)
            guard storedValue == requestedValue else {
                throw HeadsetError.readbackMismatch(key)
            }
        }
        snapshot.values[key] = value
        snapshot.valueConfidence[key] = .deviceConfirmed
        snapshot.lastUpdated = .now
        continuation.yield(.snapshot(snapshot))
        return snapshot
    }

    public func perform(_ key: HeadsetSettingKey) async throws -> HeadsetSnapshot {
        guard case .connected = snapshot.connection else {
            throw HeadsetError.disconnected
        }
        guard snapshot.readiness(for: key).allowsWrite else {
            throw HeadsetError.unsupported(key)
        }
        throw HeadsetError.unsupported(key)
    }

    private func handle(_ update: TransportUpdate) {
        TransportStateReducer.apply(update, to: &snapshot)
        updateReadiness()

        if case .failed(_, let message, false) = update {
            continuation.yield(.error(.transport(message)))
        } else if case .unsolicitedBluetooth(let data) = update {
            DiagnosticRecorder.shared.record(
                "bluetooth-unsolicited",
                "Notification did not match the pending transaction",
                details: ["bytes": DiagnosticRecorder.hex(data)]
            )
        }
        continuation.yield(.snapshot(snapshot))
    }

    private func updateReadiness() {
        let readiness: CapabilityReadiness
        switch snapshot.connection {
        case .connected(.bluetooth): readiness = .validationPending
        case .connected(.receiver): readiness = .validationPending
        default: readiness = .unavailable
        }
        for key in HeadsetSettingKey.allCases {
            snapshot.readiness[key] = qualifiedWrites.contains(key) && readiness == .validationPending
                ? .ready
                : readiness
        }
        if case .connected(.bluetooth) = snapshot.connection,
           snapshot.confidence(for: .automaticMedia) == .deviceConfirmed,
           !qualifiedWrites.contains(.automaticMedia) {
            snapshot.readiness[.automaticMedia] = .readOnly
        }
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

}

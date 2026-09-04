import Foundation

@MainActor
public final class LiveHeadsetController: HeadsetController {
    private let transport: any HeadsetTransporting
    private let writeQualifications: [HeadsetSettingKey: WriteQualification]
    private var snapshot = HeadsetSnapshot(
        connection: .idle,
        capabilities: Set(HeadsetSettingKey.allCases),
        readiness: Dictionary(uniqueKeysWithValues: HeadsetSettingKey.allCases.map { ($0, .unavailable) })
    )
    private let stream: AsyncStream<HeadsetEvent>
    private let continuation: AsyncStream<HeadsetEvent>.Continuation
    private var revision: UInt64 = 0
    private static let readableKeys = ShippingSettingReads.orderedKeys

    var currentSnapshot: HeadsetSnapshot { snapshot }

    public init() {
        transport = TransportCoordinator()
        writeQualifications = ShippingWriteQualifications.all
        let pair = AsyncStream.makeStream(
            of: HeadsetEvent.self,
            bufferingPolicy: .bufferingNewest(20)
        )
        stream = pair.stream
        continuation = pair.continuation
    }

    init(
        transport: any HeadsetTransporting,
        writeQualifications: [HeadsetSettingKey: WriteQualification] = ShippingWriteQualifications.all
    ) {
        self.transport = transport
        self.writeQualifications = writeQualifications
        let pair = AsyncStream.makeStream(
            of: HeadsetEvent.self,
            bufferingPolicy: .bufferingNewest(20)
        )
        stream = pair.stream
        continuation = pair.continuation
    }

    public func events() async -> AsyncStream<HeadsetEvent> { stream }

    public func start() async -> HeadsetStateUpdate {
        guard snapshot.connection == .idle else { return currentUpdate }
        snapshot.connection = .searching
        let initialUpdate = publish()
        transport.start { [weak self] update in
            MainActor.assumeIsolated {
                self?.handle(update)
            }
        }
        return initialUpdate
    }

    public func stop() async -> HeadsetStateUpdate {
        transport.stop()
        snapshot.connection = .idle
        snapshot.device.transport = nil
        return publish()
    }

    public func refresh() async throws -> HeadsetStateUpdate {
        guard case .connected = snapshot.connection else {
            throw HeadsetError.disconnected
        }

        snapshot.lastAttemptedAt = .now
        _ = publish()
        var firstError: (any Error)?
        var confirmedAnyValue = false
        var responseCache: [Data: Result<Data, any Error>] = [:]

        for key in Self.readableKeys {
            try Task.checkCancellation()
            guard let definition = ShippingSettingReads.all[key] else { continue }

            do {
                var responses: [Data] = []
                for transaction in definition.transactions {
                    try Task.checkCancellation()
                    if let cached = responseCache[transaction.request] {
                        responses.append(try cached.get())
                    } else {
                        do {
                            let response = try await transport.transact(transaction, timeout: .seconds(3))
                            responseCache[transaction.request] = .success(response)
                            responses.append(response)
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            responseCache[transaction.request] = .failure(error)
                            throw error
                        }
                    }
                }
                snapshot.values[key] = try definition.decoder(responses)
                snapshot.valueConfidence[key] = .deviceConfirmed
                snapshot.readiness[key] = writeQualifications[key] == nil ? .readOnly : .experimental
                confirmedAnyValue = true
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                firstError = firstError ?? error
                DiagnosticRecorder.shared.record(
                    "protocol-read",
                    "Setting read failed",
                    details: [
                        "setting": key.rawValue,
                        "error": error.localizedDescription,
                    ]
                )
            }
        }

        if confirmedAnyValue {
            snapshot.lastUpdated = .now
            return publish()
        }
        throw firstError ?? HeadsetError.timeout
    }

    public func set(
        _ key: HeadsetSettingKey,
        value: SettingValue
    ) async throws -> HeadsetStateUpdate {
        guard case .connected = snapshot.connection else {
            throw HeadsetError.disconnected
        }
        guard snapshot.readiness(for: key).allowsWrite else {
            throw HeadsetError.unsupported(key)
        }
        guard let qualification = writeQualifications[key], qualification.key == key else {
            throw HeadsetError.unsupported(key)
        }

        snapshot.lastAttemptedAt = .now
        _ = publish()
        var preparationResponses: [Data] = []
        for preparation in qualification.preparationTransactions {
            try Task.checkCancellation()
            preparationResponses.append(
                try await transport.transact(preparation, timeout: .seconds(3))
            )
        }
        let writeTransactions = try qualification.writeTransactions(
            for: value,
            preparationResponses: preparationResponses
        )
        for (index, writeTransaction) in writeTransactions.enumerated() {
            try Task.checkCancellation()
            let acknowledgement = try await transport.transact(writeTransaction, timeout: .seconds(3))
            try qualification.acknowledgementValidator(index, acknowledgement)
        }
        var readBackResponses: [Data] = []
        for transaction in qualification.readBackTransactions {
            try Task.checkCancellation()
            readBackResponses.append(try await transport.transact(transaction, timeout: .seconds(3)))
        }
        let storedValue = try qualification.readBackDecoder(readBackResponses)
        guard qualification.comparison(value, storedValue) else {
            throw HeadsetError.readbackMismatch(key)
        }
        snapshot.values[key] = storedValue
        snapshot.valueConfidence[key] = .deviceConfirmed
        snapshot.lastUpdated = .now
        return publish()
    }

    public func perform(_ key: HeadsetSettingKey) async throws -> HeadsetStateUpdate {
        guard case .connected = snapshot.connection else {
            throw HeadsetError.disconnected
        }
        guard snapshot.readiness(for: key).allowsWrite else {
            throw HeadsetError.unsupported(key)
        }
        throw HeadsetError.unsupported(key)
    }

    public func discoverReadOnly(
        progress: @escaping @MainActor @Sendable (ReadOnlyDiscoveryProgress) -> Void
    ) async throws -> ReadOnlyDiscoveryResult {
        guard case .connected(.bluetooth) = snapshot.connection else {
            throw HeadsetError.disconnected
        }

        let probes = ReadOnlyDiscoveryPlan.probes
        let startedAt = Date.now
        var responseCount = 0
        var timeoutCount = 0
        var failureCount = 0
        var decodedSettings: Set<HeadsetSettingKey> = []

        snapshot.lastAttemptedAt = startedAt
        _ = publish()
        DiagnosticRecorder.shared.record(
            "protocol-discovery",
            "Read-only discovery started",
            details: [
                "preferenceModules": "0...255",
                "queryCount": probes.count.description,
                "scope": "Recovered getters only; no setters, maintenance, reset, pairing, or firmware commands",
                "timeoutMilliseconds": "750",
            ]
        )

        do {
            for (index, probe) in probes.enumerated() {
                try Task.checkCancellation()
                guard case .connected(.bluetooth) = snapshot.connection else {
                    throw HeadsetError.disconnected
                }

                progress(ReadOnlyDiscoveryProgress(
                    completed: index,
                    total: probes.count,
                    currentProbe: probe.identifier
                ))
                DiagnosticRecorder.shared.record(
                    "protocol-discovery",
                    "Sending read-only query",
                    details: [
                        "bytes": DiagnosticRecorder.hex(probe.transaction.request),
                        "index": (index + 1).description,
                        "probe": probe.identifier,
                        "queryCount": probes.count.description,
                    ]
                )

                do {
                    let response = try await transport.transact(
                        probe.transaction,
                        timeout: probe.timeout
                    )
                    responseCount += 1
                    var details = [
                        "bytes": DiagnosticRecorder.hex(response),
                        "probe": probe.identifier,
                    ]
                    if let frame = try? RaceFrame(decoding: response) {
                        details["opcode"] = String(format: "0x%04X", frame.opcode)
                        details["payload"] = DiagnosticRecorder.hex(frame.payload)
                    }

                    if let decoded = try? decodeDiscoveredSettings(probe, response: response) {
                        for setting in decoded {
                            snapshot.values[setting.key] = setting.value
                            snapshot.valueConfidence[setting.key] = .deviceConfirmed
                            snapshot.readiness[setting.key] = writeQualifications[setting.key] == nil
                                ? .readOnly
                                : .experimental
                            decodedSettings.insert(setting.key)
                        }
                        details["decodedSetting"] = decoded.map(\.key.rawValue).joined(separator: ",")
                        details["decodedValue"] = decoded.map { String(describing: $0.value) }.joined(separator: ",")
                    }
                    DiagnosticRecorder.shared.record(
                        "protocol-discovery",
                        "Read-only query received a response",
                        details: details
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch HeadsetError.timeout {
                    timeoutCount += 1
                    DiagnosticRecorder.shared.record(
                        "protocol-discovery",
                        "Read-only query timed out",
                        details: ["probe": probe.identifier]
                    )
                } catch {
                    failureCount += 1
                    DiagnosticRecorder.shared.record(
                        "protocol-discovery",
                        "Read-only query failed",
                        details: [
                            "error": error.localizedDescription,
                            "probe": probe.identifier,
                        ]
                    )
                }

                progress(ReadOnlyDiscoveryProgress(
                    completed: index + 1,
                    total: probes.count,
                    currentProbe: probe.identifier
                ))
            }
        } catch is CancellationError {
            DiagnosticRecorder.shared.record(
                "protocol-discovery",
                "Read-only discovery cancelled",
                details: [
                    "responses": responseCount.description,
                    "timeouts": timeoutCount.description,
                ]
            )
            throw CancellationError()
        } catch {
            DiagnosticRecorder.shared.record(
                "protocol-discovery",
                "Read-only discovery stopped",
                details: ["error": error.localizedDescription]
            )
            throw error
        }

        if !decodedSettings.isEmpty {
            snapshot.lastUpdated = .now
        }
        let update = decodedSettings.isEmpty ? currentUpdate : publish()
        let summary = ReadOnlyDiscoverySummary(
            queryCount: probes.count,
            responseCount: responseCount,
            timeoutCount: timeoutCount,
            failureCount: failureCount,
            decodedSettingCount: decodedSettings.count,
            elapsedSeconds: Date.now.timeIntervalSince(startedAt)
        )
        DiagnosticRecorder.shared.record(
            "protocol-discovery",
            "Read-only discovery completed",
            details: [
                "decodedSettings": summary.decodedSettingCount.description,
                "elapsedSeconds": summary.elapsedSeconds.formatted(.number.precision(.fractionLength(2))),
                "failures": summary.failureCount.description,
                "queries": summary.queryCount.description,
                "responses": summary.responseCount.description,
                "timeouts": summary.timeoutCount.description,
            ]
        )
        return ReadOnlyDiscoveryResult(update: update, summary: summary)
    }

    private func decodeDiscoveredSettings(
        _ probe: ReadOnlyProbe,
        response: Data
    ) throws -> [(key: HeadsetSettingKey, value: SettingValue)]? {
        if case .wearDetection = probe.kind {
            let flags = try WL5024Command.getWearDetection.decodeWearDetectionFlags(from: response)
            let composite = WearDetectionFlags(rawValue: flags)
            return try ShippingWriteQualifications.wearKeys.map { key in
                (key, try composite.value(for: key))
            }
        }
        if case .setting(let key) = probe.kind,
           let definition = ShippingSettingReads.all[key] {
            return [(key, try definition.decoder([response]))]
        }
        if case .environmentDetection = probe.kind,
           let definition = ShippingSettingReads.all[.environmentDetection] {
            return [(.environmentDetection, try definition.decoder([response]))]
        }
        if case .smartSwitch = probe.kind,
           let definition = ShippingSettingReads.all[.smartSwitch] {
            return [(.smartSwitch, try definition.decoder([response]))]
        }
        guard case .preference(let module) = probe.kind else { return nil }
        let key: HeadsetSettingKey
        switch module {
        case 1: key = .autoPowerOff
        case 8: key = .advancedPassthrough
        default: return nil
        }
        guard let definition = ShippingSettingReads.all[key] else { return nil }
        return [(key, try definition.decoder([response]))]
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
        _ = publish()
    }

    private func updateReadiness() {
        let baseline: CapabilityReadiness
        switch snapshot.connection {
        case .connected: baseline = .validationPending
        default: baseline = .unavailable
        }
        for key in HeadsetSettingKey.allCases {
            snapshot.readiness[key] = baseline
        }
        if case .connected(.bluetooth) = snapshot.connection {
            for key in writeQualifications.keys {
                snapshot.readiness[key] = .experimental
            }
            for key in HeadsetSettingKey.allCases
            where snapshot.confidence(for: key) == .deviceConfirmed && writeQualifications[key] == nil {
                snapshot.readiness[key] = .readOnly
            }
        }
    }

    private var currentUpdate: HeadsetStateUpdate {
        HeadsetStateUpdate(revision: revision, snapshot: snapshot)
    }

    @discardableResult
    private func publish() -> HeadsetStateUpdate {
        revision &+= 1
        let update = currentUpdate
        continuation.yield(.snapshot(update))
        return update
    }
}

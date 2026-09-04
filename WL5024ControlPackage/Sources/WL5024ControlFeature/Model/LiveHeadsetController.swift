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
        snapshot.device.bluetoothSessionId = nil
        // End of session: drop live values so a later session cannot reuse
        // them as device-confirmed (AUD-001).
        snapshot.values.removeAll()
        snapshot.valueConfidence.removeAll()
        snapshot.readiness = Dictionary(
            uniqueKeysWithValues: HeadsetSettingKey.allCases.map { ($0, .unavailable) }
        )
        snapshot.lastUpdated = nil
        snapshot.lastAttemptedAt = nil
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
        var failedKeys: Set<HeadsetSettingKey> = []
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
                failedKeys.insert(key)
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

        // Drop stale state for keys that failed so a partial refresh never
        // presents old values as freshly confirmed.
        for key in failedKeys {
            snapshot.values.removeValue(forKey: key)
            snapshot.valueConfidence.removeValue(forKey: key)
            snapshot.readiness.removeValue(forKey: key)
        }

        if confirmedAnyValue {
            if !failedKeys.isEmpty {
                DiagnosticRecorder.shared.record(
                    "protocol-read",
                    "Partial refresh completed with stale keys removed",
                    details: [
                        "failed": failedKeys.map(\.rawValue).sorted().joined(separator: ","),
                    ]
                )
            }
            snapshot.lastUpdated = .now
            return publish()
        }
        // The failed reads mutated the authoritative snapshot by removing
        // values. Publish that invalidation before surfacing the error so
        // observers cannot retain the prior successful refresh as current.
        snapshot.lastUpdated = nil
        _ = publish()
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
        if ShippingWriteQualifications.wearKeys.contains(key),
           !preparationResponses.isEmpty {
            let observed = try qualification.readBackDecoder(preparationResponses)
            try applyConfirmedReadBack(
                key: key,
                storedValue: observed,
                responses: preparationResponses
            )
            snapshot.lastUpdated = .now
            _ = publish()
        }
        let writeTransactions = try qualification.writeTransactions(
            for: value,
            preparationResponses: preparationResponses
        )
        for (index, writeTransaction) in writeTransactions.enumerated() {
            do {
                try Task.checkCancellation()
                let acknowledgement = try await transport.transactWrite(writeTransaction, timeout: .seconds(3))
                try qualification.acknowledgementValidator(index, acknowledgement)
            } catch let error as DispatchedTransactionError {
                if error.isCancellation {
                    invalidateCancelledWrite(
                        key: key,
                        step: index,
                        gattWriteAcknowledged: error.gattWriteAcknowledged
                    )
                    throw CancellationError()
                }
                throw await writeRecoveryError(
                    key: key,
                    qualification: qualification,
                    step: index,
                    earlierStepAcknowledged: index > 0,
                    underlying: error
                )
            } catch is CancellationError {
                // Cancellation before step zero is safe. Between later steps,
                // at least one write was already acknowledged, and the
                // cancelled task cannot perform a reliable read-back.
                if index > 0 {
                    invalidateCancelledWrite(
                        key: key,
                        step: index,
                        gattWriteAcknowledged: true
                    )
                }
                throw CancellationError()
            } catch HeadsetError.malformedResponse {
                // The write received an attributable response, but its shape
                // cannot prove success or rejection. Treat device state as
                // uncertain even for the first step and recover by read-back.
                throw await writeRecoveryError(
                    key: key,
                    qualification: qualification,
                    step: index,
                    earlierStepAcknowledged: index > 0,
                    underlying: HeadsetError.malformedResponse
                )
            } catch {
                // A later step failed after earlier steps were acknowledged:
                // observe and report partial device state (AUD-007). No
                // rollback is attempted without proven-safe ordering.
                if index > 0 {
                    throw await writeRecoveryError(
                        key: key,
                        qualification: qualification,
                        step: index,
                        earlierStepAcknowledged: true,
                        underlying: error
                    )
                }
                // An explicit negative acknowledgement or provable
                // pre-dispatch failure leaves the prior value authoritative.
                throw error
            }
        }
        var readBackResponses: [Data] = []
        let storedValue: SettingValue
        do {
            for transaction in qualification.readBackTransactions {
                try Task.checkCancellation()
                readBackResponses.append(try await transport.transact(transaction, timeout: .seconds(3)))
            }
            storedValue = try qualification.readBackDecoder(readBackResponses)
            try applyConfirmedReadBack(
                key: key,
                storedValue: storedValue,
                responses: readBackResponses
            )
        } catch is CancellationError {
            invalidateUnverifiedState(for: key)
            _ = publish()
            throw CancellationError()
        } catch {
            invalidateUnverifiedState(for: key)
            _ = publish()
            throw HeadsetError.transport(
                "The \(key.rawValue) change may have been applied, but its current value could not be read. Refresh or reconnect before trying again."
            )
        }
        snapshot.lastUpdated = .now
        let update = publish()
        guard qualification.comparison(value, storedValue) else {
            throw HeadsetError.readbackMismatch(key)
        }
        return update
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
        case 0x0031: key = .leAudioFeatureMode
        default: return nil
        }
        guard let definition = ShippingSettingReads.all[key] else { return nil }
        return [(key, try definition.decoder([response]))]
    }

    /// After a write may have reached the headset, performs qualified read-back
    /// and reports the observed state. Returns the error to throw and publishes
    /// observed values when decodable (AUD-007, WL5024-POST-AUD-002).
    private func writeRecoveryError(
        key: HeadsetSettingKey,
        qualification: WriteQualification,
        step: Int,
        earlierStepAcknowledged: Bool,
        underlying: any Error
    ) async -> any Error {
        var readBackResponses: [Data] = []
        do {
            for transaction in qualification.readBackTransactions {
                try Task.checkCancellation()
                readBackResponses.append(
                    try await transport.transact(transaction, timeout: .seconds(3))
                )
            }
            let observed = try qualification.readBackDecoder(readBackResponses)
            try applyConfirmedReadBack(
                key: key,
                storedValue: observed,
                responses: readBackResponses
            )
            snapshot.lastUpdated = .now
            _ = publish()
            DiagnosticRecorder.shared.record(
                "protocol-write",
                earlierStepAcknowledged
                    ? "Multi-step write partially applied"
                    : "Dispatched write outcome recovered",
                details: [
                    "setting": key.rawValue,
                    "failedStep": step.description,
                    "observed": String(describing: observed),
                    "error": underlying.localizedDescription,
                ]
            )
            let message = earlierStepAcknowledged
                ? "Part of the \(key.rawValue) change was applied (observed \(String(describing: observed))). Check the setting and try again."
                : "The \(key.rawValue) change could not be confirmed (observed \(String(describing: observed))). Check the setting and try again."
            return HeadsetError.transport(message)
        } catch is CancellationError {
            invalidateUnverifiedState(for: key)
            _ = publish()
            return CancellationError()
        } catch {
            invalidateUnverifiedState(for: key)
            _ = publish()
            DiagnosticRecorder.shared.record(
                "protocol-write",
                earlierStepAcknowledged
                    ? "Multi-step write failed with unreadable partial state"
                    : "Dispatched write failed with unreadable state",
                details: [
                    "setting": key.rawValue,
                    "failedStep": step.description,
                    "error": underlying.localizedDescription,
                    "readBackError": error.localizedDescription,
                ]
            )
            let message = earlierStepAcknowledged
                ? "Part of the \(key.rawValue) change may have been applied, but its current value could not be read. Refresh or reconnect before trying again."
                : "The \(key.rawValue) change may have been applied, but its current value could not be read. Refresh or reconnect before trying again."
            return HeadsetError.transport(message)
        }
    }

    private func invalidateCancelledWrite(
        key: HeadsetSettingKey,
        step: Int,
        gattWriteAcknowledged: Bool
    ) {
        invalidateUnverifiedState(for: key)
        _ = publish()
        DiagnosticRecorder.shared.record(
            "protocol-write",
            "Write cancelled after hardware state became uncertain",
            details: [
                "setting": key.rawValue,
                "step": step.description,
                "gattWriteAcknowledged": gattWriteAcknowledged.description,
            ]
        )
    }

    /// A wear-detection getter is one composite source of truth. Any
    /// confirmed read-back from that getter replaces all six projections
    /// atomically so sibling settings cannot retain a contradictory value.
    private func applyConfirmedReadBack(
        key: HeadsetSettingKey,
        storedValue: SettingValue,
        responses: [Data]
    ) throws {
        if ShippingWriteQualifications.wearKeys.contains(key) {
            guard responses.count == 1 else { throw HeadsetError.malformedResponse }
            let rawValue = try WL5024Command.getWearDetection
                .decodeWearDetectionFlags(from: responses[0])
            let flags = WearDetectionFlags(rawValue: rawValue)
            let projectedValues = try Dictionary(
                uniqueKeysWithValues: ShippingWriteQualifications.wearKeys.map { wearKey in
                    (wearKey, try flags.value(for: wearKey))
                }
            )
            for (wearKey, value) in projectedValues {
                snapshot.values[wearKey] = value
                snapshot.valueConfidence[wearKey] = .deviceConfirmed
                snapshot.readiness[wearKey] = .experimental
            }
            return
        }

        snapshot.values[key] = storedValue
        snapshot.valueConfidence[key] = .deviceConfirmed
    }

    /// Once a qualified write might have reached the headset, an unreadable
    /// read-back makes the affected source of truth unknown. Keep the write
    /// affordance available, but never retain an older value as confirmed.
    private func invalidateUnverifiedState(for key: HeadsetSettingKey) {
        let affectedKeys = ShippingWriteQualifications.wearKeys.contains(key)
            ? ShippingWriteQualifications.wearKeys
            : [key]
        for affectedKey in affectedKeys {
            snapshot.values.removeValue(forKey: affectedKey)
            snapshot.valueConfidence.removeValue(forKey: affectedKey)
            if case .connected(.bluetooth) = snapshot.connection,
               writeQualifications[affectedKey] != nil {
                snapshot.readiness[affectedKey] = .experimental
            } else {
                snapshot.readiness[affectedKey] = .unavailable
            }
        }
    }

    private func handle(_ update: TransportUpdate) {
        TransportStateReducer.apply(update, to: &snapshot)
        updateReadiness()

        if case .failed(_, let message, false) = update,
           snapshot.connection == .failed {
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

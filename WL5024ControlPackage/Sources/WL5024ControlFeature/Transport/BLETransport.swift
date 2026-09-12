import Foundation

@MainActor
final class BLETransport: RawHeadsetTransport {
    let kind = TransportKind.bluetooth
    private(set) var isReady = false
    private(set) var lifecycle: BluetoothLifecycleState = .stopped

    private let source: any BluetoothEventSourcing
    private let recorder: DiagnosticRecorder
    private var updateHandler: (@Sendable (TransportUpdate) -> Void)?
    private var activeIdentifier: UUID?
    private var pendingContinuation: CheckedContinuation<Data, any Error>?
    private var pendingRequestID: UUID?
    private var pendingMatcher: RaceResponseMatcher?
    private var pendingTracksDispatchFailure = false
    private var pendingRequestDispatched = false
    private var pendingWriteAcknowledged = false
    private var timeoutTask: Task<Void, Never>?
    private var responseQuarantine = RaceResponseQuarantine()

    init(source: any BluetoothEventSourcing = CoreBluetoothEventSource(), recorder: DiagnosticRecorder = .shared) {
        self.source = source
        self.recorder = recorder
    }

    func configure(updateHandler: @escaping @Sendable (TransportUpdate) -> Void) {
        self.updateHandler = updateHandler
    }

    func start() {
        source.start { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        activeIdentifier = nil
        recorder.setBluetoothConnection(nil)
        timeoutTask?.cancel()
        timeoutTask = nil
        isReady = false
        failPending(with: CancellationError())
        source.stop()
        isReady = false
        responseQuarantine.removeAll()
        transition(.stop)
    }

    func transact(_ transaction: TransportTransaction, timeout: Duration) async throws -> Data {
        try await transact(transaction, timeout: timeout, tracksDispatchFailure: false)
    }

    func transactWrite(_ transaction: TransportTransaction, timeout: Duration) async throws -> Data {
        try await transact(transaction, timeout: timeout, tracksDispatchFailure: true)
    }

    private func transact(
        _ transaction: TransportTransaction,
        timeout: Duration,
        tracksDispatchFailure: Bool
    ) async throws -> Data {
        try Task.checkCancellation()
        guard isReady, source.isReady else { throw HeadsetError.disconnected }
        guard pendingContinuation == nil else { throw HeadsetError.busy }
        guard !responseQuarantine.contains(transaction.expectedResponse) else {
            DiagnosticRecorder.shared.record(
                "bluetooth-tx",
                "RACE request blocked pending late-response drain",
                details: [
                    "opcode": String(format: "0x%04X", transaction.expectedResponse.opcode),
                    "module": transaction.expectedResponse.module.map {
                        String(format: "0x%04X", $0)
                    } ?? "none",
                ]
            )
            throw HeadsetError.transport(
                "A previous request may still reply. Reconnect the headset before retrying this command."
            )
        }

        DiagnosticRecorder.shared.record(
            "bluetooth-tx",
            "RACE request",
            details: ["bytes": DiagnosticRecorder.hex(transaction.request)]
        )

        let requestID = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                pendingContinuation = continuation
                pendingRequestID = requestID
                pendingMatcher = transaction.expectedResponse
                pendingTracksDispatchFailure = tracksDispatchFailure
                pendingRequestDispatched = false
                pendingWriteAcknowledged = false
                do {
                    try source.write(transaction.request)
                    guard pendingRequestID == requestID else { return }
                    pendingRequestDispatched = true
                } catch {
                    finishPending(with: .failure(error))
                    return
                }
                timeoutTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                        guard self?.pendingRequestID == requestID else { return }
                        DiagnosticRecorder.shared.record(
                            "bluetooth",
                            "RACE response timeout",
                            details: [
                                "gattWriteAcknowledged": String(self?.pendingWriteAcknowledged ?? false),
                            ]
                        )
                        self?.failPending(with: HeadsetError.timeout, requestID: requestID)
                    } catch is CancellationError {
                        // The response arrived or the transport stopped.
                    } catch {
                        self?.failPending(with: HeadsetError.timeout, requestID: requestID)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.failPending(with: CancellationError(), requestID: requestID)
            }
        }
    }

    private func handle(_ event: BluetoothAdapterEvent) {
        switch event {
        case .lifecycle(let event):
            transition(event)
        case .searching:
            updateHandler?(.searching(.bluetooth))
        case .ready(let metadata):
            activeIdentifier = metadata.identifier
            transition(.notificationsEnabled)
            recorder.setBluetoothConnection(metadata)
            isReady = false
            failPending(with: HeadsetError.disconnected)
            isReady = true
            // A new CoreBluetooth connection is a fresh protocol session.
            responseQuarantine.removeAll()
            updateHandler?(.connectedBluetooth(name: metadata.name, identifier: metadata.identifier))
        case .disconnected(let identifier):
            guard activeIdentifier == identifier else { return }
            activeIdentifier = nil
            transition(.setupFailed)
            recorder.setBluetoothConnection(nil)
            isReady = false
            failPending(with: HeadsetError.disconnected)
            updateHandler?(.bluetoothDisconnected(identifier: identifier))
        case .permissionDenied:
            activeIdentifier = nil
            transition(.stop)
            recorder.setBluetoothConnection(nil)
            isReady = false
            failPending(with: HeadsetError.disconnected)
            updateHandler?(.bluetoothPermissionDenied)
        case .unavailable:
            activeIdentifier = nil
            transition(.stop)
            recorder.setBluetoothConnection(nil)
            isReady = false
            failPending(with: HeadsetError.disconnected)
            updateHandler?(.bluetoothUnavailable)
        case .received(let data):
            guard isReady else { return }
            if responseQuarantine.drain(matching: data) {
                DiagnosticRecorder.shared.record(
                    "bluetooth-rx",
                    "Late response drained",
                    details: ["bytes": DiagnosticRecorder.hex(data)]
                )
                updateHandler?(.unsolicitedBluetooth(data))
                return
            }
            guard pendingContinuation != nil else {
                updateHandler?(.unsolicitedBluetooth(data))
                return
            }
            switch TransactionResponseRouter.classify(data, pending: pendingMatcher) {
            case .matched:
                finishPending(with: .success(data))
            case .ambiguousStatusOnly:
                // Never complete the pending request: the bytes cannot
                // identify their module, so completing would risk crediting a
                // late packet to the wrong module (AUD-008). The pending
                // transaction stays open until an exact match or timeout.
                DiagnosticRecorder.shared.record(
                    "bluetooth-rx",
                    "Ambiguous status-only response ignored",
                    details: ["bytes": DiagnosticRecorder.hex(data)]
                )
                updateHandler?(.unsolicitedBluetooth(data))
            case .unsolicited:
                updateHandler?(.unsolicitedBluetooth(data))
            }
        case .writeAcknowledged(let characteristic):
            pendingWriteAcknowledged = true
            DiagnosticRecorder.shared.record(
                "bluetooth-tx",
                "GATT write acknowledged",
                details: ["characteristic": characteristic]
            )
        case .writeFailed(let message):
            failPending(with: HeadsetError.transport(message))
        case .failed(let message, let willRetry):
            activeIdentifier = nil
            transition(willRetry ? .setupFailed : .stop)
            recorder.setBluetoothConnection(nil)
            isReady = false
            if pendingContinuation != nil {
                failPending(with: HeadsetError.transport(message))
            }
            updateHandler?(.failed(source: .bluetooth, message: message, willRetry: willRetry))
        }
    }

    private func failPending(with error: any Error, requestID: UUID? = nil) {
        if let requestID, pendingRequestID != requestID { return }
        // If a request left CoreBluetooth but its attributable response never
        // arrived while this session remains live, the protocol has no request
        // identifier that can separate a late response from an identical retry.
        if pendingRequestDispatched,
           isReady,
           source.isReady,
           let pendingMatcher {
            responseQuarantine.insert(pendingMatcher)
        }
        guard pendingTracksDispatchFailure, pendingRequestDispatched else {
            finishPending(with: .failure(error))
            return
        }
        finishPending(with: .failure(DispatchedTransactionError(
            underlying: error,
            gattWriteAcknowledged: pendingWriteAcknowledged
        )))
    }

    private func finishPending(with result: Result<Data, any Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let continuation = pendingContinuation else { return }
        pendingContinuation = nil
        pendingRequestID = nil
        pendingMatcher = nil
        pendingTracksDispatchFailure = false
        pendingRequestDispatched = false
        pendingWriteAcknowledged = false
        continuation.resume(with: result)
    }

    private func transition(_ event: BluetoothLifecycleEvent) {
        let next = BluetoothLifecyclePolicy.next(after: event)
        guard lifecycle != next else { return }
        lifecycle = next
        DiagnosticRecorder.shared.record(
            "bluetooth",
            "Lifecycle changed",
            details: ["state": String(describing: lifecycle)]
        )
    }
}

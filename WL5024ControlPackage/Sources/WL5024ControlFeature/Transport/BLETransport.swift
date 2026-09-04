import Foundation

@MainActor
final class BLETransport: RawHeadsetTransport {
    let kind = TransportKind.bluetooth
    private(set) var isReady = false
    private(set) var lifecycle: BluetoothLifecycleState = .stopped

    private let source: any BluetoothEventSourcing
    private var updateHandler: (@Sendable (TransportUpdate) -> Void)?
    private var pendingContinuation: CheckedContinuation<Data, any Error>?
    private var pendingMatcher: RaceResponseMatcher?
    private var pendingWriteAcknowledged = false
    private var timeoutTask: Task<Void, Never>?

    init(source: any BluetoothEventSourcing = CoreBluetoothEventSource()) {
        self.source = source
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
        timeoutTask?.cancel()
        timeoutTask = nil
        finishPending(with: .failure(CancellationError()))
        source.stop()
        isReady = false
        transition(.stop)
    }

    func transact(_ transaction: TransportTransaction, timeout: Duration) async throws -> Data {
        guard isReady, source.isReady else { throw HeadsetError.disconnected }
        guard pendingContinuation == nil else { throw HeadsetError.busy }

        DiagnosticRecorder.shared.record(
            "bluetooth-tx",
            "RACE request",
            details: ["bytes": DiagnosticRecorder.hex(transaction.request)]
        )

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingContinuation = continuation
                pendingMatcher = transaction.expectedResponse
                pendingWriteAcknowledged = false
                do {
                    try source.write(transaction.request)
                } catch {
                    finishPending(with: .failure(error))
                    return
                }
                timeoutTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                        DiagnosticRecorder.shared.record(
                            "bluetooth",
                            "RACE response timeout",
                            details: [
                                "gattWriteAcknowledged": String(self?.pendingWriteAcknowledged ?? false),
                            ]
                        )
                        self?.finishPending(with: .failure(HeadsetError.timeout))
                    } catch is CancellationError {
                        // The response arrived or the transport stopped.
                    } catch {
                        self?.finishPending(with: .failure(HeadsetError.timeout))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishPending(with: .failure(CancellationError()))
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
            isReady = true
            updateHandler?(.connectedBluetooth(name: metadata.name, identifier: metadata.identifier))
        case .disconnected(let identifier):
            isReady = false
            finishPending(with: .failure(HeadsetError.disconnected))
            updateHandler?(.bluetoothDisconnected(identifier: identifier))
        case .permissionDenied:
            isReady = false
            updateHandler?(.bluetoothPermissionDenied)
        case .unavailable:
            isReady = false
            updateHandler?(.bluetoothUnavailable)
        case .received(let data):
            guard pendingContinuation != nil,
                  TransactionResponseRouter.classify(data, pending: pendingMatcher) == .matched else {
                updateHandler?(.unsolicitedBluetooth(data))
                return
            }
            finishPending(with: .success(data))
        case .writeAcknowledged(let characteristic):
            pendingWriteAcknowledged = true
            DiagnosticRecorder.shared.record(
                "bluetooth-tx",
                "GATT write acknowledged",
                details: ["characteristic": characteristic]
            )
        case .writeFailed(let message):
            finishPending(with: .failure(HeadsetError.transport(message)))
        case .failed(let message, let willRetry):
            if pendingContinuation != nil {
                finishPending(with: .failure(HeadsetError.transport(message)))
            }
            updateHandler?(.failed(source: .bluetooth, message: message, willRetry: willRetry))
        }
    }

    private func finishPending(with result: Result<Data, any Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let continuation = pendingContinuation else { return }
        pendingContinuation = nil
        pendingMatcher = nil
        pendingWriteAcknowledged = false
        continuation.resume(with: result)
    }

    private func transition(_ event: BluetoothLifecycleEvent) {
        lifecycle = BluetoothLifecyclePolicy.next(after: event)
        DiagnosticRecorder.shared.record(
            "bluetooth",
            "Lifecycle changed",
            details: ["state": String(describing: lifecycle)]
        )
    }
}

import Foundation

/// Preserves the safety-relevant fact that a request reached CoreBluetooth
/// before its response path failed. Callers must not treat the prior device
/// value as authoritative after this error.
enum DispatchedTransactionError: Error, Sendable {
    case cancelled(gattWriteAcknowledged: Bool)
    case failed(HeadsetError, gattWriteAcknowledged: Bool)

    init(underlying: any Error, gattWriteAcknowledged: Bool) {
        if underlying is CancellationError {
            self = .cancelled(gattWriteAcknowledged: gattWriteAcknowledged)
        } else if let headsetError = underlying as? HeadsetError {
            self = .failed(headsetError, gattWriteAcknowledged: gattWriteAcknowledged)
        } else {
            self = .failed(
                .transport(underlying.localizedDescription),
                gattWriteAcknowledged: gattWriteAcknowledged
            )
        }
    }

    var isCancellation: Bool {
        if case .cancelled = self { true } else { false }
    }

    var gattWriteAcknowledged: Bool {
        switch self {
        case .cancelled(let acknowledged), .failed(_, let acknowledged): acknowledged
        }
    }
}

extension DispatchedTransactionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .cancelled:
            CancellationError().localizedDescription
        case .failed(let error, _):
            error.localizedDescription
        }
    }
}

@MainActor
protocol RawHeadsetTransport: AnyObject {
    var kind: TransportKind { get }
    var isReady: Bool { get }
    func configure(updateHandler: @escaping @Sendable (TransportUpdate) -> Void)
    func start()
    func stop()
    func transact(_ transaction: TransportTransaction, timeout: Duration) async throws -> Data
    func transactWrite(_ transaction: TransportTransaction, timeout: Duration) async throws -> Data
}

extension RawHeadsetTransport {
    func transactWrite(_ transaction: TransportTransaction, timeout: Duration) async throws -> Data {
        try await transact(transaction, timeout: timeout)
    }
}

@MainActor
protocol HeadsetTransporting: AnyObject {
    var activeKind: TransportKind? { get }
    func start(updateHandler: @escaping @Sendable (TransportUpdate) -> Void)
    func stop()
    func transact(_ transaction: TransportTransaction, timeout: Duration) async throws -> Data
    func transactWrite(_ transaction: TransportTransaction, timeout: Duration) async throws -> Data
}

extension HeadsetTransporting {
    func transactWrite(_ transaction: TransportTransaction, timeout: Duration) async throws -> Data {
        try await transact(transaction, timeout: timeout)
    }
}
